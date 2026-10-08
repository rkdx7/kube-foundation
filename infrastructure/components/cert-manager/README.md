<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/cert-manager/icon/color/cert-manager-icon-color.svg" alt="cert-manager logo" width="160" />
</p>

# cert-manager

> **Site officiel** : https://cert-manager.io/
> **Documentation** : https://cert-manager.io/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/cert-manager/cert-manager

## À quoi ça sert ?

cert-manager automatise la **gestion des certificats TLS/X.509** dans Kubernetes. Il
émet, renouvelle et révoque des certificats signés par une autorité de certification
(CA) — le plus souvent **Let's Encrypt** (ACME) — et les injecte dans des secrets
Kubernetes consommables par les Ingress, les services, les webhooks, etc.

Il gère le cycle de vie complet : demande, validation du domaine (challenge),
émission, stockage en `Secret`, et **renouvellement automatique** avant expiration.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `cert-manager` **v1.21.2** (repo `https://charts.jetstack.io`) |
| Namespace | `cert-manager` |
| `installCRDs` | `true` (les CRD `Certificate`, `Issuer`, `ClusterIssuer`…) |
| Métriques | `prometheus.enabled: true` + `ServiceMonitor` |
| `ClusterIssuer` staging | `letsencrypt-staging` — ACME `http01`, ingress class `nginx` |
| `ClusterIssuer` prod | `letsencrypt-prod` — ACME `http01`, ingress class `nginx` |
| Email ACME | `letsencrypt@example.com` (⚠️ à remplacer) |

Fichiers clés :
- `controllers/base/cert-manager.yaml` — la `HelmRelease` (installation du contrôleur).
- `configs/staging/cluster-issuer.yaml` / `configs/prod/cluster-issuer.yaml` — les `ClusterIssuer` ACME par environnement.

## Configurations à considérer

- **`dns01` au lieu de `http01`** : indispensable pour les certificats wildcard
  (`*.example.com`) et plus fiable si le port 80/443 n'est pas exposé publiquement.
  Nécessite de configurer un fournisseur DNS (Cloudflare, Route53, …).
- **Email ACME** : remplacer `letsencrypt@example.com` par une vraie adresse (notifications
  d'expiration).
- **`renewBefore` / `duration`** : ajuster la fenêtre de renouvellement (défaut 30 jours).
- **Issuer alternatif** : utiliser un `Issuer` Vault/OpenBao, une CA interne, ou un
  fournisseur cloud (AWS PCA) au lieu d'ACME.
- **`ingressShim`** : annoter directement les `Ingress` avec
  `cert-manager.io/cluster-issuer` pour créer les certificats automatiquement.
- **Haute dispo / scaling** : répliques du contrôleur, ressources CPU/mémoire.
- **Private CA** : via l'Issuer `selfSigned` ou `CA`.

## Mini-formation

1. Installer (c'est déjà fait via Flux ici) :
   ```bash
   helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true
   ```
2. Créer un `ClusterIssuer` Let's Encrypt :
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata: { name: letsencrypt-prod }
   spec:
     acme:
       email: me@example.com
       server: https://acme-v02.api.letsencrypt.org/directory
       privateKeySecretRef: { name: letsencrypt-prod-account-key }
       solvers: [ { http01: { ingress: { class: nginx } } } ]
   ```
3. Créer un `Certificate` :
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata: { name: demo-tls, namespace: default }
   spec:
     secretName: demo-tls
     dnsNames: [ demo.example.com ]
     issuerRef: { name: letsencrypt-prod, kind: ClusterIssuer }
   EOF
   ```
4. Vérifier l'émission :
   ```bash
   kubectl get certificate,secret -n default
   kubectl describe certificate demo-tls -n default
   ```
5. (Optionnel) Plugin CLI : `kubectl cert-manager status certificate demo-tls`.

## Dashboard

Pas de dashboard intégré. cert-manager expose des **métriques Prometheus**
(`certmanager_*` : expirations, nombre d'émissions…) exploitables via **Grafana**
(des dashboards communautaires existent sur grafana.com, ex. « cert-manager »).
L'essentiel du monitoring passe par `kubectl get certificate` + les alertes.
