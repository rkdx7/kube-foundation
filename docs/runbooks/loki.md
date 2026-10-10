# Loki — Runbook

> **Code** : `infrastructure/components/loki/` · **Version** : `loki` **7.3.0**
> **Namespace Flux** : `loki` · **Namespace pods** : `loki` · **Shard (prod)** : `shard-observability`
> Voir : [README du composant](../../infrastructure/components/loki/README.md)

## Rôle

Loki est le backend d'**agrégation de logs** (LogQL). Il reçoit les logs collectés par
**Vector**. Une panne = perte de visibilité sur les logs (pas d'impact applicatif direct).

## Infos clés

| | |
|---|---|
| Namespace(s) | `loki` |
| Mode | `SingleBinary`, `replicas: 1`, persistance **désactivée** |
| Stockage | S3 → Ceph RGW `rook-ceph-rgw-rgw:80`, bucket `loki-data` |
| Dépendances | Rook (S3), Vector (ingest) |

## Vérifications de santé

```bash
kubectl -n loki get pods
kubectl -n loki logs deploy/loki --tail=50
kubectl -n loki port-forward svc/loki 3100:3100 &
curl -s http://localhost:3100/ready     # doit renvoyer "ready"
curl -s http://localhost:3100/loki/api/v1/labels
```

Signes de bonne santé : pod `Running`, `/ready` → `ready`, les `labels` remontent des
namespaces (preuve que Vector alimente Loki).

## Opérations courantes

- **Requêter (LogQL)** :
  ```bash
  curl -G http://localhost:3100/loki/api/v1/query_range \
    --data-urlencode 'query={namespace="default"}' --data-urlencode 'limit=10'
  ```
- **Vérifier l'ingestion** : `curl http://localhost:3100/loki/api/v1/labels`
- **Explorer dans Grafana** : datasource Loki `http://loki.loki.svc.cluster.local:3100`, onglet « Explore ».
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n loki
  flux reconcile kustomization infra-controllers -n loki
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Aucun log récent | Vector n'ingère pas / S3 injoignable | Vérifier Vector, puis Rook/S3 |
| `S3` inaccessible | Ceph RGW down / credentials | Voir le runbook [rook](rook.md) |
| Erreurs de quota/stockage | Pas de persistance + bucket plein | Vérifier le bucket `loki-data`, activer la rétention |
| Perf dégradée | `SingleBinary` sous-dimensionné | Passer en `SimpleScalable` + memcached |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/loki.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `/ready` → `ready` + requête LogQL.

## Sauvegarde / restauration

Logs = données dans Ceph RGW (bucket `loki-data`). Pas de backup dédié ; si les logs
sont critiques, prévoir rétention + réplication du bucket S3.

## Métriques & alertes

Métriques `loki_*` (ingestion rate, erreurs). Alerte : Loki down, taux d'erreurs
d'ingestion élevé, retards de lecture.
