<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/velero/icon/color/velero-icon-color.svg" alt="Velero logo" width="160" />
</p>

# Velero

> **Site officiel** : https://velero.io/
> **Documentation** : https://velero.io/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/vmware-tanzu/velero

## À quoi ça sert ?

**Velero** est la solution de **sauvegarde, restauration et migration** de clusters
Kubernetes. Il sauvegarde :

- les **objets Kubernetes** (manifests, ConfigMaps, secrets, CRDs…) dans un object store,
- les **volumes persistants** via des snapshots (CSI ou provider cloud) ou via
  Restic/Kopia (copie fichier).

Il permet de restaurer un cluster, de faire du **disaster recovery** et de **migrer**
des workloads entre clusters. C'est la brique de sauvegarde/DR de la plateforme.

## Configuration appliquée (dans ce dépôt)

`controllers/base/velero.yaml` (chart `velero` **12.2.1**) :

| Élément | Valeur |
|---|---|
| Namespace | `velero` |
| `installCRDs` / `upgradeCRDs` | `true` / `false` |
| `backupStorageLocation` | `default` → provider `aws`, bucket `velero-backups`, région `us-east-1` |
| `volumeSnapshotLocation` | `default` → provider `aws`, région `us-east-1` |
| Schedule | `daily` → cron `0 1 * * *`, TTL `720h` (30 jours) |

Fichier clé : `controllers/base/velero.yaml` — la `HelmRelease`.

## Configurations à considérer

- **Backend de stockage** : adapter à S3, GCS, Azure Blob, ou **MinIO** (on-prem).
  Utiliser **IRSA / Workload Identity** pour les credentials.
- **Snapshot des volumes** : utiliser le CSI de votre provider ou Longhorn ; sinon
  activer **Kopia/Restic** pour la copie fichier (`use-node-agent`).
- **Schedules** : plusieurs planifications (quotidien + hebdo + mensuel) et rétention.
- **Filtres** : `includedNamespaces`, `excludedResources`, labels pour cibler les backups.
- **Hooks** : `pre/post` (ex. flusher une base avant snapshot).
- **Restore** : tester régulièrement les restaurations (un backup non testé n'est pas fiable).
- **Velero + Longhorn** : Velero gère les objets, Longhorn les backups de volumes.

## Mini-formation

1. Créer un backup à la demande :
   ```bash
   velero backup create demo --include-namespaces frontend
   velero backup get
   velero backup describe demo
   ```
2. Simuler un incident (supprimer un namespace) puis restaurer :
   ```bash
   kubectl delete namespace frontend
   velero restore create --from-backup demo
   velero restore get
   ```
3. Vérifier la planification :
   ```bash
   velero schedule get
   velero schedule describe daily
   ```

## Dashboard

Pas de dashboard intégré. L'opération se fait via la **CLI `velero`** ; des dashboards
Grafana communautaires (« Velero ») existent pour surveiller les métriques des backups.
