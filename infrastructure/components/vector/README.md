<p align="center">
  <img src="https://raw.githubusercontent.com/vectordotdev/vector/master/website/static/img/logos/vector-logo-dark.svg" alt="Vector logo" width="200" />
</p>

# Vector

> **Runbook** : [docs/runbooks/vector.md](../../../docs/runbooks/vector.md)

> **Site officiel** : https://vector.dev/
> **Documentation** : https://vector.dev/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/vector/vector

## À quoi ça sert ?

**Vector** est un pipeline d'**observabilité** léger et performant (Rust) qui
**collecte, transforme et route** logs, métriques et traces. Il remplace des agents
comme Fluent Bit/Fluentd ou Logstash.

Dans ce dépôt, il tourne en mode **Agent** (DaemonSet) pour collecter les **logs des
conteneurs** (`kubernetes_logs`) et les envoyer vers **Loki** — c'est l'agent de
collecte de logs de la plateforme.

## Configuration appliquée (dans ce dépôt)

`controllers/base/vector.yaml` (chart `vector` **0.59.0**) :

| Élément | Valeur |
|---|---|
| Namespace | `vector` |
| `role` | `Agent` (DaemonSet par nœud) |
| `service.enabled` | `false` |
| Source | `kubernetes_logs` (logs des pods) |
| Sink | `loki` → `http://loki.loki.svc.cluster.local:3100` |
| `tenant_id` | `fake` (multi-tenancy Loki) |
| Encoding | `json` |
| Label | `source: vector` |

## Configurations à considérer

- **Rôle `Aggregator`** : centraliser avant l'envoi (buffer, déduplication) pour les gros volumes.
- **Transforms** : `remap` (VRL) pour parser/enrichir/filtrer les logs.
- **Sinks multiples** : envoyer vers S3 (archive), Elasticsearch, un second Loki, etc.
- **Buffers** : disque/mémoire pour survivre aux coupures du backend.
- **Sources métriques** : `prometheus_scrape`, `host_metrics` pour alimenter le monitoring.
- **`tenant_id`** : aligner sur la vraie multi-tenancy Loki si `auth_enabled: true`.
- **Ressources** : surveiller la mémoire du DaemonSet selon le débit de logs.

## Mini-formation

1. Vérifier que Vector tourne :
   ```bash
   kubectl get pods -n vector
   kubectl logs -n vector -l app.kubernetes.io/name=vector --tail=20
   ```
2. Tester une config VRL (bac à sable) : https://playground.vrl.dev
3. Vérifier que les logs arrivent dans Loki :
   ```bash
   kubectl port-forward -n loki svc/loki 3100:3100 &
   curl "http://localhost:3100/loki/api/v1/labels"
   ```
   puis explorer dans **Grafana** (datasource Loki, filtre `source=vector`).

## Dashboard

Pas de dashboard intégré. Vector propose un TUI local (`vector top`) et un pipeline
dans les données visualisées via **Grafana/Loki**.
