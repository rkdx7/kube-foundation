# Versions — tableau de correspondance

La **version OCI** (artefact) est **découplée** de la version du **composant**
(chart Helm). Chaque artefact OCI est versionné indépendamment (`1.0.0`
initialement) ; la version est déclarée directement dans le champ `tag` de chaque
`ResourceSet` (`fleet/tenants/infra.yaml` et `fleet/tenants/apps.yaml`).

Ce tableau fait la correspondance entre la version OCI et la version du composant
déployée par l'artefact. Les versions de composants sont pinnées dans le champ
`version:` de chaque `controllers/base/*.yaml` (HelmRelease).

## Infrastructure

| Composant | Version OCI | Version composant (chart) |
|---|---|---|
| cilium | 1.0.0 | 1.20.2 |
| ingress-nginx | 1.0.0 | 4.15.1 |
| cert-manager | 1.0.0 | v1.21.2 |
| external-dns | 1.0.0 | 1.23.0 |
| external-secrets | 1.0.0 | 2.12.0 |
| openbao | 1.0.0 | 0.30.3 |
| kyverno | 1.0.0 | 3.9.1 |
| falco | 1.0.0 | 9.2.0 |
| trivy | 1.0.0 | 0.37.0 |
| istio | 1.0.0 | 1.30.5 |
| keda | 1.0.0 | 2.21.0 |
| velero | 1.0.0 | 12.2.1 |
| longhorn | 1.0.0 | 1.9.1 |
| monitoring | 1.0.0 | 92.2.0 (kube-prometheus-stack) / 3.14.0 (metrics-server) |
| loki | 1.0.0 | 7.3.0 |
| tempo | 1.0.0 | 1.24.4 |
| opentelemetry | 1.0.0 | 0.175.1 |
| vector | 1.0.0 | 0.59.0 |

## Applications

| Composant | Version OCI | Version composant |
|---|---|---|
| frontend | 1.0.0 | image `latest` (Go) |
| backend | 1.0.0 | redis / memcached (charts) |

## Comment versionner

- **Bumper un composant** : changer le `version:` dans son `controllers/base/*.yaml`,
  puis mettre à jour sa ligne dans ce tableau.
- **Bumper la version OCI d'un composant** : changer le `tag:` dans le `ResourceSet`
  correspondant (`fleet/tenants/infra.yaml` ou `apps.yaml`), puis mettre à jour sa
  ligne dans ce tableau.

Le build (`scripts/devbox.sh` et les workflows CI) lit le `tag` de chaque composant
dans le `ResourceSet` et tague l'artefact OCI avec cette valeur (+ `latest`).
