<p align="center">
  <img src="https://raw.githubusercontent.com/kubernetes-sigs/external-dns/master/docs/img/external-dns.png" alt="ExternalDNS logo" width="280" />
</p>

# ExternalDNS

> **Site / projet** : https://kubernetes-sigs.github.io/external-dns/
> **Documentation** : https://kubernetes-sigs.github.io/external-dns/latest/
> **Chart Helm** : https://artifacthub.io/packages/helm/external-dns/external-dns

## À quoi ça sert ?

ExternalDNS **synchronise les enregistrements DNS** avec votre fournisseur DNS
(Route53, Cloudflare, Google Cloud DNS, Azure DNS, …) à partir des ressources
Kubernetes (`Service` de type LoadBalancer, `Ingress`, `Gateway`, CRDs).

Dès qu'un HTTPRoute/Service déclare un nom d'hôte, ExternalDNS crée/maintient l'enregistrement
DNS correspondant. C'est le chaînon manquant entre le cluster et le DNS public.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `external-dns` **1.23.0** (repo `https://kubernetes-sigs.github.io/external-dns/`) |
| Namespace | `external-dns` |
| `provider` | `aws` (Route53) |
| `policy` | `sync` (créer **et supprimer** les enregistrements) |
| `sources` | `service`, `gateway-httproute` |

Fichier clé : `controllers/base/external-dns.yaml` — la `HelmRelease`.

## Configurations à considérer

- **Fournisseur** : adapter `provider` (gcp, azure, cloudflare, digitalocean, …) et
  les identifiants associés. En prod, utiliser **IRSA** (AWS) / Workload Identity
  (GCP) plutôt que des clés statiques.
- **`policy`** : passer à `upsert-only` si vous ne voulez pas qu'ExternalDNS supprime
  des enregistrements qu'il ne gère pas.
- **`domainFilters`** : limiter les domaines gérés (éviter d'agir sur tout le compte).
- **`txtPrefix` / `txtSuffix`** : préfixe/suffixe des enregistrements TXT (ownership).
- **`interval`** : fréquence de resync (défaut 1m).
- **`registry`** : mode `txt` (défaut) vs `noop`.
- Ajouter les sources `gateway-*`, `istio-gateway`, `crd` selon les cas.

## Mini-formation

1. Déclarer un `HTTPRoute` (les hostnames sont lus depuis `spec.hostnames`) :
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: demo
   spec:
     parentRefs: [ { name: kgateway, namespace: kgateway } ]
     hostnames: [ demo.example.com ]
     rules: [ { backendRefs: [ { name: demo, port: 80 } ] } ]
   ```
2. Vérifier que l'enregistrement est créé :
   ```bash
   kubectl logs -n external-dns deploy/external-dns
   # puis vérifier côté fournisseur (ex. Route53)
   ```
3. Supprimer l'annotation/objet → l'enregistrement est supprimé (policy `sync`).

## Dashboard

Pas de dashboard intégré. ExternalDNS expose des **métriques Prometheus**
(`external_dns_*`) monitorables dans Grafana.
