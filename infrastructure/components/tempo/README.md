<p align="center">
  <img src="https://raw.githubusercontent.com/grafana/tempo/main/docs/sources/tempo/logo_and_name.png" alt="Grafana Tempo logo" width="220" />
</p>

# Tempo

> **Site officiel** : https://grafana.com/oss/tempo/
> **Documentation** : https://grafana.com/docs/tempo/latest/
> **Chart Helm** : https://artifacthub.io/packages/helm/grafana/tempo

## À quoi ça sert ?

**Tempo** est le backend de **tracing distribué** de Grafana. Il **stocke les traces**
(reçues en OTLP via l'OpenTelemetry Collector) de façon économique dans un object
store, sans indexer le contenu des spans, et se requête via **TraceQL** dans Grafana.

Il permet de suivre une requête de bout en bout à travers les services, de détecter
les latences et de corréler traces, logs et métriques.

## Configuration appliquée (dans ce dépôt)

`controllers/base/tempo.yaml` (chart `tempo` **1.24.4**) :

| Élément | Valeur |
|---|---|
| Namespace | `tempo` |
| Receiver OTLP gRPC | `0.0.0.0:4317` |
| Receiver OTLP HTTP | `0.0.0.0:4318` |

Le collector OpenTelemetry exporte vers `tempo:4317`.

## Configurations à considérer

- **Stockage** : object store S3/GCS/Azure (`storage.trace.backend: s3`) ; le défaut
  est un stockage local éphémère, inadapté à la prod.
- **Rétention** : `compactor.compaction.block_retention` (durée de conservation).
- **Memcached** : cache pour les requêtes récentes.
- **Scaling** : séparer `distributor`, `ingester`, `querier`, `compactor` en mode
  micro-services (vs mode mono-binaire).
- **Metrics generator** : générer des métriques (RED) à partir des traces.
- **Datasource Grafana** : ajouter Tempo dans Grafana pour visualiser les traces.
- **TLS** : activer TLS sur les receivers (le collector est actuellement en `insecure`).

## Mini-formation

1. Envoyer des traces (via l'OTel Collector) puis requêter l'API :
   ```bash
   kubectl port-forward -n tempo svc/tempo 3200:3200 &
   curl "http://localhost:3200/api/search"
   ```
2. Requêter en TraceQL :
   ```bash
   curl -G http://localhost:3200/api/search \
     --data-urlencode 'q={ resource.service.name = "frontend" }'
   ```
3. Dans **Grafana** : datasource Tempo (`http://tempo.tempo.svc.cluster.local:3200`),
   onglet « Explore », puis suivre une trace de bout en bout.

## Dashboard

Pas d'interface dédiée : **Grafana** est l'UI de Tempo (TraceQL, waterfall des spans).
