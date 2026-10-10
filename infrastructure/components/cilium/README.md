<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/cilium/icon/color/cilium_icon-color.svg" alt="Cilium logo" width="160" />
</p>

# Cilium

> **Runbook** : [docs/runbooks/cilium.md](../../../docs/runbooks/cilium.md)

> **Site officiel** : https://cilium.io/
> **Documentation** : https://docs.cilium.io/
> **Chart Helm** : https://artifacthub.io/packages/helm/cilium/cilium

## À quoi ça sert ?

Cilium est le **CNI** (réseau) et la couche **réseau/sécurité eBPF** du cluster. Il
remplace kube-proxy, fournit la connectivité des pods (overlay/natif), et applique des
**NetworkPolicies** enrichies (L3/L4/L7, identités, DNS, HTTP).

Il embarque aussi **Hubble**, la couche d'observabilité réseau (flux, logs,
connectivité), ainsi qu'un service mesh optionnel et des fonctions avancées
(chiffrement, load-balancing, BGP).

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `cilium` **1.20.2** (repo `https://helm.cilium.io/`) |
| Namespace cible | `kube-system` (`targetNamespace`) |
| `ipam.mode` | `kubernetes` (allocation par le cluster) |
| `kubeProxyReplacement` | `false` (kube-proxy encore utilisé) |
| `hubble.enabled` | `true` |
| `hubble.relay` | `true` |
| `hubble.ui` | `true` |

Fichier clé : `controllers/base/cilium.yaml` — la `HelmRelease` d'installation.

## Configurations à considérer

- **`kubeProxyReplacement: true`** (mode « kube-proxy-free ») : meilleures perf et
  permet le chiffrement/l'observabilité complets ; à activer quand on maîtrise l'env.
- **`clusterPoolIPv4PodCIDR`** : changer de `ipam.mode: kubernetes` vers
  `cluster-pool` pour une gestion autonome des CIDR pods.
- **Chiffrement** : `encryption` WireGuard ou IPsec pour le trafic entre nœuds.
- **NetworkPolicy L7** : règles DNS/HTTP via `CiliumNetworkPolicy`.
- **ClusterMesh** : interconnecter plusieurs clusters (services partagés).
- **BGP / LoadBalancer** : annoncer les IP de service via BGP (`bgpControlPlane`).
- **`bandwidthManager`** : gestion de bande passante par pod.
- **Service mesh** : activer le mesh Cilium ou rester sur Istio (éviter les deux en même temps).

## Mini-formation

1. Vérifier l'état :
   ```bash
   cilium status
   cilium connectivity test   # test de connectivité complet
   ```
2. Inspecter les identités et politiques :
   ```bash
   kubectl get ciliumnetworkpolicies -A
   cilium policy get
   ```
3. Accéder à **Hubble UI** :
   ```bash
   cilium hubble ui
   ```
4. Observer un flux réseau :
   ```bash
   cilium hubble observe
   ```

## Dashboard

- **Hubble UI** (intégré, activé ici : `hubble.ui: true`) — visualisation temps réel
  des flux réseau et des dépendances entre services.
- **Grafana** : Cilium publie des dashboards officiels (métriques `cilium_*`).
