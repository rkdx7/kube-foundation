# Multi-cloud

The repository is environment-first (`staging`, `prod` folders). Cloud-specific
behaviour is configured per environment. The `PROVIDER` value in
`flux-runtime-info` records the target provider (`aws`, `gcp`, `azure`, `onprem`).

## What changes per provider

| Concern | AWS | GCP | Azure | On-prem |
|---|---|---|---|---|
| Storage CSI | `aws-ebs-csi-driver` | `gcp-compute-persistent-disk-csi-driver` | `azuredisk-csi-driver` | Rook (Ceph RBD) |
| ExternalDNS | `provider: aws` | `provider: google` | `provider: azure` | `rfc2136` / none |
| External Secrets | AWS Secrets Manager | GCP Secret Manager | Azure Key Vault | Vault / none |
| Velero | S3 | GCS | Azure Blob | Ceph RGW (Rook) |
| Loki / Tempo (object store) | S3 | GCS | Azure Blob | Ceph RGW (Rook) |
| LoadBalancer | AWS LB | GCP LB | Azure LB | kube-vip |

## Adding a cloud CSI driver

Add it as a new infrastructure component following the same pattern as `rook`.
For example, AWS EBS CSI:

```yaml
# infrastructure/components/aws-ebs-csi/controllers/base/aws-ebs-csi.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: aws-ebs-csi
  namespace: aws-ebs-csi
spec:
  interval: 24h
  url: https://kubernetes-sigs.github.io/aws-ebs-csi-driver
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: aws-ebs-csi
  namespace: aws-ebs-csi
spec:
  interval: 30m
  releaseName: aws-ebs-csi-driver
  targetNamespace: kube-system
  chart:
    spec:
      chart: aws-ebs-csi-driver
      sourceRef:
        kind: HelmRepository
        name: aws-ebs-csi
```

Then register it in `fleet/tenants/infra.yaml` inputs and let CI push it.

Equivalent chart sources:

| Provider | Chart | Repository |
|---|---|---|
| AWS | `aws-ebs-csi-driver` | https://kubernetes-sigs.github.io/aws-ebs-csi-driver |
| GCP | `gcp-compute-persistent-disk-csi-driver` | https://kubernetes-sigs.github.io/gcp-compute-persistent-disk-csi-driver |
| Azure | `azuredisk-csi-driver` | https://kubernetes-sigs.github.io/azuredisk-csi-driver |

## Workload identity

Prefer provider workload identity over static credentials:

- **AWS**: IRSA (EKS pod identity)
- **GCP**: Workload Identity Federation
- **Azure**: Workload Identity (AAD Pod Identity successor)

The Flux `FluxInstance.cluster.objectLevelWorkloadIdentity` flag enables object-level
service-account selection for the Flux controllers in these environments.

## Object storage (logs & traces)

On-prem, the S3-compatible object store is **Ceph RGW** (deployed by **Rook**,
`infrastructure/components/rook`). Loki, Tempo and Velero point at its S3 gateway
(`rook-ceph-rgw-rgw.rook-ceph.svc:80`) instead of a cloud bucket:

| Consumer | Bucket |
|---|---|
| Loki (logs) | `loki-data` |
| Tempo (traces) | `tempo-data` |
| Velero (backups) | `velero` |

On cloud providers you can instead point each consumer at the native object store
(S3 / GCS / Azure Blob) by overriding its Helm `values` per environment — e.g. Loki
`loki.storage.type: s3|gcs|azure` and the corresponding endpoint/bucket. Credentials
come from workload identity where available, or SOPS/External Secrets.

