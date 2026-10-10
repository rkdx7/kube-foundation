# Monitoring (kube-prometheus-stack + metrics-server) — Runbook

> **Code** : `infrastructure/components/monitoring/` · **Version** : `kube-prometheus-stack` **92.2.0** / `metrics-server` **3.14.0**
> **Namespace Flux** : `monitoring` · **Namespace pods** : `monitoring` (+ `kube-system`) · **Shard (prod)** : `shard-observability`
> Voir : [README du composant](../../infrastructure/components/monitoring/README.md)

## Rôle

La pile **métriques** : Prometheus (scraping/stockage), Alertmanager (routage
d'alertes), Grafana (visualisation), + **metrics-server** (source `kubectl top` et HPA).

## Infos clés

| | |
|---|---|
| Namespace(s) | `monitoring` (metrics-server dans `kube-system`) |
| Dépendances | aucune (source de données pour les alertes) |
| ⚠️ | `grafana.adminPassword: admin` (à changer) · `--kubelet-insecure-tls` (dev) |

## Vérifications de santé

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get prometheus,alertmanager
kubectl -n kube-system get pods -l k8s-app=metrics-server
kubectl top nodes            # valide metrics-server
```

Signes de bonne santé : Prometheus/Grafana/Alertmanager `Running`, `kubectl top nodes`
répond, les cibles Prometheus (`/targets`) sont majoritairement `up`.

## Opérations courantes

- **Accéder à Grafana** : `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` → `http://localhost:3000` (admin/admin)
- **Accéder à Prometheus** : `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090`
- **Accéder à Alertmanager** : `kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093`
- **Voir les alertes** : `kubectl -n monitoring get prometheusrules -A` + UI Alertmanager
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n monitoring
  flux reconcile kustomization infra-controllers -n monitoring
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Pas de données Grafana | Prometheus down / pas de cibles | Vérifier pods Prometheus, `/targets` |
| Alertes non envoyées | Alertmanager non configuré (receivers) | Configurer Slack/PagerDuty/email |
| Données perdues au redémarrage | Pas de PVC Prometheus | Activer la persistance (voir README) |
| `kubectl top` en erreur | metrics-server down | `kubectl -n kube-system get pods -l k8s-app=metrics-server` |
| Grafana en défaut de sécurité | `adminPassword: admin` | Changer le mot de passe + SSO OIDC |

## Mise à jour (upgrade)

1. Bumper les `version:` des deux releases dans `controllers/base/monitoring.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : Prometheus/Grafana/Alertmanager `Running`, cibles `up`.

## Sauvegarde / restauration

- **Grafana** : sauvegarder les dashboards/datasources (provisionning en code = Git).
- **Prometheus** : activer un PVC (sinon données volatiles) ; pour le long terme,
  remote-write / Thanos.

## Métriques & alertes

C'est **la** source des alertes plateforme. Alerte critique : Prometheus down,
Alertmanager down, `kubectl top` indisponible (HPA aveugle).
