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
#   openbao          Initialize + unseal + configure OpenBao (one-time).
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
# is reachable at its container IP on that network. We prefer the network's
# *gateway* address (the host's address on the kind bridge) because it is stable:
# the registry publishes its port on 0.0.0.0, so the nodes can always reach it at
# <gateway>:<port>, whereas the container's own IP is reassigned every time the
# registry container is recreated (which silently breaks every baked-in OCI URL
# and containerd mirror). Falls back to the container IP when the gateway is
# unavailable.
resolve_pull_host() {
  if [ -z "${REGISTRY_PULL}" ]; then
    local ip
    ip="$(docker network inspect "${KIND_NETWORK}" -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
    if [ -z "${ip}" ]; then
      ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${REGISTRY_NAME}" 2>/dev/null || true)"
    fi
    [ -z "${ip}" ] && die "could not determine the registry in-cluster address"
    REGISTRY_PULL="${ip}:${REGISTRY_PORT}"
  fi
  echo "${REGISTRY_PULL}"
}

ensure_network() {
  docker network inspect "${KIND_NETWORK}" >/dev/null 2>&1 || docker network create "${KIND_NETWORK}" >/dev/null
}

# The host kernel's fs.inotify.max_user_instances defaults to 128. The local loop
# runs many inotify consumers as root on the host: dockerd, the kind nodes
# (containerd/kubelet/cilium/falco inside each node) and the zot registry. When
# that budget is exhausted, zot panics at startup with "failed to create htpasswd
# watcher" (fsnotify.NewWatcher -> inotify_init -> EMFILE). Bump the host limit,
# mirroring what we already do inside the kind nodes for Falco.
ensure_host_inotify() {
  local current want=1024
  current="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"
  [ "${current}" -ge "${want}" ] && return 0

  if sysctl -w fs.inotify.max_user_instances="${want}" >/dev/null 2>&1; then
    ok "host fs.inotify.max_user_instances raised ${current} -> ${want}"
    return 0
  fi

  warn "host fs.inotify.max_user_instances is ${current} (want >= ${want})."
  die "run: sudo sysctl -w fs.inotify.max_user_instances=${want}"
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
      ensure_host_inotify
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
    local artifact="$1" path="$2" tag="$3"
    log "pushing artifact ${artifact}:${tag}"
    flux push artifact "${artifact}:${tag}" \
      --path="${path}" \
      --source="${src}" \
      --revision="${rev}" >/dev/null
    if [ "${tag}" != "latest" ]; then
      flux push artifact "${artifact}:latest" \
        --path="${path}" \
        --source="${src}" \
        --revision="${rev}" >/dev/null
    fi
  }

  # Read a component's OCI artifact tag from a tenant ResourceSet (the single
  # source of truth for the artifact version). Falls back to "latest".
  rs_tag() {
    local file="$1" component="$2" v
    v="$(awk -v c="${component}" '
      /^    - component:/ { comp=$0; sub(/.*component: "/,"",comp); sub(/".*/,"",comp) }
      comp == c && /^      tag:/ { t=$0; sub(/.*tag: "/,"",t); sub(/".*/,"",t); print t; exit }
    ' "${file}")"
    echo "${v:-latest}"
  }

  log "packaging OCI artifacts..."

  # fleet (per cluster/environment)
  push_artifact "oci://${REGISTRY_PUSH}/${REPOSITORY}/fleet" "${RENDER_DIR}/fleet" "${FLEET_VERSION}"

  # infrastructure components (one artifact per component, version from the ResourceSet)
  local comp
  for comp in "${ROOT_DIR}"/infrastructure/components/*/; do
    [ -d "$comp" ] || continue
    local name tag
    name="$(basename "$comp")"
    tag="$(rs_tag "${ROOT_DIR}/fleet/tenants/infra.yaml" "${name}")"
    render_tree "${comp}" "${RENDER_DIR}/infrastructure/${name}" "${host}" "${insecure}" "${REPOSITORY}"
    push_artifact "oci://${REGISTRY_PUSH}/${REPOSITORY}/infrastructure/${name}" "${RENDER_DIR}/infrastructure/${name}" "${tag}"
  done

  # app components (version from the ResourceSet)
  for comp in "${ROOT_DIR}"/apps/components/*/; do
    [ -d "$comp" ] || continue
    local name tag
    name="$(basename "$comp")"
    tag="$(rs_tag "${ROOT_DIR}/fleet/tenants/apps.yaml" "${name}")"
    render_tree "${comp}" "${RENDER_DIR}/apps/${name}" "${host}" "${insecure}" "${REPOSITORY}"
    push_artifact "oci://${REGISTRY_PUSH}/${REPOSITORY}/apps/${name}" "${RENDER_DIR}/apps/${name}" "${tag}"
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

  # Once the FluxInstance's `flux-operator` ResourceSet has been applied, Flux
  # self-manages the operator via its own HelmRelease. Re-running the manual
  # `helm upgrade --install` then conflicts with helm-controller over the
  # `helm.sh/chart` field ownership, so skip it when the operator is already
  # self-managed. On a fresh cluster (no HelmRelease) the manual install still
  # bootstraps the operator before the FluxInstance is applied.
  if kubectl -n flux-system get helmrelease flux-operator >/dev/null 2>&1; then
    log "flux-operator already self-managed by Flux — skipping manual Helm install"
  else
    helm upgrade --install flux-operator \
      oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
      --namespace flux-system \
      --set multitenancy.enabled=true \
      --set multitenancy.defaultServiceAccount=flux-operator \
      --set reporting.interval=45s \
      --wait
  fi

  log "waiting for flux-operator deployment..."
  kubectl -n flux-system rollout status deploy/flux-operator --timeout=180s >/dev/null

  log "applying FluxInstance (ENVIRONMENT=${ENVIRONMENT}, registry=${REGISTRY_PULL})..."
  kubectl apply -f "${rendered}/flux-system/flux-instance.yaml"

  log "waiting for FluxInstance to become ready..."
  kubectl -n flux-system wait fluxinstance/flux --for=condition=ready --timeout=300s

  ok "bootstrap complete — Flux is reconciling the OCI artifacts"
}

# ---------------------------------------------------------------------------
# Subcommand: openbao
# ---------------------------------------------------------------------------
# One-time OpenBao bootstrap for the local devbox: initialize the Shamir seal,
# unseal every HA replica (created one at a time by the ordered StatefulSet),
# enable the KV v2 engine + Kubernetes auth method that the External Secrets
# Operator expects, then write the demo secret. Idempotent.
cmd_openbao() {
  need kubectl

  log "waiting for OpenBao pods to be created..."
  kubectl -n openbao wait --for=jsonpath='{.status.phase}'=Running pod/openbao-0 --timeout=600s >/dev/null 2>&1 \
    || die "openbao-0 not running — is the OpenBao component reconciled?"

  local unseal_key root_token initialized sealed pod

  initialized="$(openbao_field openbao-0 '^Initialized')"

  if [ "${initialized}" = "true" ]; then
    log "OpenBao already initialized"
  else
    log "initializing OpenBao (1 unseal key, threshold 1)..."
    local init_out
    init_out="$(kubectl -n openbao exec openbao-0 -- bao operator init -key-shares=1 -key-threshold=1 -format=json 2>/dev/null)"
    # `bao -format=json` pretty-prints, so the unseal key sits on the line after
    # "unseal_keys_b64" and the root token on the "root_token" line.
    unseal_key="$(printf '%s' "$init_out" | grep -A1 'unseal_keys_b64' | tail -1 | tr -d ' ",\n\t')"
    root_token="$(printf '%s' "$init_out" | grep 'root_token' | tr -d ' ",\n\t' | sed 's/^.*root_token://')"
    [ -z "${unseal_key}" ] && die "failed to parse the OpenBao unseal key from init output"
    kubectl -n openbao create secret generic openbao-bootstrap \
      --from-literal=unseal-key="${unseal_key}" \
      --from-literal=root-token="${root_token}" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  fi

  unseal_key="$(kubectl -n openbao get secret openbao-bootstrap -o jsonpath='{.data.unseal-key}' 2>/dev/null | base64 -d)"
  root_token="$(kubectl -n openbao get secret openbao-bootstrap -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d)"
  [ -z "${unseal_key}" ] && die "openbao-bootstrap secret missing"

  # Unseal each replica as the ordered StatefulSet creates it (openbao-1 and
  # openbao-2 are only scheduled once openbao-0 becomes Ready).
  for pod in openbao-0 openbao-1 openbao-2; do
    log "waiting for ${pod} to be running..."
    for _ in $(seq 1 120); do
      kubectl -n openbao get pod "${pod}" >/dev/null 2>&1 && break
      sleep 5
    done
    kubectl -n openbao get pod "${pod}" >/dev/null 2>&1 || { warn "${pod} not created yet"; continue; }

    sealed="$(openbao_field "${pod}" '^Sealed')"
    if [ "${sealed}" = "true" ]; then
      log "unsealing ${pod}..."
      kubectl -n openbao exec "${pod}" -- bao operator unseal "${unseal_key}" >/dev/null 2>&1 || true
      kubectl -n openbao wait --for=condition=Ready pod "${pod}" --timeout=120s >/dev/null 2>&1 || true
    else
      log "${pod} already unsealed"
    fi
  done

  # Configure (idempotent): login + KV v2 + kubernetes auth + eso role + demo secret.
  log "configuring OpenBao (KV v2 'apps', kubernetes auth, 'eso' role, demo secret)..."
  kubectl -n openbao exec openbao-0 -- bao login "${root_token}" >/dev/null 2>&1 || true
  kubectl -n openbao exec openbao-0 -- bao secrets enable -path=apps kv-v2 2>/dev/null || true
  kubectl -n openbao exec openbao-0 -- bao auth enable kubernetes 2>/dev/null || true
  printf 'path "apps/data/*" { capabilities = ["read"] }\n' \
    | kubectl -n openbao exec -i openbao-0 -- bao policy write eso - >/dev/null 2>&1 || true
  kubectl -n openbao exec openbao-0 -- bao write auth/kubernetes/role/eso \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=eso ttl=1h >/dev/null 2>&1 || true
  kubectl -n openbao exec openbao-0 -- bao kv put apps/demo/app password=s3cr3t >/dev/null 2>&1 || true

  ok "OpenBao initialized, unsealed and configured"
}

# Read a field from `bao status` (e.g. '^Initialized' or '^Sealed').
# `bao status` exits non-zero (2) when the node is sealed/uninitialized, so the
# pipeline is guarded with `|| true` to avoid tripping `set -e` + `pipefail`.
openbao_field() {
  local pod="$1" pattern="$2"
  kubectl -n openbao exec "${pod}" -- bao status 2>/dev/null \
    | grep -E "${pattern}" | awk '{print $2}' | head -1 || true
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
  # zot writes its registry blobs as root inside the bind-mounted
  # `.devbox/registry`, so the host user cannot `rm -rf` them. Remove the tree
  # via a disposable container (which runs as root), then fall back to a plain
  # `rm -rf` for anything left over.
  if [ -d "${DEBOX_DIR}" ]; then
    docker run --rm -v "${DEBOX_DIR}:/devbox" alpine:3.20 \
      sh -c 'rm -rf /devbox/* /devbox/.[!.]*' >/dev/null 2>&1 || true
    rm -rf "${DEBOX_DIR}"
  fi
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
    openbao)   cmd_openbao ;;
    test)     cmd_test ;;
    down)     cmd_down ;;
    clean)    cmd_clean ;;
    help|-h|--help) usage ;;
    *) usage; die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
