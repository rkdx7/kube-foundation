<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/rook/icon/color/rook-icon-color.svg" alt="Rook logo" width="160" />
</p>

# Rook (Ceph)

> **Site officiel** : https://rook.io/
> **Documentation** : https://rook.io/docs/rook/latest-release/
> **Chart Helm** : https://artifacthub.io/packages/helm/rook-release/rook-ceph

## À quoi ça sert ?

**Rook** orchestre **Ceph** dans Kubernetes (projet **CNCF Graduated**). Il fournit
à la fois :

- **Block storage** (Ceph RBD) via une `StorageClass` par défaut — remplace Longhorn ;
- **Object storage S3** (Ceph RGW) — remplace SeaweedFS comme backend S3 auto-hébergé
  de Loki, Tempo et Velero.

Contrairement à Longhorn (un seul opérateur léger), Rook déploie un cluster Ceph
complet (MON, MGR, OSD, RGW, CSI) : plus lourd, mais c'est le standard CNCF du
stockage distribué en self-hosted.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `rook-ceph` **1.21.0** (repo `https://charts.rook.io/release`) |
| Namespace cible | `rook-ceph` (`targetNamespace`, créé auto) |
| Ceph | `quay.io/ceph/ceph:v20.2.4` (Tentacle), MON ×3, MGR ×1 |
| OSDs | `useAllNodes` + `useAllDevices` (auto-découverte des disques) |
| Block | `CephBlockPool` `replicapool` (size 3) + StorageClass **par défaut** `rook-ceph-block` |
| Object (S3) | `CephObjectStore` `rgw` → service `rook-ceph-rgw-rgw:80` |
| Utilisateur S3 | `CephObjectStoreUser` `platform` (creds auto-générées) |
| Buckets | `loki-data`, `tempo-data`, `velero` (Job de création) |

Fichiers clés :
- `controllers/base/rook.yaml` — l'opérateur Rook (`HelmRelease`).
- `configs/base/ceph-cluster.yaml` — le cluster Ceph.
- `configs/base/block-pool.yaml` — pool RBD + StorageClass par défaut.
- `configs/base/object-store.yaml` + `object-store-user.yaml` — le gateway S3 (RGW).
- `configs/base/buckets-job.yaml` — création des buckets.

> ⚠️ **Disques requis** : les OSD Ceph exigent des **blocs bruts** sur les nœuds
> (disques NVMe/SSD non formatés). En devbox/kind il n'y en a pas → le `CephCluster`
> reste `NotReady` localement. Cette config cible un vrai on-prem/cloud. Pour
> restreindre/forcer les disques, remplacez `useAllNodes/useAllDevices` par un
> `storage.nodes` explicite.

## Credentials S3 (consommateurs)

Rook génère les credentials de l'utilisateur `platform` dans le Secret
`rook-ceph-object-user-rgw-platform` (clés `AccessKey` / `SecretKey`). Pour qu'un
consommateur (Loki) les utilise, copiez-les dans son namespace :

```bash
kubectl -n loki create secret generic loki-s3-creds \
  --from-literal=accessKeyId=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rgw-platform -o jsonpath='{.data.AccessKey}' | base64 -d) \
  --from-literal=secretAccessKey=$(kubectl -n rook-ceph get secret rook-ceph-object-user-rgw-platform -o jsonpath='{.data.SecretKey}' | base64 -d)
```

La `HelmRelease` Loki injecte ensuite ces valeurs via `spec.valuesFrom` (aucun
secret en clair dans Git). Pour automatiser, branchez un `ExternalSecret` (ESO,
provider `kubernetes`) à la place de la copie manuelle — voir `docs/secrets.md`.

## Configurations à considérer

- **`storage.nodes`** : sélection explicite des disques/nœuds (au lieu de
  l'auto-découverte), `deviceFilter`, `osdsPerDevice`.
- **Chiffrement** : `network.connections.encryption` (Ceph msgr) + OSD encryption.
- **RGW HA/TLS** : `gateway.instances` > 1 et `securePort` + `sslCertificateRef`.
- **Multisite RGW** : réplication entre zones (disaster recovery).
- **`failureDomain`** : `host` (défaut) vs `osd`/`zone` pour la tolérance de panne.
- **Dashboard Ceph** : `dashboard.enabled: true` (exposer via HTTPRoute + SSO).
- **Ressources** : Ceph consomme RAM/CPU/disque ; dimensionner MON/MGR/OSD.

## Mini-formation

1. Vérifier l'état du cluster :
   ```bash
   kubectl -n rook-ceph get cephcluster
   kubectl -n rook-ceph get pods
   ```
2. Vérifier la StorageClass par défaut et le gateway S3 :
   ```bash
   kubectl get sc
   kubectl -n rook-ceph get svc rook-ceph-rgw-rgw
   kubectl -n rook-ceph get secret rook-ceph-object-user-rgw-platform
   ```
3. Tester le bloc (PVC via `rook-ceph-block`) et le S3 (lister les buckets) :
   ```bash
   kubectl create -f - <<'EOF'
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata: { name: demo }
   spec:
     accessModes: [ ReadWriteOnce ]
     resources: { requests: { storage: 5Gi } }
   EOF
   kubectl -n rook-ceph exec -ti deploy/rook-ceph-rgw-rgw -- radosgw-admin bucket list
   ```

## Dashboard

- **Ceph Dashboard** (intégré) : gestion du cluster (pools, OSDs, RGW) — port-forward
  vers `rook-ceph-mgr-dashboard` puis connexion avec les credentials générés.
- **Grafana** : les métriques Ceph/Rook (`ceph_*`, `rook_*`) via le `ServiceMonitor`
  fourni par Rook (si `monitoring` activé).
