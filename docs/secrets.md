# Secrets

Two complementary mechanisms:

- **SOPS + age** — encrypt secrets at rest in Git.
- **External Secrets Operator (ESO)** — sync secrets from cloud Secret Managers.
- **OpenBao** — a self-hosted secrets engine (the open-source fork of HashiCorp Vault),
  deployed as a highly-available cluster (integrated Raft storage).

## SOPS + age

1. Generate an age keypair:

   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt
   age-keygen -y ~/.config/sops/age/keys.txt   # -> public key
   ```

2. Paste the public key into `config/age/keys.txt` and `.sops.yaml`.

3. Encrypt a file:

   ```bash
   sops --encrypt --in-place secrets.enc.yaml
   ```

4. Store the age private key in the cluster for Flux decryption:

   ```bash
   kubectl -n flux-system create secret generic sops-age \
     --from-file=age.agekey=~/.config/sops/age/keys.txt
   ```

5. Reference decryption in the relevant `Kustomization`:

   ```yaml
   spec:
     decryption:
       provider: sops
       secretRef:
         name: sops-age
   ```

## External Secrets Operator

ESO is installed as an infrastructure component (`external-secrets`). Create a
`ClusterSecretStore` pointing at your cloud Secret Manager, then `ExternalSecret`
resources to mirror values into Kubernetes Secrets.

A `ClusterSecretStore` pointing at OpenBao (`provider: openbao`, Kubernetes auth) is
already provisioned in `infrastructure/components/external-secrets/configs/` — see
[OpenBao](#openbao) below.

Example (`ClusterSecretStore` for AWS Secrets Manager):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
```

Example (`ExternalSecret`):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app
  namespace: frontend
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: my-app-secret
  data:
    - secretKey: password
      remoteRef:
        key: my-app
        property: password
```

> Credentials for the cloud provider (via workload identity / IRSA) are documented in
> [docs/multi-cloud.md](multi-cloud.md).

## OpenBao

OpenBao is installed as an infrastructure component (`openbao`) in HA mode with
integrated Raft storage (3 replicas) and the agent injector enabled. It is exposed
through ingress-nginx with a cert-manager issued certificate (`openbao` ingress).

Initialise and unseal the cluster once it is running:

```bash
# Initialise (prints root token + unseal keys — store them securely)
kubectl -n openbao exec -ti openbao-0 -- bao operator init

# Unseal the leader, then join the remaining replicas to the Raft cluster
kubectl -n openbao exec -ti openbao-0 -- bao operator unseal
kubectl -n openbao exec -ti openbao-1 -- bao operator raft join http://openbao-0.openbao-internal:8200
kubectl -n openbao exec -ti openbao-1 -- bao operator unseal
kubectl -n openbao exec -ti openbao-2 -- bao operator raft join http://openbao-0.openbao-internal:8200
kubectl -n openbao exec -ti openbao-2 -- bao operator unseal
```

ESO consumes OpenBao through a provisioned `ClusterSecretStore` (`name: openbao`,
`provider: openbao`, Kubernetes auth with the `external-secrets` ServiceAccount), plus
an example `ExternalSecret` (`demo-app`) in the `frontend` namespace. Before the store
can sync, configure OpenBao once:

```bash
# Enable a KV v2 engine and the Kubernetes auth method
kubectl -n openbao exec -ti openbao-0 -- bao secrets enable -path=apps kv-v2
kubectl -n openbao exec -ti openbao-0 -- bao auth enable kubernetes

# Create the role that maps the external-secrets ServiceAccount to a policy
kubectl -n openbao exec -ti openbao-0 -- bao write auth/kubernetes/role/eso \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-reader \
  ttl=1h
```

The injector can also sidecar-inject secrets into workloads via the
`openbao.org/agent-inject` annotation.
