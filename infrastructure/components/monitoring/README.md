<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/prometheus/icon/color/prometheus-icon-color.svg" alt="Prometheus (monitoring) logo" width="160" />
</p>

# Monitoring (kube-prometheus-stack + metrics-server)

> **Site officiel** :
> - Prometheus Operator : https://prometheus-operator.dev/
> - Prometheus : https://prometheus.io/ · Grafana : https://grafana.com/
> - metrics-server : https://github.com/kubernetes-sigs/metrics-server
> **Chart Helm** : https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack

## À quoi ça sert ?

Ce composant regroupe la **pile d'observabilité métriques** :

- **kube-prometheus-stack** : déploie **Prometheus** (scraping + stockage des métriques),
  **Alertmanager** (routage des alertes), **Grafana** (visualisation) et un ensemble de
  règles/dashboards préconfigurés pour Kubernetes.
- **metrics-server** : source des métriques CPU/mémoire pour `kubectl top` et l'HPA
  (autoscaling natif).

C'est le socle de monitoring du cluster (métriques), complété par Loki (logs) et
Tempo (traces) pour l'observabilité « trois piliers ».

## Configuration appliquée (dans ce dépôt)

**kube-prometheus-stack** (`controllers/base/monitoring.yaml`) :

| Élément | Valeur |
|---|---|
| Chart / version | `kube-prometheus-stack` **92.2.0** (repo `https://prometheus-community.github.io/helm-charts`) |
| Namespace | `monitoring` |
| `defaultRules.create` | `true` |
| `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues` | `false` (scrape tous les ServiceMonitors) |
| `prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues` | `false` |
| `grafana.enabled` | `true` |
| `grafana.adminPassword` | `admin` (⚠️ à changer) |

**metrics-server** :

| Élément | Valeur |
|---|---|
| Chart / version | `metrics-server` **3.14.0** (repo `https://kubernetes-sigs.github.io/metrics-server/`) |
| Namespace cible | `kube-system` |
| `args` | `--kubelet-insecure-tls` (⚠️ dev uniquement) |

## Configurations à considérer

- **Alertmanager** : configurer les receivers (Slack, PagerDuty, email) et les routes.
- **Persistance** : activer les PVC pour Prometheus/Grafana (sinon données volatiles).
- **Rétention** : `retention` et `retentionSize` de Prometheus.
- **Grafana** : changer `adminPassword`, exposer via Ingress, ajouter SSO (OIDC/LDAP),
  provisionner des dashboards/datasources (Loki, Tempo).
- **Thanos / remote-write** : pour la longue durée et la fédération multi-cluster.
- **Scrape additionnel** : `additionalScrapeConfigs` pour les endpoints custom.
- **metrics-server** : retirer `--kubelet-insecure-tls` et configurer les certificats
  kubelet en prod.

## Mini-formation

1. Accéder à Grafana :
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   # http://localhost:3000  (admin / admin)
   ```
2. Accéder à Prometheus / Alertmanager :
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
   ```
3. Vérifier les métriques HPA :
   ```bash
   kubectl top nodes
   kubectl top pods -A
   ```

## Dashboard

- **Grafana** (intégré) : le dashboard principal, avec les dashboards Kubernetes
  préconfigurés (cluster, nœuds, pods) + vos propres dashboards.
- **Prometheus UI** : requêtes ad hoc et cibles (`/targets`).
- **Alertmanager UI** : état des alertes et silences.
