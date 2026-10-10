# Velero — Runbook

> **Code** : `infrastructure/components/velero/` · **Version** : `velero` **12.2.1**
> **Namespace Flux** : `velero` · **Namespace pods** : `velero` · **Shard (prod)** : `shard-platform`
> Voir : [README du composant](../../infrastructure/components/velero/README.md)

## Rôle

Velero assure la **sauvegarde / restauration / migration** du cluster (objets K8s +
snapshots de volumes). C'est la brique **DR**. Un backup non testé n'est pas un backup.

## Infos clés

| | |
|---|---|
| Namespace(s) | `velero` |
| Backup Storage | `default` → provider `aws`, bucket `velero-backups` (⚠️ adapter au backend réel : S3/GCS/Ceph RGW) |
| Schedule | `daily` → cron `0 1 * * *`, TTL `720h` (30 j) |
| Dépendances | credentials du backend de stockage, CSI pour les snapshots |

## Vérifications de santé

```bash
kubectl -n velero get pods
velero backup get
velero schedule get
velero backup-location get
```

Signes de bonne santé : pod `Running`, `BackupStorageLocation` `Available`, le
schedule `daily` a produit des backups récents (aucun `Failed`).

## Opérations courantes

- **Backup à la demande** :
  ```bash
  velero backup create demo --include-namespaces frontend
  velero backup get
  velero backup describe demo
  ```
- **Restaurer** :
  ```bash
  velero restore create --from-backup demo
  velero restore get
  ```
- **Voir les logs** : `kubectl -n velero logs deploy/velero --tail=100`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n velero
  flux reconcile kustomization infra-controllers -n velero
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Backup `PartiallyFailed`/`Failed` | Snapshot CSI en échec / bucket injoignable | `velero backup describe <name>`, logs Velero |
| `BackupStorageLocation` `Unavailable` | Credentials / bucket erronés | Vérifier la config du BSL et les credentials |
| Restauration bloquée | Ressources existantes / hook en échec | `velero restore describe <name>`, logs |
| Volumes non sauvegardés | CSI snapshot non supporté | Activer Kopia/Restic (`use-node-agent`) |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/velero.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : un `velero backup create` + un `velero restore create` de test.

## Sauvegarde / restauration

- **Plan de reprise** : backup quotidien (`daily`), TTL 30 j. Prévoir aussi un
  **test de restauration régulier** (mensuel) vers un cluster de recette.
- Restaurer un namespace : `velero restore create --from-backup <b> --include-namespaces <ns>`.

## Métriques & alertes

Métriques Velero (backups en échec, durée). Alerte critique : backup `daily` en échec
ou absent > 48 h, `BackupStorageLocation` non `Available`.
