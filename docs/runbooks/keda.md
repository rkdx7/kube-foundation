# KEDA — Runbook

> **Code** : `infrastructure/components/keda/` · **Version** : `keda` **2.21.0**
> **Namespace Flux** : `keda` · **Namespace pods** : `keda` · **Shard (prod)** : `shard-platform`
> Voir : [README du composant](../../infrastructure/components/keda/README.md)

## Rôle

KEDA ajoute l'**autoscaling piloté par événements** (en plus de l'HPA CPU/mémoire) et
permet de scaler à **zéro**. Une panne = les `ScaledObject`/`ScaledJob` ne scalent plus.

## Infos clés

| | |
|---|---|
| Namespace(s) | `keda` |
| Dépendances | aucune (consomme des sources externes selon les scalers) |

## Vérifications de santé

```bash
kubectl -n keda get pods
kubectl get scaledobject,scaledjob -A
kubectl -n keda logs deploy/keda-operator --tail=50
```

Signes de bonne santé : opérateur + metrics-apiserver `Running`, les `ScaledObject`
ont un statut `Ready=True`.

## Opérations courantes

- **Inspecter un `ScaledObject`** : `kubectl describe scaledobject <name> -n <ns>`
- **Voir le HPA piloté par KEDA** : `kubectl get hpa -n <ns>`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n keda
  flux reconcile kustomization infra-controllers -n keda
  ```
- **Déclarer un trigger** : voir le README (ex. `ScaledObject` sur une file Redis).

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Workload ne scale pas | `ScaledObject` non `Ready` / source injoignable | `kubectl describe scaledobject`, logs opérateur |
| `ScaledObject` `Error` | Scaler mal configuré (metadata manquante) | Vérifier `spec.triggers[].metadata` |
| HPA en `Unknown` | metrics-apiserver KEDA down | `kubectl -n keda get pods`, redémarrer |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/keda.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `kubectl get scaledobject -A` tout `Ready`.

## Sauvegarde / restauration

Sans état (`ScaledObject` = CR versionnées dans Git). Restauration = re-déploiement.

## Métriques & alertes

Métriques `keda_*`. Alerte : opérateur down, `ScaledObject` non `Ready` prolongé,
incapacité à scaler (HPA `FailedGetExternalMetric`).
