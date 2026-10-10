# Stakater Reloader — Runbook

> **Code** : `infrastructure/components/stakater/` · **Version** : `reloader` **2.2.18** (app v1.4.22)
> **Namespace Flux** : `stakater` · **Namespace pods** : `stakater` · **Shard (prod)** : `shard-platform`
> Voir : [README du composant](../../infrastructure/components/stakater/README.md)

## Rôle

Reloader surveille les **ConfigMaps** et **Secrets** et déclenche un **rolling upgrade**
des `Deployment`/`StatefulSet`/`DaemonSet` qui les référencent. Une panne = les
workloads continuent de tourner avec d'**anciennes valeurs** après un changement de
config/secret, sans que personne ne le remarque immédiatement.

## Infos clés

| | |
|---|---|
| Namespace(s) | `stakater` |
| Dépendances | aucune (lecture de l'API Kubernetes, rôle `reloader-reloader` du chart) |
| Portée | globale (`reloader.watchGlobally: true`) |

## Vérifications de santé

```bash
kubectl -n stakater get pods
kubectl -n stakater logs deploy/reloader-reloader --tail=50
flux get helmrelease -n stakater
```

Signes de bonne santé : un pod `reloader-reloader-*` `Running`/`Ready`, logs sans
boucle d'erreurs (`level=error`), `HelmRelease` `Ready=True`.

## Opérations courantes

- **Voir ce que Reloader surveille** : le contrôleur liste les ConfigMaps/Secrets
  au démarrage ; `kubectl -n stakater logs deploy/reloader-reloader | grep -i watch`.
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n stakater
  flux reconcile kustomization infra-controllers -n stakater
  ```
- **Relier un workload à une ConfigMap/Secret** : ajouter l'annotation
  `reloader.stakater.com/auto: "true"` (voir le README du composant).

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Un workload ne redémarre pas après un changement de ConfigMap | ConfigMap montée via `subPath` (non détectée) ou annotation absente | Annoter explicitement (`reloader.stakater.com/auto`) ou `reloader.stakater.com/search` |
| Rolling upgrade en boucle | Secret/ConfigMap régénéré en continu (ex. token expirant) | `kubectl -n stakater logs`, isoler la source qui réécrit l'objet |
| Pod Reloader `CrashLoopBackOff` | RBAC du chart incomplet / conflit de version | `kubectl -n stakater describe pod`, `kubectl -n stakater logs` |
| Aucun pod Reloader | `HelmRelease` non `Ready` (repo indisponible) | `flux get helmrelease -n stakater`, `kubectl -n stakater get helmrelease` |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/stakater.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `kubectl -n stakater get pods` et un rolling upgrade de test.

## Sauvegarde / restauration

Sans état (les annotations de config vivent dans Git). Restauration = re-déploiement
via Flux.

## Métriques & alertes

Métriques `reloader_*` (compteurs de rechargements par type). Alerte : pod Reloader
down, `HelmRelease` non `Ready`, et absence prolongée d'événements de rechargement
après un changement de config attendu.
