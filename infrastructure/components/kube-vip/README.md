<p align="center">
  <img src="https://raw.githubusercontent.com/kube-vip/kube-vip/main/docs/images/kube-vip.png" alt="kube-vip logo" width="160" />
</p>

# kube-vip

> **Runbook** : [docs/runbooks/kube-vip.md](../../../docs/runbooks/kube-vip.md)

> **Site officiel** : https://kube-vip.io/
> **Documentation** : https://kube-vip.io/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/kube-vip/kube-vip

## À quoi ça sert ?

**kube-vip** (projet CNCF Sandbox) fournit une **IP virtuelle (VIP)** et un
**load-balancing** pour les clusters **sans fournisseur cloud**. Dans ce dépôt, il est
déployé en deux morceaux complémentaires :

- **`kube-vip`** (DaemonSet) : annonce les VIP des services `LoadBalancer` via
  **ARP** (mode L2) sur chaque nœud.
- **`kube-vip-cloud-provider`** (Deployment) : joue le rôle de *cloud controller
  manager* — il observe les `Service` de type `LoadBalancer` et leur alloue une IP
  depuis un pool (`cidr-global`), puis kube-vip l'annonce.

C'est l'équivalent on-prem de l'Elastic Load Balancer d'AWS, du LB GCP ou d'Azure.
Il permet aux services exposés (par ex. le proxy Envoy de **kgateway**) d'obtenir une
IP stable joignable depuis l'extérieur, sans MetalLB ni équilibreur matériel.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Charts / versions | `kube-vip` **0.11.1** (app v1.2.3) + `kube-vip-cloud-provider` **0.2.10** (repo `https://kube-vip.github.io/helm-charts/`) |
| Namespace des pods | `kube-system` (`targetNamespace`) |
| Namespace des ressources Flux | `kube-vip` |
| Mode | **L2 / ARP** (`vip_arp: true`) — pas de BGP |
| `cp_enable` | `false` (pas de VIP du plan de contrôle) |
| `svc_enable` | `true` (VIP des services `LoadBalancer`) |
| Pool d'IP | `cidr-global` fourni par la ConfigMap `kubevip` (namespace `kube-system`) |

Fichiers clés :
- `controllers/base/kube-vip.yaml` — les deux `HelmRelease` (DaemonSet + cloud provider).
- `configs/base/kubevip-pool.yaml` — la ConfigMap `kubevip` (`cidr-global`), alimentée
  par `${LOADBALANCER_CIDR}` (défini dans `flux-runtime-info`, par environnement).

## À propos du pool d'IP

Le pool est **spécifique à chaque environnement** : la valeur `${LOADBALANCER_CIDR}`
est résolue depuis `flux-runtime-info` (ConfigMap `fleet/clusters/<env>/flux-system/`)
puis propagée via la ConfigMap `kube-vip-flux-config` générée par le `ResourceSet`.
Exemple : `192.168.10.200/29` fournit 6 IP joignables pour les services `LoadBalancer`.

> Sur les fournisseurs cloud (`aws`/`gcp`/`azure`), le LoadBalancer vient du cloud :
> `LOADBALANCER_CIDR` est laissé vide et kube-vip n'alloue rien (voir
> [docs/multi-cloud.md](../../../docs/multi-cloud.md)).

## Configurations à considérer

- **`vip_interface`** : laisser vide (auto-détection) ou forcer l'interface réseau
  qui portera les VIP (`env.vip_interface`) si l'auto-détection se trompe.
- **BGP** : passer de l'ARP à BGP (`enableBGP`) pour une annonce routée au niveau
  des routeurs, avec `bgp_peers` + `bgp_routerid`.
- **`svc_election` / `vip_leaderelection`** : activer l'élection de leader pour éviter
  le flapping ARP quand plusieurs réplicas annoncent la même VIP.
- **`loadbalancerClass`** : restreindre kube-vip à certains services via
  `enableloadbalancerClass` + `spec.loadbalancerClass: kube-vip.io/kube-vip-class`.
- **Pools par namespace** : `cidr-<namespace>` / `range-<namespace>` dans la ConfigMap
  pour isoler les plages par tenant.
- **Métriques** : `podMonitor.enabled: true` (kube-vip) + `prometheus_server` pour
  exposer les métriques au monitoring de la plateforme.

## Mini-formation

1. Vérifier que les deux contrôleurs tournent :
   ```bash
   kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip
   kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-cloud-provider
   ```
2. Inspecter le pool :
   ```bash
   kubectl -n kube-system get configmap kubevip -o yaml
   ```
3. Exposer un service en `LoadBalancer` et observer l'allocation :
   ```bash
   kubectl expose deploy frontend --name frontend-lb --type=LoadBalancer --port=80 -n frontend
   kubectl -n frontend get svc frontend-lb -w   # l'EXTERNAL-IP apparaît
   ```
4. Tester la VIP depuis un hôte du réseau :
   ```bash
   curl http://<EXTERNAL-IP>/
   ```

## Dashboard

Pas de dashboard intégré. kube-vip expose des **métriques Prometheus** sur
`/metrics` (port `2112` par défaut) via `podMonitor`, intégrables au monitoring
Grafana de la plateforme.
