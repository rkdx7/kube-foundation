# Sharding (prod)

The `prod` cluster is sharded so that the Flux controllers scale out horizontally
and the reconciliation workload is isolated per domain. Sharding is configured
declaratively on the `FluxInstance` and applied to tenant workloads via the
`sharding.fluxcd.io/key` label.

## How it works

1. `fleet/clusters/prod/flux-system/flux-instance.yaml` declares
   `spec.sharding.key` and `spec.sharding.shards`. For each shard the Flux Operator
   provisions a dedicated set of controllers (`source-controller`,
   `kustomize-controller`, `helm-controller`, … suffixed with the shard name), each
   watching only the resources carrying `sharding.fluxcd.io/key=<shard>`.
   Unlabelled resources are reconciled by the **main** (unsharded) controllers, which
   keep reconciling the fleet bootstrap (`flux-system` + `tenants` Kustomizations,
   the `ResourceSet`s and the operator self-management).

2. `fleet/tenants/infra.yaml` and `fleet/tenants/apps.yaml` assign each component an
   `shard` input. The `ResourceSet` renders that value into the generated
   `OCIRepository` and `Kustomization` labels, and into each `Kustomization`'s
   `commonMetadata.labels`, which propagates the label to everything the
   `Kustomization` applies (the `HelmRelease`s and their `HelmRepository` /
   `OCIRepository` chart sources inside the artifact).

   > Flux resources that reference each other must share the same shard label. Here
   > the whole chain — `OCIRepository` → `Kustomization` → `HelmRelease` +
   > `HelmRepository` — is generated from a single `shard` input, so it always stays
   > consistent.

## Shard layout

| Shard | Domain | Components |
|---|---|---|
| `shard-core` | Networking, ingress & TLS | cilium, kube-vip, kgateway, cert-manager, external-dns |
| `shard-security` | Secrets, policy & runtime security | external-secrets, openbao, kyverno, falco, trivy |
| `shard-observability` | Monitoring, logs & traces | monitoring, loki, tempo, opentelemetry, vector |
| `shard-platform` | Mesh, autoscaling, storage, backup & apps | istio, keda, stakater, velero, rook, frontend, backend |

## Staging

`staging` deliberately runs **unsharded**: its `FluxInstance` has no `spec.sharding`,
so the `sharding.fluxcd.io/key` labels rendered into its tenant resources are inert
and everything is reconciled by the main controllers. This keeps the dev/CI loop
simple while exercising the exact same `ResourceSet` templates as prod.

## Adding a shard or reassigning a component

- **Add/remove a shard**: edit `spec.sharding.shards` in the prod `FluxInstance`.
- **Reassign a component**: change its `shard` input in `fleet/tenants/*.yaml`
  (e.g. move `rook` from `shard-platform` to `shard-core`). The next fleet
  reconciliation regenerates the sources/Kustomizations with the new label.

## Verification

```bash
# the sharded controllers (one set per shard)
kubectl -n flux-system get deploy -l app.kubernetes.io/part-of=flux

# resources assigned to a given shard
flux get all -A -l sharding.fluxcd.io/key=shard-core
```

See the upstream reference:
[Controllers sharding](https://fluxoperator.dev/docs/instance/sharding) and
[Flux sharding and horizontal scaling](https://fluxcd.io/flux/installation/configuration/sharding).
