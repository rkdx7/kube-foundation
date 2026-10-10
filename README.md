# kube-foundation

A production-ready, **Gitless-GitOps** reference platform built on **Flux Operator**
and the **Flux D2 architecture**, packing the full CNCF stack (observability, security,
service mesh, secrets, storage, autoscaling, backup) into a single monorepo.

Everything is reconciled from **signed OCI artifacts** — clusters never talk to Git.
A single script (`scripts/devbox.sh`) spins up a local OCI registry, builds the
artifacts, boots a kind cluster, and verifies the whole deployment end-to-end.

---

## Architecture (D2 — Gitless GitOps)

```
 git (kube-foundation) ──CI──▶ OCI registry ──▶ clusters (staging / prod)
        fleet/                  oci://reg/fleet        Flux Operator + FluxInstance
        infrastructure/         oci://reg/infrastructure/<component>
        apps/                   oci://reg/apps/<component>
```

The desired state lives in **OCI artifacts**, produced from this Git repository by CI
(`flux push artifact` + `cosign sign`). Clusters reconcile those artifacts via
**`FluxInstance`** (declarative Flux install) and **`ResourceSet`** (self-service,
templated resource generation), matching the [Flux D2 reference architecture](https://fluxcd.control-plane.io/guides/d2-architecture-reference).

| Layer | Role | Contents |
|---|---|---|
| `fleet/` | Platform team only | `FluxInstance`, self-managed operator, tenant `ResourceSet`s |
| `infrastructure/` | Cluster add-ons | 17 CNCF components (controllers + per-env configs) |
| `apps/` | App delivery | Demo frontend (Go) + backend (redis/memcached) |

## Included components

| Domain | Components |
|---|---|
| GitOps | Flux Operator (`FluxInstance`, `ResourceSet`) |
| Networking | Cilium (CNI + Hubble) |
| Ingress & TLS | kgateway, cert-manager, ExternalDNS |
| Service mesh | Istio (base, istiod, gateway) |
| Observability | kube-prometheus-stack (Prometheus/Grafana/Alertmanager), Loki, Tempo, OpenTelemetry Collector, Vector (log agent), metrics-server |
| Secrets | External Secrets Operator + SOPS (age), OpenBao (Vault fork, HA) |
| Security & policy | Kyverno, Falco, Trivy |
| Storage | Rook/Ceph (on-prem block + S3 object store via RGW) + cloud CSI (documented) |
| Autoscaling | KEDA |
| Backup/DR | Velero |

## Repository layout

```
├── fleet/                        # == d2-fleet
│   ├── clusters/{staging,prod}/  # per-cluster FluxInstance + runtime info
│   └── tenants/                  # infra + apps ResourceSets
├── infrastructure/
│   └── components/<name>/        # controllers/{base,staging,prod} + configs/
├── apps/
│   └── components/{frontend,backend}/
├── scripts/devbox.sh             # THE script (registry/build/cluster/bootstrap/test)
├── config/{age,registry}/        # SOPS keys + zot config
├── .sops.yaml
└── .github/workflows/            # validate / push-artifact / release-artifact
```

---

## Quick start (local, end-to-end)

> Requires: `docker`, `kind`, `kubectl`, `flux`, `helm`, `curl`.

```bash
make devbox
```

This runs, in order:

1. `registry start` — starts a local **zot** OCI registry (HTTP, `:5000`).
2. `build` — builds the frontend image + packages `fleet`/`infrastructure`/`apps`
   as OCI artifacts, pushes them to the local registry.
3. `cluster up` — creates a **kind** cluster wired to the registry.
4. `bootstrap` — installs Flux Operator (Helm), applies the `FluxInstance`, Flux
   reconciles the OCI artifacts.
5. `test` — waits for reconciliation and smoke-tests the frontend.

Individual steps are also available:

```bash
./scripts/devbox.sh registry start
./scripts/devbox.sh build
./scripts/devbox.sh cluster up
./scripts/devbox.sh bootstrap
./scripts/devbox.sh test
./scripts/devbox.sh down
```

The local loop uses a plain-HTTP registry reachable from kind; this is purely for
offline development. Production uses `ghcr.io` with cosign verification (see
[Production bootstrap](#production-bootstrap)).

---

## Production bootstrap

Each environment is bootstrapped the same way as locally, but against `ghcr.io`:

```bash
export GITHUB_TOKEN=...
export GITHUB_USER=...

# 1. Build + push artifacts (or let CI do it on push to main)
#    -> oci://ghcr.io/<org>/kube-foundation/fleet, .../infrastructure/<c>, .../apps/<c>

# 2. Point a cluster at the repo, install the operator and the FluxInstance
helm upgrade --install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  -n flux-system --create-namespace \
  --set multitenancy.enabled=true \
  --set multitenancy.defaultServiceAccount=flux-operator

# 3. Render the fleet with your registry (REGISTRY_HOST=ghcr.io, INSECURE=false)
#    and apply the FluxInstance for the target environment:
#      fleet/clusters/<staging|prod>/flux-system/flux-instance.yaml
```

See [docs/bootstrap.md](docs/bootstrap.md) for the full multi-cloud procedure.

---

## Secrets (SOPS + External Secrets Operator)

- **SOPS + age**: sensitive values are encrypted in Git (`.sops.yaml`) and decrypted
  at reconcile time by Flux.
- **External Secrets Operator**: syncs secrets from cloud Secret Managers
  (AWS Secrets Manager / GCP Secret Manager / Azure Key Vault) into the cluster via
  `ExternalSecret` + `ClusterSecretStore`.

See [docs/secrets.md](docs/secrets.md).

## Multi-cloud

`staging` and `prod` are environment folders; each component has `controllers/` and
`configs/` overlays. Cloud-specific pieces (storage CSI drivers, ExternalDNS provider,
External Secrets store, Velero backend) are selected per provider — see
[docs/multi-cloud.md](docs/multi-cloud.md).

## Sharding

The `prod` cluster is horizontally sharded (4 domain shards) so Flux reconciliation
scales out and stays isolated per domain. `staging` stays unsharded. See
[docs/sharding.md](docs/sharding.md).

## Documentation

- [docs/architecture.md](docs/architecture.md) — how the pieces fit together
- [docs/bootstrap.md](docs/bootstrap.md) — production & multi-cloud bootstrap
- [docs/secrets.md](docs/secrets.md) — SOPS + ESO
- [docs/multi-cloud.md](docs/multi-cloud.md) — AWS / GCP / Azure / on-prem
- [docs/sharding.md](docs/sharding.md) — horizontal sharding of the prod cluster

## License & attribution

This repository is [MIT](LICENSE). It is based on the
[Flux D2 reference architecture](https://fluxcd.control-plane.io/guides/d2-architecture-reference)
by ControlPlane. Note that `flux-operator` itself is licensed under
**AGPL-3.0** — review its terms if you redistribute it.
