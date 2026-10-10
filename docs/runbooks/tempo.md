# Tempo — Runbook

> **Code** : `infrastructure/components/tempo/` · **Version** : `tempo` **1.24.4**
> **Namespace Flux** : `tempo` · **Namespace pods** : `tempo` · **Shard (prod)** : `shard-observability`
> Voir : [README du composant](../../infrastructure/components/tempo/README.md)

## Rôle

Tempo est le backend de **tracing distribué** (TraceQL). Il reçoit les traces OTLP de
l'OpenTelemetry Collector. Une panne = perte de visibilité sur les traces.

## Infos clés

| | |
|---|---|
| Namespace(s) | `tempo` |
| Receivers | OTLP gRPC `4317`, HTTP `4318` |
| Dépendances | OpenTelemetry Collector (amont) |
| ⚠️ Stockage | local éphémère par défaut (à brancher sur S3 en prod) |

## Vérifications de santé

```bash
kubectl -n tempo get pods
kubectl -n tempo logs deploy/tempo --tail=50
kubectl -n tempo port-forward svc/tempo 3200:3200 &
curl -s "http://localhost:3200/api/search"
```

Signes de bonne santé : pod `Running`, `/api/search` répond, des traces récentes
arrivent (comparer les timestamps).

## Opérations courantes

- **Requêter (TraceQL)** :
  ```bash
  curl -G http://localhost:3200/api/search \
    --data-urlencode 'q={ resource.service.name = "frontend" }'
  ```
- **Explorer dans Grafana** : datasource Tempo `http://tempo.tempo.svc.cluster.local:3200`, onglet « Explore ».
- **Vérifier l'ingestion** : logs du collector OpenTelemetry (voir son runbook).
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n tempo
  flux reconcile kustomization infra-controllers -n tempo
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Aucune trace récente | Collector OTel en échec | Voir le runbook [opentelemetry](opentelemetry.md) |
| Traces perdues au restart | Stockage local éphémère | Brancher S3 (`storage.trace.backend: s3`) |
| Tempo down | OOM / config | `kubectl -n tempo logs deploy/tempo`, ajuster ressources |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/tempo.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `/api/search` + une trace TraceQL.

## Sauvegarde / restauration

Traces stockées dans l'object store (si S3 configuré). Pas de backup dédié ; prévoir
rétention via `compactor.compaction.block_retention`.

## Métriques & alertes

Métriques `tempo_*` (ingestion, erreurs). Alerte : Tempo down, retards d'ingestion.
