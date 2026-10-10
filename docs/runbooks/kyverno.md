# Kyverno — Runbook

> **Code** : `infrastructure/components/kyverno/` · **Version** : `kyverno` **3.9.1**
> **Namespace Flux** : `kyverno` · **Namespace pods** : `kyverno` · **Shard (prod)** : `shard-security`
> Voir : [README du composant](../../infrastructure/components/kyverno/README.md)

## Rôle

Kyverno applique les **politiques d'admission** (validate/mutate/generate) en YAML
natif. Une panne peut soit bloquer les déploiements (webhook en échec), soit laisser
passer des ressources non conformes.

## Infos clés

| | |
|---|---|
| Namespace(s) | `kyverno` |
| Dépendances | webhook d'admission (validating/mutating) |
| `admissionController.replicas` | `1` |

## Vérifications de santé

```bash
kubectl -n kyverno get pods
kubectl get clusterpolicy
kubectl get policyreports -A
```

Signes de bonne santé : pods `Running`, les webhooks de validation/mutation
`kyverno` répondent (`kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration | grep kyverno`).

## Opérations courantes

- **Voir pourquoi un déploiement est bloqué** :
  ```bash
  kubectl get events -n <ns> --sort-by=.lastTimestamp | grep -i kyverno
  kubectl describe clusterpolicy <name>
  ```
- **Basculer une politique en audit** (débloquer sans supprimer) :
  `kubectl patch clusterpolicy <name> -p '{"spec":{"validationFailureAction":"Audit"}}' --type=merge`
- **Voir les rapports d'audit** : `kubectl get policyreports -A`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n kyverno
  flux reconcile kustomization infra-controllers -n kyverno
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Tout `kubectl apply` en timeout | Webhook Kyverno injoignable | `kubectl -n kyverno get pods`, vérifier le service/webhook |
| Déploiement bloqué par une politique | Règle `Enforce` trop stricte | Identifier la politique, `Audit` ou `policyException` |
| `PolicyReport` `fail` massif | Nouvelle politique trop large | Revoir le `match` de la politique |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/kyverno.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : déployer un pod conforme et un pod non conforme (doit être bloqué).

## Sauvegarde / restauration

Politiques = ressources versionnées dans Git (pas de backup). Les `PolicyReport` sont
recalculés.

## Métriques & alertes

Métriques `kyverno_*` (admission, policy execution). Alerte : webhook down (déploiements
bloqués), taux d'échec d'admission anormal.
