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

Each input carries a `tag` field — the **OCI artifact version**, decoupled from the
component (Helm chart) version — rendered directly into the generated
`OCIRepository.spec.ref.tag`. The build tags every artifact `:<tag>` plus `latest`.
The correspondence between the OCI version and each component version is recorded
in [`docs/versions.md`](versions.md); component chart versions stay pinned in each
`controllers/base/*.yaml` HelmRelease.

The `infra-configs` `Kustomization` is generated only for components that declare
`configs: "true"` (currently cert-manager and openbao), using the conditional
`fluxcd.controlplane.io/reconcile` annotation.

### Two-stage templating

1. **Build time** (`envsubst`): `${REGISTRY_HOST}`, `${REGISTRY_INSECURE}`,
   `${REPOSITORY}`, `${FLEET_VERSION}` are rendered into concrete values before the
   OCI artifacts are pushed. This is what lets the same repo target `ghcr.io` (prod)
   or a local zot (devbox), and lets boolean fields (e.g. `insecure`) render
   correctly. `${FLEET_VERSION}` bakes the fleet artifact `ref` into each
   `FluxInstance`. Component artifact versions (`tag`) come directly from the
   `ResourceSet` inputs.
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

## Sharding

The `prod` `FluxInstance` declares `spec.sharding` with four domain shards
(`shard-core`, `shard-security`, `shard-observability`, `shard-platform`). Each
tenant `ResourceSet` carries a `shard` input that is rendered into the
`sharding.fluxcd.io/key` label on the generated `OCIRepository` + `Kustomization`
(and propagated via `commonMetadata` to the `HelmRelease`s they apply). `staging`
runs unsharded. See [docs/sharding.md](sharding.md).
