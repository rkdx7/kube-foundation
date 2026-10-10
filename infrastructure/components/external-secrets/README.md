<p align="center">
  <img src="https://raw.githubusercontent.com/external-secrets/external-secrets/main/assets/eso-logo-large.png" alt="External Secrets Operator logo" width="280" />
</p>

# External Secrets Operator (ESO)

> **Runbook** : [docs/runbooks/external-secrets.md](../../../docs/runbooks/external-secrets.md)

> **Site officiel** : https://external-secrets.io/
> **Documentation** : https://external-secrets.io/latest/
> **Chart Helm** : https://artifacthub.io/packages/helm/external-secrets/external-secrets

## À quoi ça sert ?

L'**External Secrets Operator** synchronise les secrets depuis des gestionnaires de
secrets externes (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, **OpenBao/Vault**,
Hashicorp Vault, 1Password, …) vers des `Secret` Kubernetes.

Il déclare la **source** via un `SecretStore`/`ClusterSecretStore`, puis un
`ExternalSecret` décrit *quoi* synchroniser. Les secrets restent la source de vérité à
l'extérieur du cluster (pas de stockage durable dans Git/etcd).

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `external-secrets` **2.12.0** (repo `https://charts.external-secrets.io`) |
| Namespace | `external-secrets` |
| `installCRDs` | `true` |
| `serviceAccount.create` | `true` |

**`ClusterSecretStore` `openbao`** (`configs/base/openbao-store.yaml`) :

| Champ | Valeur |
|---|---|
| Provider | `openbao` |
| Serveur | `http://openbao-active.openbao.svc:8200` (service actif OpenBao HA, HTTP) |
| Chemin KV | `apps` (KV **v2**) |
| Auth | `kubernetes` (mount `kubernetes`, rôle `eso`) |

**`ExternalSecret` `demo-app`** (namespace `frontend`) :

| Champ | Valeur |
|---|---|
| Cible | Secret `demo-app-secret` |
| Donnée | clé `password` ← `demo/app` → `password` dans OpenBao |
| Refresh | `1h` |

Fichiers clés : `controllers/base/external-secrets.yaml` + `configs/base/openbao-store.yaml`.

## Configurations à considérer

- **Autres providers** : AWS Secrets Manager, GCP Secret Manager, Azure Key Vault,
  Vault, etc. — avec **IRSA / Workload Identity** pour l'authentification.
- **`refreshInterval`** : ajuster la fréquence de re-synchronisation (défaut 1m).
- **`secretStore` (webhook)** : valider les `ExternalSecret` à l'admission.
- **`certController`** : générer des certificats pour le webhook.
- **`dataFrom`** : synchroniser *toutes* les clés d'un chemin au lieu de lister `data`.
- **`target.creationPolicy`** : `Owner` (défaut) vs `Merge`.
- **Templates** (`spec.target.template`) : transformer les clés/valeurs.

## Mini-formation

1. Créer un `SecretStore` (ou utiliser le `ClusterSecretStore openbao` déjà présent) :
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: SecretStore
   metadata: { name: demo, namespace: default }
   spec:
     provider:
       openbao:
         server: http://openbao-active.openbao.svc:8200
         path: apps
         version: v2
         auth:
           kubernetes: { mountPath: kubernetes, role: eso }
   ```
2. Créer un `ExternalSecret` :
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata: { name: demo, namespace: default }
   spec:
     refreshInterval: 1h
     secretStoreRef: { name: demo, kind: SecretStore }
     target: { name: demo-secret }
     data: [ { secretKey: password, remoteRef: { key: demo/app, property: password } } ]
   ```
3. Vérifier la synchronisation :
   ```bash
   kubectl get externalsecret -n default
   kubectl describe externalsecret demo -n default
   kubectl get secret demo-secret -n default -o yaml
   ```

## Dashboard

Pas de dashboard intégré. ESO expose des **métriques Prometheus** (`eso_*`,
statut de synchro, erreurs) monitorables dans Grafana.
