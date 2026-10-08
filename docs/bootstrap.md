# Bootstrap

Two bootstrap paths exist: **local devbox** (kind + zot) and **production**
(cloud cluster + `ghcr.io`).

## Prerequisites

- `flux` CLI (>= 2.2), `kubectl`, `helm`
- `docker`, `kind` (local only)

## Local (devbox)

```bash
make devbox
# or step by step:
./scripts/devbox.sh registry start
./scripts/devbox.sh build
./scripts/devbox.sh cluster up
./scripts/devbox.sh bootstrap
./scripts/devbox.sh test
```

Environment variables (optional):

| Variable | Default | Description |
|---|---|---|
| `ENVIRONMENT` | `staging` | `staging` or `prod` (which fleet path to bootstrap) |
| `FLEET_VERSION` | `latest` | fleet artifact `ref` baked into the `FluxInstance` |
| `REGISTRY_PORT` | `5000` | local registry port |
| `CLUSTER_NAME` | `kube-foundation` | kind cluster name |
| `REPOSITORY` | `kube-foundation` | OCI repository prefix |

## Production (cloud)

### 1. Build & push artifacts

CI does this automatically on push to `main` (`.github/workflows/push-artifact.yaml`),
rendering with `REGISTRY_HOST=ghcr.io`, `REGISTRY_INSECURE=false`,
`REPOSITORY=<org>/kube-foundation`, then pushing and cosign-signing:

- `oci://ghcr.io/<org>/kube-foundation/fleet`
- `oci://ghcr.io/<org>/kube-foundation/infrastructure/<component>`
- `oci://ghcr.io/<org>/kube-foundation/apps/<component>`

### 2. Install the operator

```bash
helm upgrade --install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  -n flux-system --create-namespace \
  --set multitenancy.enabled=true \
  --set multitenancy.defaultServiceAccount=flux-operator \
  --set reporting.interval=45s \
  --wait
```

### 3. Apply the FluxInstance

Render `fleet/clusters/<env>/` with your registry values and apply the FluxInstance:

```bash
export REGISTRY_HOST=ghcr.io REGISTRY_INSECURE=false REPOSITORY=<org>/kube-foundation FLEET_VERSION=latest

# render the FluxInstance (same substitution CI does)
envsubst '${REGISTRY_HOST} ${REGISTRY_INSECURE} ${REPOSITORY} ${FLEET_VERSION}' \
  < fleet/clusters/prod/flux-system/flux-instance.yaml \
  | kubectl apply -f -
```

> If the artifacts are private, create an image-pull secret in `flux-system` and
> reference it in the FluxInstance `sync.pullSecret`.

### 4. Verify

```bash
kubectl -n flux-system get fluxinstance flux
kubectl -n flux-system get kustomizations
flux get sources oci
```

## Enabling cosign verification

The artifacts are signed in CI. To enforce verification at reconcile time, add the
following to the `FluxInstance.spec.kustomize.patches` (and to the tenant
`OCIRepository` templates in `fleet/tenants/*.yaml`):

```yaml
- op: add
  path: /spec/verify
  value:
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token\.actions\.githubusercontent\.com$
        subject: ^https://github\.com/<org>/kube-foundation/\.github/workflows/push-artifact\.yaml@refs/heads/main$
```

Verification is disabled by default so the local devbox (plain-HTTP zot, no OIDC)
works out of the box.
