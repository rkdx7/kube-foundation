# External Secrets Operator (ESO) — Runbook

> **Code** : `infrastructure/components/external-secrets/` · **Version** : `external-secrets` **2.12.0**
> **Namespace Flux** : `external-secrets` · **Namespace pods** : `external-secrets` · **Shard (prod)** : `shard-security`
> Voir : [README du composant](../../infrastructure/components/external-secrets/README.md)

## Rôle

ESO **synchronise les secrets** depuis un gestionnaire externe (ici OpenBao) vers des
`Secret` Kubernetes. Une panne = les `Secret` ne sont plus rafraîchis, et à terme les
applications échouent sur des secrets périmés/absents.

## Infos clés

| | |
|---|---|
| Namespace(s) | `external-secrets` |
| Source | `ClusterSecretStore` `openbao` (KV v2, chemin `apps`, auth Kubernetes rôle `eso`) |
| Exemple | `ExternalSecret` `demo-app` → `Secret` `demo-app-secret` (namespace `frontend`) |
| Dépendances | OpenBao joignable (`http://openbao-active.openbao.svc:8200`) |

## Vérifications de santé

```bash
kubectl -n external-secrets get pods
kubectl get clustersecretstore openbao
kubectl get externalsecret -A
```

Signes de bonne santé : `ClusterSecretStore` `Ready=True`, tous les `ExternalSecret`
`Ready=True` (colonne `STATUS`), pod ESO `Running`.

## Opérations courantes

- **Diagnostiquer une synchro en échec** :
  ```bash
  kubectl describe externalsecret <name> -n <ns>
  kubectl -n external-secrets logs deploy/external-secrets --tail=100
  ```
- **Forcer un refresh immédiat** : `kubectl annotate externalsecret <name> -n <ns> --overwrite force-sync=$(date +%s)`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n external-secrets
  flux reconcile kustomization infra-controllers -n external-secrets
  flux reconcile kustomization infra-configs -n external-secrets
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `ExternalSecret` `SecretSyncedError` | OpenBao injoignable ou non déscellé | Vérifier OpenBao (voir [runbook openbao](openbao.md)) |
| `Permission denied` dans ESO | Rôle/politique OpenBao insuffisante | Vérifier mount `kubernetes`, rôle `eso`, politique |
| `Secret` Kubernetes absent | `target.creationPolicy` ou erreur de mapping | `kubectl describe externalsecret`, vérifier `data[].remoteRef` |
| Secrets non rafraîchis | `refreshInterval` trop long | Ajuster `spec.refreshInterval` |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/external-secrets.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `kubectl get externalsecret -A` tout `Ready`.

## Sauvegarde / restauration

Les secrets restent la source de vérité dans OpenBao ; les `Secret` Kubernetes sont
reconstruits. Pas de backup ESO. Sauvegarder OpenBao (voir son runbook).

## Métriques & alertes

Métriques `eso_*` (`external_secret_status_condition`, compteurs de synchro/erreurs).
Alerte critique : un `ExternalSecret` non `Ready` depuis > 15 min.
