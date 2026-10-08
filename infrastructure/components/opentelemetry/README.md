<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/opentelemetry/icon/color/opentelemetry-icon-color.svg" alt="OpenTelemetry logo" width="160" />
</p>

# OpenTelemetry Collector

> **Site officiel** : https://opentelemetry.io/
> **Documentation** : https://opentelemetry.io/docs/collector/
> **Chart Helm** : https://artifacthub.io/packages/helm/opentelemetry-helm-charts/opentelemetry-collector

## À quoi ça sert ?

L'**OpenTelemetry Collector** est le **routeur de télémétrie** (traces, métriques,
logs) indépendant des fournisseurs. Il **reçoit** la télémétrie des applications
(via OTLP), la **traite** (batch, filtres, enrichissement, sampling) et l'**exporte**
vers un ou plusieurs backends.

Dans ce dépôt, il reçoit les **traces** en OTLP et les exporte vers **Tempo** —
c'est le point d'entrée unique du tracing pour les applications.

## Configuration appliquée (dans ce dépôt)

`controllers/base/opentelemetry.yaml` (chart `opentelemetry-collector` **0.175.1**) :

| Élément | Valeur |
|---|---|
| Namespace | `opentelemetry` |
| `mode` | `deployment` (instance unique) |
| Image | `otel/opentelemetry-collector-k8s` |
| Receiver OTLP gRPC | `0.0.0.0:4317` |
| Receiver OTLP HTTP | `0.0.0.0:4318` |
| Exporter | `otlp/tempo` → `tempo:4317` (TLS `insecure: true`) |
| Pipeline | `traces`: receiver `otlp` → exporter `otlp/tempo` |

## Configurations à considérer

- **Pipeline métriques** : ajouter un exporter Prometheus et un receiver métriques
  (OTLP ou scrapes) pour alimenter le `monitoring`.
- **Pipeline logs** : exporter vers Loki en complément de Vector.
- **Processors** : `batch`, `memory_limiter` (recommandé), `attributes/k8sattributes`
  (enrichir avec les métadonnées pod/namespace), `tail_sampling`.
- **Receivers** : `kubeletstats`, `hostmetrics`, `prometheus` pour collecter l'infra.
- **Mode** : `daemonset` (agent par nœud) + `deployment` (gateway) selon l'échelle.
- **OpenTelemetry Operator** : auto-instrumentation des applications (Java, .NET, …)
  sans changer le code.
- **TLS** : activer TLS entre le collector et Tempo en prod (`insecure: false`).

## Mini-formation

1. Envoyer une trace de test vers le collector :
   ```bash
   kubectl run -it --rm otel-test --image=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib:latest -- \
     telemetrygen traces --otlp-insecure --otlp-endpoint opentelemetry-collector.opentelemetry.svc:4317
   ```
2. Vérifier la réception :
   ```bash
   kubectl logs -n opentelemetry deploy/opentelemetry-collector
   ```
3. Vérifier que les traces arrivent dans **Tempo** (via Grafana, datasource Tempo).

## Dashboard

Pas de dashboard propre : le collector **n'a pas d'UI** ; les données sont visualisées
dans **Grafana** (via Tempo). Le collector expose des métriques Prometheus pour sa santé.
