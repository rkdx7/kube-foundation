<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/longhorn/icon/color/longhorn-icon-color.svg" alt="Longhorn logo" width="160" />
</p>

# Longhorn

> **Site officiel** : https://longhorn.io/
> **Documentation** : https://longhorn.io/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/longhorn/longhorn

## À quoi ça sert ?

**Longhorn** est la solution de **stockage distribué (block storage)** pour
Kubernetes on-prem. Il réplique les volumes sur plusieurs nœuds, fournit des
snapshots, des backups vers un object store (S3/NFS), et une UI de gestion complète.

Il fournit une **StorageClass** par défaut afin que les PVC puissent être provisionnés
dynamiquement sans SAN externe (contrairement aux clouds qui utilisent leurs CSI natifs).

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `longhorn` **1.9.1** (repo `https://charts.longhorn.io`) |
| Namespace cible | `longhorn-system` (`targetNamespace`, créé auto) |
| `defaultSettings.backupTarget` | `""` (pas de destination de backup) |
| `persistence.defaultClass` | `true` (StorageClass par défaut) |

Fichier clé : `controllers/base/longhorn.yaml` — la `HelmRelease`.

## Configurations à considérer

- **`backupTarget`** : configurer une destination S3/NFS pour les backups de volumes
  (indispensable en prod, à coupler avec Velero pour une stratégie complète).
- **`defaultDataLocality`** : `best-effort` pour garder les données proches du pod.
- **`numberOfReplicas`** : réplication (3 = tolérance à 2 pannes de nœud).
- **Over-provisioning** : `storageOverProvisioningPercentage`.
- **Scheduling des nœuds** : `nodeSelector`, disques dédiés, `allowVolumeExpansion`.
- **`recurringJobs`** : snapshots/backups planifiés.
- **Ressources** : les volumes consomment disque + mémoire ; surveiller l'espace nœud.

## Mini-formation

1. Créer un PVC (la StorageClass par défaut est Longhorn) :
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata: { name: demo }
   spec:
     accessModes: [ ReadWriteOnce ]
     resources: { requests: { storage: 5Gi } }
   ```
2. Vérifier :
   ```bash
   kubectl get pvc demo
   kubectl get volumes.longhorn.io -n longhorn-system
   ```
3. Accéder à l'UI Longhorn :
   ```bash
   kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
   # ouvrir http://localhost:8080
   ```
4. Créer un snapshot/backup depuis l'UI, puis tester une restauration.

## Dashboard

**Longhorn UI** (intégré, exposé via le service `longhorn-frontend`) : tableau de bord
complet des volumes, répliques, nœuds, snapshots et backups.
