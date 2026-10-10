# Rook (Ceph) — Runbook

> **Code** : `infrastructure/components/rook/` · **Version** : `rook-ceph` **1.21.0** / Ceph **v20.2.4**
> **Namespace Flux** : `rook` · **Namespace pods** : `rook-ceph` · **Shard (prod)** : `shard-platform`
> Voir : [README du composant](../../infrastructure/components/rook/README.md)

## Rôle

Rook orchestre **Ceph** : **block storage** (RBD, StorageClass par défaut) + **object
storage S3** (RGW, backend de Loki/Tempo/Velero). Une panne = PVC impossibles à
provisionner et perte d'accès aux données (pas nécessairement de perte de données).

## Infos clés

| | |
|---|---|
| Namespace(s) | pods dans `rook-ceph`, sources Flux dans `rook` |
| Composants | MON ×3, MGR ×1, OSD (auto-découverte), RGW |
| Block | `CephBlockPool` `replicapool` (size 3) + StorageClass par défaut `rook-ceph-block` |
| Object | `CephObjectStore` `rgw` → `rook-ceph-rgw-rgw:80`, user `platform` |
| ⚠️ Pré-requis | **disques bruts** requis pour les OSD (absents en kind/devbox) |

## Vérifications de santé

```bash
kubectl -n rook-ceph get pods
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph get cephblockpool,cephobjectstore
kubectl -n rook-ceph exec -ti deploy/rook-ceph-tools -- ceph status   # si toolbox déployé
kubectl -n rook-ceph exec -ti deploy/rook-ceph-rgw-rgw -- radosgw-admin bucket list
```

Signes de bonne santé : `CephCluster` `Ready`, MON/MGR/OSD `Running`, `ceph status`
→ `HEALTH_OK` (ou `HEALTH_WARN` acceptable), OSD `up`.

## Opérations courantes

- **Voir la santé Ceph** : `kubectl -n rook-ceph exec -ti deploy/rook-ceph-tools -- ceph status` et `ceph osd tree`
- **Vérifier le S3** : `kubectl -n rook-ceph exec -ti deploy/rook-ceph-rgw-rgw -- radosgw-admin bucket list`
- **Lister les credentials S3** :
  `kubectl -n rook-ceph get secret rook-ceph-object-user-rgw-platform`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n rook
  flux reconcile kustomization infra-controllers -n rook
  flux reconcile kustomization infra-configs -n rook
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `CephCluster` `NotReady` (kind/devbox) | Pas de disque brut → normal en local | Attendu en devbox ; cible on-prem/cloud |
| OSD down / `HEALTH_WARN` | Disque défaillant ou nœud down | `ceph osd tree`, `ceph health detail`, remplacer le disque |
| PVC en attente (StorageClass défaut) | Pool/StorageClass manquant | `kubectl get sc`, vérifier `replicapool` |
| Loki/Tempo/Velero sans accès S3 | Credentials `platform` non propagés | Copier le secret S3 dans le namespace consommateur |
| `HEALTH_ERR` (pg dégradées) | Panne multiple OSD / réseau | `ceph health detail`, restaurer la réplication |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/rook.yaml`.
2. Suivre la [doc d'upgrade Rook](https://rook.io/docs/rook/latest-release/Upgrade/rook-upgrade/)
   (upgrade **un minor à la fois**, vérifier `HEALTH_OK` avant).
3. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
4. Valider : `ceph status` → `HEALTH_OK`, puis test PVC + S3.

## Sauvegarde / restauration

- **Données** : protégées par la réplication Ceph (size 3). Le **DR** passe par Velero
  (snapshots RBD via CSI + objets K8s).
- **Pas de backup des buckets S3 par défaut** : prévoir une réplication RGW multisite
  ou un export régulier si Loki/Tempo/Velero y stockent des données critiques.
- Ne jamais supprimer un `CephCluster` sans avoir vidé/migré les PVC.

## Métriques & alertes

Métriques `ceph_*` (santé, capacité, IOPS). Alerte critique : `HEALTH_ERR`, OSD down,
capacité > 80 %, MON non quorum.
