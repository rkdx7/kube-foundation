<p align="center">
  <img src="https://raw.githubusercontent.com/openbao/openbao/main/website/public/img/logo-black.svg" alt="OpenBao logo" width="220" />
</p>

# OpenBao

> **Site officiel** : https://openbao.org/
> **Documentation** : https://openbao.org/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/openbao/openbao

## À quoi ça sert ?

**OpenBao** est le fork communautaire (Linux Foundation) de **HashiCorp Vault** : un
gestionnaire de **secrets, de chiffrement et d'identité** centralisé.

Il gère :
- des **secrets statiques** (clés, mots de passe) et **dynamiques** (crédentiels à durée de vie),
- le **chiffrement** en tant que service (transit),
- une **PKI** interne (certificats),
- l'**authentification** (méthode `kubernetes`, OIDC, …) et les **politiques** d'accès.

Dans ce dépôt, il sert de **source de vérité des secrets** pour l'External Secrets
Operator (`ClusterSecretStore openbao`, KV v2 sur le chemin `apps`).

## Configuration appliquée (dans ce dépôt)

`controllers/base/openbao.yaml` (chart `openbao` **0.30.3**) :

| Élément | Valeur |
|---|---|
| Namespace | `openbao` |
| `server.standalone` | `false` |
| `server.ha.enabled` | `true`, `replicas: 3` (mode HA) |
| `server.ha.raft` | `true`, `setNodeId: true` (stockage Raft intégré) |
| `server.dataStorage` | `enabled: true`, `size: 10Gi` |
| `ui.enabled` | `true` |
| `injector.enabled` | `true` (sidecar injector Vault/OpenBao) |

`configs/base/httproute.yaml` : `HTTPRoute` vers `openbao-active` (service actif),
hôte injecté via le tenant (`${HOST}`), TLS terminé à la Gateway kgateway.

Fichiers clés : `controllers/base/openbao.yaml` + `configs/base/httproute.yaml`.

## Configurations à considérer

- **Unseal** : par défaut OpenBao doit être **dés scellé** (Shamir) au premier démarrage ;
  envisager l'**auto-unseal** (Transit, KMS cloud) pour éviter l'étape manuelle.
- **Stockage** : Raft (intégré, utilisé ici) vs Consul/externe ; prévoir des snapshots Raft.
- **TLS** : en interne le cluster est en HTTP (TLS terminé à l'edge par kgateway) ;
  durcir avec TLS interne si besoin.
- **Audit** : activer un `audit device` (fichier/socket) pour la traçabilité.
- **Auth & rôles** : méthode `kubernetes` (mount `kubernetes`, rôle `eso`), OIDC pour l'UI.
- **Politiques** : ACL précises par chemin (least privilege).
- **Secrets engines** : KV v2 (utilisé), PKI, database, transit, etc.
- **Backup** : snapshots Raft + sauvegarde du stockage.

## Mini-formation

1. Initialiser et dés sceller (une fois, via un pod ou `bao` CLI) :
   ```bash
   kubectl exec -n openbao openbao-0 -- bao operator init -key-shares=3 -key-threshold=2
   kubectl exec -n openbao openbao-0 -- bao operator unseal <key1>
   kubectl exec -n openbao openbao-0 -- bao operator unseal <key2>
   ```
2. Activer KV v2 et l'auth Kubernetes (correspond à la config ESO) :
   ```bash
   bao secrets enable -path=apps kv-v2
   bao auth enable kubernetes
   ```
3. Créer une politique + rôle pour ESO :
   ```bash
   bao policy write eso - <<'EOF'
   path "apps/data/*" { capabilities = ["read"] }
   EOF
   bao write auth/kubernetes/role/eso \
     bound_service_account_names=external-secrets \
     bound_service_account_namespaces=external-secrets \
     policies=eso ttl=1h
   ```
4. Écrire un secret et vérifier côté cluster (ESO) :
   ```bash
   bao kv put apps/demo/app password=s3cr3t
   kubectl get secret demo-app-secret -n frontend
   ```
5. Accéder à l'UI : `http://openbao.example.com` (via HTTPRoute) ou port-forward du service `openbao`.

## Dashboard

**OpenBao UI** (intégré, `ui.enabled: true`) : interface web pour gérer les secrets,
les engines, l'auth et les politiques.
