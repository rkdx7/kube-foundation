# Architecture

`kube-foundation` implements the **Flux D2** (Gitless GitOps) reference architecture
in a single monorepo, driven by the **Flux Operator**.

## Key concepts

### FluxInstance (not `flux bootstrap`)

The Flux controllers are installed, configured and auto-upgraded declaratively via a
single `FluxInstance` CR, instead of `flux bootstrap`:

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
spec:
  distribution: { version: "2.x", registry: "ghcr.io/fluxcd" }
  cluster: { multitenant: true, tenantDefaultServiceAccount: flux }
  sync:
    kind: OCIRepository
    url: oci://${REGISTRY_HOST}/${REPOSITORY}/fleet
    ref: latest
    path: clusters/staging
```

The `sync` block generates the `flux-system` `OCIRepository` + `Kustomization` that
pull the **fleet artifact** from the registry.

### ResourceSet

Tenant resources are generated from a matrix of inputs + templated resources:

- `fleet/tenants/infra.yaml` — one namespace + `OCIRepository` + `Kustomization` per
  infrastructure component (cilium, istio, openbao, ...).
- `fleet/tenants/apps.yaml` — one namespace + source + `Kustomization` per app
  (frontend, backend).

Each input carries a `tag` field (`latest` by default) rendered into the generated
`OCIRepository.spec.ref.tag`, so every component can pin its own artifact version
(e.g. `tag: "1.2.3"`). Versioned tags are produced by `release-artifact.yaml` (git
tags `v*`), `push-artifact.yaml` (git SHA + `latest`), and locally by
`scripts/devbox.sh build` (`VERSION`, plus `latest`).

The `infra-configs` `Kustomization` is generated only for components that declare
`configs: "true"` (currently cert-manager and openbao), using the conditional
`fluxcd.controlplane.io/reconcile` annotation.

### Two-stage templating

1. **Build time** (`envsubst`): `${REGISTRY_HOST}`, `${REGISTRY_INSECURE}`,
   `${REPOSITORY}`, `${FLEET_VERSION}` are rendered into concrete values before the
   OCI artifacts are pushed. This is what lets the same repo target `ghcr.io` (prod)
   or a local zot (devbox), and lets boolean fields (e.g. `insecure`) render
   correctly. `${FLEET_VERSION}` bakes the fleet artifact `ref` into each
   `FluxInstance`.
2. **Reconcile time** (Flux `postBuild.substituteFrom`): `${ENVIRONMENT}`,
   `${CLUSTER_NAME}`, `${CLUSTER_DOMAIN}` are substituted per cluster from the
   `flux-runtime-info` ConfigMap.

## Reconciliation flow

```
bootstrap:
  helm install flux-operator ──▶ operator installed
  apply FluxInstance ──▶ Flux controllers installed + flux-system OCIRepository/Kustomization

steady state:
  flux-system Kustomization ──▶ fleet artifact (clusters/<env>)
     ├─ FluxInstance (self-reconciled)
     ├─ ResourceSet flux-operator (self-managed operator upgrade)
     ├─ flux-runtime-info ConfigMap
     └─ Kustomization tenants ──▶ fleet/tenants
          ├─ ResourceSet infra ──▶ 17 component namespaces + OCIRepository + Kustomization
          └─ ResourceSet apps  ──▶ frontend/backend namespaces + sources
```

Each component's `Kustomization` then reconciles its own OCI artifact:

- `infra-controllers` → `./controllers/<env>` (the HelmReleases)
- `infra-configs`   → `./configs/<env>` (post-install config, e.g. ClusterIssuers)
- `apps`            → `./<env>` (Deployments, Services, Ingress)

## Multi-tenancy

`FluxInstance.cluster.multitenant: true` enables Flux multi-tenancy lockdown.
Each infra component runs under a `cluster-admin`-bound `flux` ServiceAccount; each
app runs under a namespace-scoped `admin`-bound ServiceAccount (least privilege).
