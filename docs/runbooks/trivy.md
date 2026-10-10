# Trivy (Trivy Operator) — Runbook

> **Code** : `infrastructure/components/trivy/` · **Version** : `trivy-operator` **0.37.0**
> **Namespace Flux** : `trivy` · **Namespace pods** : `trivy` · **Shard (prod)** : `shard-security`
> Voir : [README du composant](../../infrastructure/components/trivy/README.md)

## Rôle

Trivy Operator **scanne en continu** les images et workloads (vulnérabilités,
mauvaise configuration, secrets exposés) et produit des `VulnerabilityReport` /
`ConfigAuditReport` / `ComplianceReport`. Non bloquant : il **rapporte**.

## Infos clés

| | |
|---|---|
| Namespace(s) | `trivy` |
| `trivy.ignoreUnfixed` | `true` (vulnérabilités sans correctif ignorées) |
| Dépendances | accès aux registries d'images |

## Vérifications de santé

```bash
kubectl -n trivy get pods
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
```

Signes de bonne santé : pods `Running`, les `VulnerabilityReport` sont générés (âge
récent), aucun `scan` en erreur dans les logs de l'opérateur.

## Opérations courantes

- **Inspecter un rapport** : `kubectl describe vulnerabilityreport <name> -n <ns>`
- **Lister les CVE critiques** :
  `kubectl get vulnerabilityreports -A -o json | jq ...` (ou via l'UI Trivy/Grafana)
- **Scanner une image à la main (CLI)** : `trivy image <img>`, `trivy config ./manifests`
- **Relancer un scan** : supprimer le rapport `kubectl delete vulnerabilityreport <name> -n <ns>` (re-scanné)
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n trivy
  flux reconcile kustomization infra-controllers -n trivy
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Rapports absents ou périmés | Scan job en échec / DB vuln non téléchargée | Logs opérateur, vérifier accès registry |
| Scan très lent | Téléchargement DB à chaque job | Mode client-server Trivy (cache central) |
| Trop de bruit CVE | `ignoreUnfixed: false` | Passer à `true` ou filtrer par sévérité |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/trivy.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `kubectl get vulnerabilityreports -A` se régénèrent.

## Sauvegarde / restauration

Sans état (rapports = CR re-calculés). Restauration = re-déploiement.

## Métriques & alertes

Métriques de l'opérateur + dashboards Grafana « Trivy ». Alerte : CVE critique
(`CVSS >= 9`) sur une image en production, scan en échec récurrent.
