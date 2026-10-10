# kube-vip — Runbook

> **Code** : `infrastructure/components/kube-vip/` · **Version** : `kube-vip` **0.11.1** (app v1.2.3) + `kube-vip-cloud-provider` **0.2.10**
> **Namespace Flux** : `kube-vip` · **Namespace pods** : `kube-system` · **Shard (prod)** : `shard-core`
> Voir : [README du composant](../../infrastructure/components/kube-vip/README.md)

## Rôle

kube-vip fournit l'**IP virtuelle (VIP)** des services `LoadBalancer` sur les
clusters **on-prem** (pas de LB cloud). Deux contrôleurs : le **DaemonSet**
`kube-vip` annonce les VIP en **ARP** (L2) sur chaque nœud, et le **Deployment**
`kube-vip-cloud-provider` alloue les IP depuis le pool `cidr-global`. Sans lui,
aucun service `LoadBalancer` (dont le proxy Envoy de kgateway) ne reçoit
d'`EXTERNAL-IP`.

## Infos clés

| | |
|---|---|
| Namespace(s) | pods dans `kube-system`, sources Flux dans `kube-vip` |
| Dépendances | Cilium (CNI) — les VIP reposent sur la connectivité L2 des nœuds |
| Mode | L2 / ARP (`vip_arp: true`), pas de BGP |
| Pool d'IP | ConfigMap `kubevip` (namespace `kube-system`) → `cidr-global: ${LOADBALANCER_CIDR}` |
| `cp_enable` | `false` (pas de VIP du plan de contrôle) |

## Vérifications de santé

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-cloud-provider
kubectl -n kube-system get ds kube-vip -o wide          # un pod par nœud
kubectl -n kube-system get configmap kubevip -o yaml   # cidr-global non vide
kubectl get svc -A -o wide | grep -i loadbalancer      # EXTERNAL-IP allouées
```

Signes de bonne santé : un pod `kube-vip` **par nœud** Ready, `kube-vip-cloud-provider`
Ready, la ConfigMap `kubevip` contient un `cidr-global`, et les `Service`
`LoadBalancer` ont une `EXTERNAL-IP`.

## Opérations courantes

- **Voir les logs du DaemonSet** : `kubectl -n kube-system logs -l app.kubernetes.io/name=kube-vip --tail=100`
- **Voir les logs du cloud provider** : `kubectl -n kube-system logs -l app.kubernetes.io/name=kube-vip-cloud-provider --tail=100`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n kube-vip
  flux reconcile kustomization infra-controllers -n kube-vip
  flux reconcile kustomization infra-configs -n kube-vip
  ```
- **Forcer la réallocation d'une VIP** : supprimer le `Service` LoadBalancer
  (le cloud provider le recrée avec une IP) ou l'annotation
  `kube-vip.io/ignore` pour l'exclure.
- **Changer le pool** : modifier `LOADBALANCER_CIDR` dans `flux-runtime-info`
  (`fleet/clusters/<env>/flux-system/runtime-info.yaml`), puis re-rendre/re-pousser.

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `Service` LoadBalancer sans `EXTERNAL-IP` (`pending`) | cloud provider down ou pool vide | `kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-vip-cloud-provider`, vérifier `cidr-global` |
| VIP allouée mais injoignable | ARP non propagé / mauvaise interface | Vérifier `vip_interface`, `kubectl -n kube-system logs -l app.kubernetes.io/name=kube-vip` |
| VIP qui « saute » entre nœuds | Plusieurs réplicas annoncent la même VIP | Activer `svc_election: "true"` / `vip_leaderelection: "true"` |
| `kube-vip` en `CrashLoopBackOff` | Capabilités `NET_ADMIN`/`NET_RAW` manquantes | Vérifier le securityContext du DaemonSet, logs |
| Pool épuisé | `cidr-global` trop petit | Élargir le `cidr-global` (ou passer en `range-<ns>` par namespace) |
| Cloud provider en boucle | RBAC incomplet | `kubectl -n kube-system logs -l app.kubernetes.io/name=kube-vip-cloud-provider`, vérifier les ClusterRole |

## Mise à jour (upgrade)

1. Bumper `version:` des deux releases dans `controllers/base/kube-vip.yaml`
   (`kube-vip` et `kube-vip-cloud-provider`), en respectant les
   [release notes](https://kube-vip.io/docs/about/release/).
2. Mettre à jour la ligne kube-vip dans [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider en staging d'abord : vérifier qu'un `Service` LoadBalancer reçoit bien
   une `EXTERNAL-IP` et qu'elle est joignable.

## Sauvegarde / restauration

Pas de données propres (état en mémoire + ConfigMap `kubevip`). La restauration =
re-déploiement via Flux + re-création de la ConfigMap `kubevip` (source de vérité :
`configs/base/kubevip-pool.yaml` + `LOADBALANCER_CIDR` dans `flux-runtime-info`).

## Métriques & alertes

Métriques Prometheus exposées sur `:2112` (`podMonitor` désactivé par défaut — à
activer via `podMonitor.enabled: true`). Alerte critique : aucun pod `kube-vip` Ready
sur un nœud, ou `Service` LoadBalancer sans IP au-delà d'un délai.
