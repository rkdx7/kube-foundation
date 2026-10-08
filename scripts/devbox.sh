#!/usr/bin/env bash
#
# devbox.sh — single-script local development and test harness for kube-foundation.
#
# It drives the whole Gitless-GitOps (D2) loop entirely offline:
#
#   registry start   Start a local OCI registry (zot) reachable from kind.
#   build            Build container images + package fleet/infrastructure/apps
#                    as OCI artifacts, then push them to the local registry.
#   cluster up       Create a kind cluster wired to the local registry.
#   bootstrap        Install Flux Operator (Helm), apply the FluxInstance and
#                    let Flux reconcile the OCI artifacts.
#   test             Wait for reconciliation and run smoke tests.
#   down             Tear everything down.
#   clean            Remove local state only.
#
# Requirements: docker, kind, kubectl, flux, helm, curl.
# Optional:       git (used for artifact metadata).
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBOX_DIR="${ROOT_DIR}/.devbox"
RENDER_DIR="${DEBOX_DIR}/rendered"

# ---------------------------------------------------------------------------
# Configuration (all overridable via environment variables)
# ---------------------------------------------------------------------------
REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
KIND_NETWORK="${KIND_NETWORK:-kind}"
CLUSTER_NAME="${CLUSTER_NAME:-kube-foundation}"
WORKERS="${WORKERS:-2}"

# OCI repository prefix used inside artifact URLs (no leading/trailing slash).
REPOSITORY="${REPOSITORY:-kube-foundation}"

# Local registry address used from the HOST (docker build/push).
REGISTRY_PUSH="localhost:${REGISTRY_PORT}"

# Local registry address used from INSIDE the cluster (Flux + kubelet).
# Resolved dynamically to the kind network gateway (the host IP on that network).
REGISTRY_PULL=""

# Flux distribution (installed by FluxInstance).
FLUX_VERSION="${FLUX_VERSION:-2.x}"

# zot container image.
ZOT_IMAGE="${ZOT_IMAGE:-ghcr.io/project-zot/zot-linux-amd64:v2.1.4}"

# Environment to render/bootstrap (staging or prod).
ENVIRONMENT="${ENVIRONMENT:-staging}"

# OCI artifact version tag. Pushed in addition to `latest` so the tenant
# ResourceSets can pin a specific version via `inputs.tag`.
VERSION="${VERSION:-latest}"

# Fleet artifact version baked into the FluxInstance `sync.ref`. Defaults to
# `latest`; set it per environment to pin the fleet release a cluster consumes.
FLEET_VERSION="${FLEET_VERSION:-latest}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m[devbox]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[devbox]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[devbox]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[devbox]\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

# ---------------------------------------------------------------------------
# Registry helpers
# ---------------------------------------------------------------------------
registry_running() {
  docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null | grep -q true
}

# The registry is attached to the kind network, so from inside the kind nodes it
# is reachable at its container IP on that network. This works for both rootful
# and rootless Docker, and the IP is known at build time (the network is created
# before the registry, and kind reuses it).
resolve_pull_host() {
  if [ -z "${REGISTRY_PULL}" ]; then
    local ip
    ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${REGISTRY_NAME}" 2>/dev/null || true)"
    if [ -z "${ip}" ]; then
      ip="$(docker network inspect "${KIND_NETWORK}" -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
    fi
    [ -z "${ip}" ] && die "could not determine the registry in-cluster address"
    REGISTRY_PULL="${ip}:${REGISTRY_PORT}"
  fi
  echo "${REGISTRY_PULL}"
}

ensure_network() {
  docker network inspect "${KIND_NETWORK}" >/dev/null 2>&1 || docker network create "${KIND_NETWORK}" >/dev/null
}

# ---------------------------------------------------------------------------
# Template rendering (build-time)
#
# We render ${REGISTRY_HOST}, ${REGISTRY_INSECURE} and ${REPOSITORY} everywhere
# before packaging, so each OCI artifact contains concrete, environment-specific
# manifests. Boolean fields (e.g. `insecure:`) render correctly too.
# ---------------------------------------------------------------------------
render_tree() {
  local src="$1" dst="$2" host="$3" insecure="$4" repo="$5"
  rm -rf "${dst}"
  mkdir -p "${dst}"
  cp -R "${src}/." "${dst}/"

  export REGISTRY_HOST="${host}"
  export REGISTRY_INSECURE="${insecure}"
  export REPOSITORY="${repo}"
  export FLEET_VERSION

  while IFS= read -r -d '' f; do
    # Only process textual files (skip binaries/images).
    if file -b --mime-encoding "$f" | grep -qE 'binary'; then
      continue
    fi
    envsubst '${REGISTRY_HOST} ${REGISTRY_INSECURE} ${REPOSITORY} ${FLEET_VERSION}' < "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
  done < <(find "${dst}" -type f -print0)
}

# ---------------------------------------------------------------------------
# Subcommand: registry
# ---------------------------------------------------------------------------
cmd_registry() {
  local action="${1:-start}"
  case "${action}" in
    start)
      need docker curl
      ensure_network
      if registry_running; then
        log "registry ${REGISTRY_NAME} already running"
        resolve_pull_host
        ok "registry reachable in-cluster at ${REGISTRY_PULL}"
        return 0
      fi

      log "starting zot registry (${REGISTRY_NAME}) on port ${REGISTRY_PORT}..."
      docker run -d \
        --name "${REGISTRY_NAME}" \
        --network "${KIND_NETWORK}" \
        -p "${REGISTRY_PORT}:${REGISTRY_PORT}" \
        -v "${DEBOX_DIR}/registry:/var/lib/registry" \
        -v "${ROOT_DIR}/config/registry/zot-config.json:/etc/zot/config.json:ro" \
        "${ZOT_IMAGE}" serve /etc/zot/config.json >/dev/null

      log "waiting for registry to become ready..."
      for _ in $(seq 1 60); do
        if curl -sf "http://localhost:${REGISTRY_PORT}/v2/" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      curl -sf "http://localhost:${REGISTRY_PORT}/v2/" >/dev/null 2>&1 \
        || die "registry did not become ready on port ${REGISTRY_PORT}"

      resolve_pull_host
      ok "registry running: host=${REGISTRY_PUSH} in-cluster=${REGISTRY_PULL}"
      ;;
    stop)
      if registry_running; then
        docker rm -f "${REGISTRY_NAME}" >/dev/null
        ok "registry stopped"
      else
        log "registry not running"
      fi
      ;;
    *)
      die "usage: $0 registry {start|stop}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Subcommand: build
# ---------------------------------------------------------------------------
cmd_build() {
  need docker flux envsubst file
  cmd_registry start >/dev/null
  resolve_pull_host
  local host="${REGISTRY_PULL}"
  local insecure="true"

  log "building container images (docker)..."
  docker build \
    -t "${REGISTRY_PUSH}/${REPOSITORY}/images/frontend:latest" \
    -f "${ROOT_DIR}/apps/components/frontend/app/Dockerfile" \
    "${ROOT_DIR}/apps/components/frontend/app"

  log "pushing images to ${REGISTRY_PUSH}..."
  docker push "${REGISTRY_PUSH}/${REPOSITORY}/images/frontend:latest" >/dev/null

  log "rendering templates (REGISTRY_HOST=${host} insecure=${insecure} REPOSITORY=${REPOSITORY})..."
  render_tree "${ROOT_DIR}/fleet" "${RENDER_DIR}/fleet" "${host}" "${insecure}" "${REPOSITORY}"

  # Source/revision metadata for OCI artifacts.
  local src rev
  src="$(git -C "${ROOT_DIR}" config --get remote.origin.url 2>/dev/null || echo "local")"
  rev="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "latest")"

  push_artifact() {
    local artifact="$1" path="$2"
    log "pushing artifact ${artifact}:${VERSION}"
    flux push artifact "${artifact}:${VERSION}" \
      --path="${path}" \
      --source="${src}" \
      --revision="${rev}" >/dev/null
    if [ "${VERSION}" != "latest" ]; then
      flux push artifact "${artifact}:latest" \
        --path="${path}" \
        --source="${src}" \
        --revision="${rev}" >/dev/null
    fi
  }

  log "packaging OCI artifacts..."

  # fleet (per cluster/environment)
  push_artifact "oci://${REGISTRY_PUSH}/${REPOSITORY}/fleet" "${RENDER_DIR}/fleet"

  # infrastructure components (one artifact per component, D2 style)
  local comp
  for comp in "${ROOT_DIR}"/infrastructure/components/*/; do
    [ -d "$comp" ] || continue
    local name
    name="$(basename "$comp")"
    render_tree "${comp}" "${RENDER_DIR}/infrastructure/${name}" "${host}" "${insecure}" "${REPOSITORY}"
    push_artifact "oci://${REGISTRY_PUSH}/${REPOSITORY}/infrastructure/${name}" "${RENDER_DIR}/infrastructure/${name}"
  done

  # app components
  for comp in "${ROOT_DIR}"/apps/components/*/; do
    [ -d "$comp" ] || continue
    local name
    name="$(basename "$comp")"
    render_tree "${comp}" "${RENDER_DIR}/apps/${name}" "${host}" "${insecure}" "${REPOSITORY}"
    push_artifact "oci://${REGISTRY_PUSH}/${REPOSITORY}/apps/${name}" "${RENDER_DIR}/apps/${name}"
  done

  ok "build complete (artifacts pushed to ${REGISTRY_PUSH}/${REPOSITORY})"
}

# ---------------------------------------------------------------------------
# Subcommand: cluster
# ---------------------------------------------------------------------------
cmd_cluster() {
  local action="${1:-up}"
  case "${action}" in
    up)
      need docker kind
      cmd_registry start >/dev/null
      resolve_pull_host
      local host_ip="${REGISTRY_PULL%:*}"

      mkdir -p "${DEBOX_DIR}"
      {
        cat <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
EOF
        for _ in $(seq 1 "${WORKERS}"); do
          echo "  - role: worker"
        done
        cat <<EOF
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${host_ip}:${REGISTRY_PORT}"]
    endpoint = ["http://${host_ip}:${REGISTRY_PORT}"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
    endpoint = ["http://${host_ip}:${REGISTRY_PORT}"]
EOF
      } > "${DEBOX_DIR}/kind-config.yaml"

      if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
        log "kind cluster ${CLUSTER_NAME} already exists"
      else
        log "creating kind cluster ${CLUSTER_NAME}..."
        kind create cluster --config "${DEBOX_DIR}/kind-config.yaml"
      fi

      log "waiting for nodes to be ready..."
      kubectl wait --for=condition=Ready nodes --all --timeout=300s

      # Workaround for hosts where net.ipv4.conf.all.arp_ignore=2 (e.g. Fedora):
      # it breaks kindnet's point-to-point pod ARP, so pods cannot reach their
      # gateway. Reset it on every interface of every node (all/default/veth/...).
      log "applying arp_ignore + inotify workarounds..."
      for node in $(docker ps --format '{{.Names}}' | grep "^${CLUSTER_NAME}-"); do
        docker exec "$node" sh -c \
          'for f in /proc/sys/net/ipv4/conf/*/arp_ignore; do echo 0 > "$f" 2>/dev/null || true; done'
        # Falco's engine needs more inotify instances than the default (128).
        docker exec "$node" sysctl -w fs.inotify.max_user_instances=1024 >/dev/null 2>&1 || true
      done

      ok "kind cluster ready (in-cluster registry: ${REGISTRY_PULL})"
      ;;
    down)
      need kind
      kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
      ok "kind cluster deleted"
      ;;
    *)
      die "usage: $0 cluster {up|down}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Subcommand: bootstrap
# ---------------------------------------------------------------------------
cmd_bootstrap() {
  need kubectl helm flux
  cmd_registry start >/dev/null
  resolve_pull_host

  local rendered="${RENDER_DIR}/fleet/clusters/${ENVIRONMENT}"
  [ -d "${rendered}" ] || die "no rendered fleet for environment '${ENVIRONMENT}' — run 'build' first"

  log "installing Flux Operator (Helm)..."
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  helm upgrade --install flux-operator \
    oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --namespace flux-system \
    --set multitenancy.enabled=true \
    --set multitenancy.defaultServiceAccount=flux-operator \
    --set reporting.interval=45s \
    --wait

  log "waiting for flux-operator deployment..."
  kubectl -n flux-system rollout status deploy/flux-operator --timeout=180s >/dev/null

  log "applying FluxInstance (ENVIRONMENT=${ENVIRONMENT}, registry=${REGISTRY_PULL})..."
  kubectl apply -f "${rendered}/flux-system/flux-instance.yaml"

  log "waiting for FluxInstance to become ready..."
  kubectl -n flux-system wait fluxinstance/flux --for=condition=ready --timeout=300s

  ok "bootstrap complete — Flux is reconciling the OCI artifacts"
}

# ---------------------------------------------------------------------------
# Subcommand: test
# ---------------------------------------------------------------------------
cmd_test() {
  need kubectl flux

  log "waiting for fleet Kustomizations..."
  kubectl -n flux-system wait kustomization/flux-system --for=condition=ready --timeout=600s || true
  kubectl -n flux-system wait kustomization/tenants --for=condition=ready --timeout=600s || true

  log "waiting for tenant ResourceSets..."
  for rs in infra apps; do
    kubectl -n flux-system wait resourceset/${rs} --for=condition=ready --timeout=600s || true
  done

  log "Flux resources:"
  flux get sources oci 2>/dev/null || kubectl get ocirepositories -A
  echo ""
  flux get kustomizations 2>/dev/null || true

  log "waiting for the demo frontend rollout..."
  kubectl -n frontend rollout status deploy/frontend --timeout=300s || true

  log "smoke test: port-forward the frontend and check /healthz"
  kubectl -n frontend port-forward svc/frontend 8080:8080 >/tmp/devbox-pf.log 2>&1 &
  local pf=$!
  sleep 3
  local status=""
  for _ in $(seq 1 20); do
    status="$(curl -sf http://localhost:8080/healthz 2>/dev/null || true)"
    [ -n "$status" ] && break
    sleep 1
  done
  kill "$pf" 2>/dev/null || true

  if [ "$status" = "ok" ]; then
    ok "smoke test passed: frontend /healthz returned '${status}'"
  else
    warn "frontend did not respond yet (got '${status}') — check 'kubectl -n frontend get pods'"
  fi

  ok "test phase complete"
}

# ---------------------------------------------------------------------------
# Subcommand: down / clean
# ---------------------------------------------------------------------------
cmd_down() {
  need kind docker
  kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
  docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  ok "down: kind cluster and registry removed"
}

cmd_clean() {
  rm -rf "${DEBOX_DIR}"
  ok "clean: removed ${DEBOX_DIR}"
}

# ---------------------------------------------------------------------------
# Help + dispatch
# ---------------------------------------------------------------------------
usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "${cmd}" in
    registry) cmd_registry "$@" ;;
    build)    cmd_build ;;
    cluster)  cmd_cluster "$@" ;;
    bootstrap) cmd_bootstrap ;;
    test)     cmd_test ;;
    down)     cmd_down ;;
    clean)    cmd_clean ;;
    help|-h|--help) usage ;;
    *) usage; die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
