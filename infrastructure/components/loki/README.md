<p align="center">
  <img src="https://raw.githubusercontent.com/grafana/loki/main/docs/sources/logo.png" alt="Grafana Loki logo" width="180" />
</p>

# Loki

> **Site officiel** : https://grafana.com/oss/loki/
> **Documentation** : https://grafana.com/docs/loki/latest/
> **Chart Helm** : https://artifacthub.io/packages/helm/grafana/loki

## À quoi ça sert ?

**Loki** est le système d'**agrégation de logs** de Grafana, conçu pour fonctionner
en tandem avec Prometheus. Contrairement à un indexeur plein-texte (Elasticsearch),
Loki **n'indexe que les labels** et stocke les logs en tant que flux : beaucoup plus
léger en stockage et en CPU, et requête via le langage **LogQL** dans Grafana.

Dans ce dépôt, il reçoit les logs agrégés par **Vector** (l'agent de collecte).

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `loki` **7.3.0** (repo `https://grafana.github.io/helm-charts`) |
| Namespace | `loki` |
| `deploymentMode` | `SingleBinary` (mono-instance, mode dev) |
| `singleBinary.replicas` | `1` |
| `singleBinary.persistence` | `false` (pas de persistance) |
| `backend` / `read` / `write` | `replicas: 0` (mode scalable désactivé) |
| `loki.useTestSchema` | `true` |
| Stockage | **S3** (`type: s3`) → Ceph RGW `rook-ceph-rgw-rgw:80` (Rook), bucket `loki-data` |

Fichier clé : `controllers/base/loki.yaml` — la `HelmRelease`.

> Les chunks et l'index sont stockés dans **Ceph RGW** (object store S3 auto-hébergé
> via Rook, bucket `loki-data`), tandis que le WAL/ruler/compactor restent sur `/tmp`
> (emptyDir). Les credentials S3 sont injectés via `valuesFrom` (Secret
> `loki-s3-creds`, voir le README de Rook). Pour la prod, voir
> « Configurations à considérer ».

## Configurations à considérer

- **`deploymentMode: SimpleScalable`** : séparer read/write/backend pour la montée en charge.
- **Object storage** : S3, GCS ou Azure Blob (`loki.storage.type: s3` + bucket) au lieu
  du filesystem éphémère.
- **`singleBinary.persistence.enabled: true`** : garder les chunks sur un PVC (minimal).
- **Memcached** : cache des chunks et de l'index pour la perf.
- **`retention` / `compactor`** : rétention des logs et compaction.
- **Multi-tenancy** : `auth_enabled: true` + `X-Scope-OrgID` (tenant_id).
- **Ruler** : alertes LogQL.
- **Ingesteur d'agents** : brancher Promtail, Vector, Fluent Bit, ou l'OTel Collector.

## Mini-formation

1. Vérifier que Loki reçoit les logs (via Vector ici) :
   ```bash
   kubectl port-forward -n loki svc/loki 3100:3100 &
   curl http://localhost:3100/loki/api/v1/labels
   ```
2. Requêter avec LogQL :
   ```bash
   curl -G http://localhost:3100/loki/api/v1/query_range \
     --data-urlencode 'query={namespace="default"}' --data-urlencode 'limit=10'
   ```
3. Dans **Grafana** : ajouter une datasource Loki (`http://loki.loki.svc.cluster.local:3100`)
   puis explorer les logs avec LogQL.

## Dashboard

Pas d'interface dédiée : **Grafana** est l'UI de Loki (onglet « Explore », LogQL).
