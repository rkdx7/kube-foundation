<p align="center">
  <img src="https://raw.githubusercontent.com/aquasecurity/trivy/main/docs/imgs/logo-horizontal.svg" alt="Trivy logo" width="220" />
</p>

# Trivy (Trivy Operator)

> **Site officiel** : https://trivy.dev/
> **Documentation** : https://aquasecurity.github.io/trivy/
> **Chart Helm** : https://artifacthub.io/packages/helm/aquasecurity/trivy-operator

## À quoi ça sert ?

**Trivy** est le **scanner de vulnérabilités et de mauvaise configuration** d'Aqua
Security. **Trivy Operator** l'intègre à Kubernetes : il scanne en continu :

- les **images de conteneurs** (vulnérabilités des paquets OS et des dépendances),
- les **manifests/workloads** (mauvaise configuration, CIS Kubernetes Benchmark, RBAC),
- les **secrets exposés** et la **conformité** (NSA, MITRE, PCI-DSS…).

Il produit des **VulnerabilityReports**, **ConfigAuditReports** et **ComplianceReports**
consultables via `kubectl`. C'est la brique de sécurité « scan statique », en complément
de Kyverno (admission) et Falco (runtime).

## Configuration appliquée (dans ce dépôt)

`controllers/base/trivy.yaml` (chart `trivy-operator` **0.37.0**) :

| Élément | Valeur |
|---|---|
| Namespace | `trivy` |
| `installCRDs` | `true` |
| `trivy.ignoreUnfixed` | `true` (ignorer les vulnérabilités sans correctif) |

## Configurations à considérer

- **`trivy.ignoreUnfixed`** : passer à `false` pour un inventaire exhaustif (plus bruyant).
- **Fréquence de scan** : `operator.scanJobTTL`, `trivy.timeout`, `operator.reportAge`.
- **Scheduled scans** : `operator.scanJobTolerations` et des `CronJob`/`scanJob` planifiés.
- **Mode client-server** : déployer un serveur Trivy central pour cacher les bases de
  vulnérabilités et accélérer les scans.
- **Compliance** : activer les rapports de conformité (CIS, NSA, MITRE).
- **Secret scanning** : détecter les secrets exposés.
- **`VulnerabilityReport` → alertes** : brancher sur Prometheus/Alertmanager ou un
  exporteur pour alerter sur les CVEs critiques.
- **SBOM** : générer des SBOM (CycloneDX/SPDX) pour la chaîne d'approvisionnement.

## Mini-formation

1. Lister les rapports :
   ```bash
   kubectl get vulnerabilityreports -A
   kubectl get configauditreports -A
   ```
2. Inspecter un rapport :
   ```bash
   kubectl get vulnerabilityreport -n frontend -o wide
   kubectl describe vulnerabilityreport <name> -n frontend
   ```
3. Scanner une image manuellement (CLI) :
   ```bash
   trivy image nginx:latest
   trivy config ./manifests
   ```

## Dashboard

Pas de dashboard intégré. Options :
- **Métriques Prometheus** de l'opérateur + dashboards Grafana communautaires (« Trivy »).
- **Security Hub** (offre commerciale Aqua) pour une UI complète des résultats.
