<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/keda/icon/color/keda-icon-color.svg" alt="KEDA logo" width="160" />
</p>

# KEDA

> **Site officiel** : https://keda.sh/
> **Documentation** : https://keda.sh/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/kedacore/keda

## À quoi ça sert ?

**KEDA** (Kubernetes Event-Driven Autoscaling) ajoute l'**autoscaling piloté par
événements** en complément de l'HPA classique (CPU/mémoire). Il scale les workloads
(`Deployment`, `StatefulSet`, `Job`) en fonction de **scalers** externes : files
Kafka/RabbitMQ/Azure Service Bus, longueur de file SQS, métriques Prometheus, cron, etc.

Il permet aussi de scaler **à zéro** (0 répliques quand il n'y a plus de travail),
chose que l'HPA natif ne sait pas faire.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `keda` **2.21.0** (repo `https://kedacore.github.io/charts`) |
| Namespace | `keda` |
| `installCRDs` | `true` |

Fichier clé : `controllers/base/keda.yaml` — la `HelmRelease`.

## Configurations à considérer

- **`ScaledObject`** : déclarer les triggers (`prometheus`, `kafka`, `rabbitmq`,
  `aws-sqs-queue`, `cron`, `cpu`, `memory`…) et `minReplicas`/`maxReplicas`.
- **`idleReplicas`** : définir un plancher de répliques (y compris 0).
- **`cooldownPeriod` / `pollingInterval`** : réactivité vs. stabilité.
- **`ScaledJob`** : autoscaling de jobs (traitement par lot).
- **`fallback`** : comportement si la source d'événements est indisponible.
- **Activation/retry** : `activationThreshold`, `metricType` (`Value` vs `AverageValue`).
- **Multi-triggers** : combiner plusieurs scalers sur un même workload.

## Mini-formation

1. Définir un `ScaledObject` (ex. sur la longueur d'une file Redis) :
   ```yaml
   apiVersion: keda.sh/v1alpha1
   kind: ScaledObject
   metadata: { name: demo, namespace: default }
   spec:
     scaleTargetRef: { name: myapp }
     minReplicaCount: 0
     maxReplicaCount: 10
     triggers:
       - type: redis
         metadata:
           address: redis.default.svc.cluster.local:6379
           listName: jobs
           listLength: "5"
   ```
2. Vérifier l'état :
   ```bash
   kubectl get scaledobject demo -n default
   kubectl describe scaledobject demo -n default
   kubectl get hpa -n default   # KEDA pilote un HPA sous le capot
   ```
3. Générer de la charge et observer le scaling.

## Dashboard

Pas de dashboard intégré. KEDA expose des **métriques Prometheus** (`keda_*`) et des
dashboards Grafana communautaires existent (« KEDA »).
