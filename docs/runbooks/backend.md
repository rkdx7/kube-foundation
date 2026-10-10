# Backend — Runbook

> **Code** : `apps/components/backend/` · **Version** : redis + memcached (charts Bitnami)
> **Namespace Flux** : `backend` · **Namespace pods** : `backend` · **Shard (prod)** : `shard-platform`

## Rôle

Backend de **démonstration** : **redis** (cache/session) + **memcached** (cache),
déployés via `HelmRelease` (charts Bitnami en `OCIRepository`). Consommé par le frontend.

## Infos clés

| | |
|---|---|
| Namespace(s) | `backend` |
| Dépendances | aucune (les sources charts pointent vers `registry-1.docker.io/bitnamicharts`) |
| ⚠️ | `auth.enabled: false` (redis), persistance **désactivée** (dev) |

## Vérifications de santé

```bash
kubectl -n backend get pods,svc
kubectl -n backend get helmrelease
kubectl -n backend logs deploy/redis-master --tail=50   # ou sts selon le chart
```

Signes de bonne santé : redis + memcached `Running`, `HelmRelease` `Ready=True`.

## Opérations courantes

- **Tester redis** : `kubectl -n backend exec -ti deploy/redis-master -- redis-cli ping` (→ `PONG`)
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci apps -n backend
  flux reconcile kustomization apps -n backend
  ```
- **Voir l'état des releases** : `flux get helmrelease -n backend`

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `HelmRelease` pas `Ready` | Chart source (`semver: "*"`) résolu vers une version cassée | `kubectl describe helmrelease redis -n backend`, pincer le `semver` |
| Données perdues au restart | Persistance désactivée (dev) | Activer `master.persistence` en prod |
| Redis non sécurisé | `auth.enabled: false` | Activer l'auth + secret en prod |

## Mise à jour (upgrade)

1. Les charts sont tirés en `semver: "*"` (mise à jour automatique au reconcile). Pour
   **pinner**, fixer `ref.semver` dans `apps/components/backend/base/backend.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) si tu pinces une version.

## Sauvegarde / restauration

Persistance désactivée en dev (pas de données à sauver). En prod : activer les PVC +
backup via Velero (voir son runbook).

## Métriques & alertes

Métriques redis/memcached via exporters (si activés). Alerte : pod redis/master down,
latence de cache anormale.
