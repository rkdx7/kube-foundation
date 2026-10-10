# OpenTelemetry Collector — Runbook

> **Code** : `infrastructure/components/opentelemetry/` · **Version** : `opentelemetry-collector` **0.175.1**
> **Namespace Flux** : `opentelemetry` · **Namespace pods** : `opentelemetry` · **Shard (prod)** : `shard-observability`
> Voir : [README du composant](../../infrastructure/components/opentelemetry/README.md)

## Rôle

Le **collector** OpenTelemetry est le routeur de télémétrie. Ici il reçoit les
**traces** OTLP et les exporte vers **Tempo**. Une panne = traces perdues (le tracing
applicatif se dégrade silencieusement).

## Infos clés

| | |
|---|---|
| Namespace(s) | `opentelemetry` |
| Mode | `deployment` (instance unique) |
| Receivers | OTLP gRPC `4317`, HTTP `4318` |
| Exporter | `otlp/tempo` → `tempo:4317` (`insecure: true`) |
| Dépendances | Tempo (aval) |

## Vérifications de santé

```bash
kubectl -n opentelemetry get pods
kubectl -n opentelemetry logs deploy/opentelemetry-collector --tail=50
```

Signes de bonne santé : pod `Running`, logs sans erreurs d'export vers Tempo
(`Failed to export ...` = problème).

## Opérations courantes

- **Envoyer une trace de test** :
  ```bash
  kubectl run -it --rm otel-test \
    --image=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:latest -- \
    telemetrygen traces --otlp-insecure --otlp-endpoint opentelemetry-collector.opentelemetry.svc:4317
  ```
- **Vérifier la réception** : `kubectl -n opentelemetry logs deploy/opentelemetry-collector`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n opentelemetry
  flux reconcile kustomization infra-controllers -n opentelemetry
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `Failed to export` vers Tempo | Tempo down / TLS mismatch | Vérifier Tempo, aligner `insecure` |
| Aucune trace reçue | App non configurée pour OTLP | Vérifier l'endpoint côté app (4317/4318) |
| Collector OOM | Pas de `memory_limiter` | Ajouter le processor `memory_limiter` + `batch` |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/opentelemetry.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `telemetrygen` puis traces visibles dans Tempo/Grafana.

## Sauvegarde / restauration

Sans état. Restauration = re-déploiement.

## Métriques & alertes

Métriques du collector (`otelcol_*` : `otelcol_exporter_sent_spans`,
`otelcol_exporter_send_failed_spans`). Alerte : échecs d'export élevés, collector down.
