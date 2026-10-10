# Cilium — Runbook

> **Code** : `infrastructure/components/cilium/` · **Version** : `cilium` **1.20.2**
> **Namespace Flux** : `cilium` · **Namespace pods** : `kube-system` · **Shard (prod)** : `shard-core`
> Voir : [README du composant](../../infrastructure/components/cilium/README.md)

## Rôle

Cilium est le **CNI** (réseau des pods) et la couche **sécurité/réseau eBPF** du
cluster. Si Cilium tombe, **tout le réseau du cluster tombe** : c'est le composant le
plus critique avec les API servers.

## Infos clés

| | |
|---|---|
| Namespace(s) | pods dans `kube-system`, sources Flux dans `cilium` |
| Dépendances | aucune (le plus bas niveau) |
| `kubeProxyReplacement` | `false` (kube-proxy encore actif) |
| Hubble | activé (`hubble.relay` + `hubble.ui`) |

## Vérifications de santé

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system get ds cilium -o wide
cilium status --wait            # état global (daemonset, clustermesh, contraintes)
cilium connectivity test        # test complet de connectivité (long)
kubectl get ciliumnodes -o wide # chaque nœud doit être Ready
```

Signes de bonne santé : `cilium status` tout vert, un pod `cilium` **par nœud** Ready,
`ciliumnodes` avec état `Ready`.

## Opérations courantes

- **Redémarrer l'agent sur un nœud** (après une panne locale) :
  ```bash
  kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=<node>
  ```
- **Voir les logs de l'agent** : `kubectl -n kube-system logs -l k8s-app=cilium --tail=100`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n cilium
  flux reconcile kustomization infra-controllers -n cilium
  ```
- **Inspecter les identités / politiques** : `cilium policy get`, `cilium endpoint list`.

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Pods en `ContainerCreating` partout | Agent Cilium down sur le nœud | `kubectl -n kube-system get pods -l k8s-app=cilium -o wide`, `cilium status` |
| `cilium` en `CrashLoopBackOff` | Kernel trop ancien / BPF non disponible | Vérifier le kernel et la compatibilité eBPF ; logs agent |
| `cilium connectivity test` en échec sur DNS | Politique réseau bloquante | `cilium policy get`, inspecter les `CiliumNetworkPolicy` |
| Hubble UI inaccessible | `hubble-relay`/`hubble-ui` down | `kubectl -n kube-system get pods -l k8s-app=hubble-ui,hubble-relay` |
| Changement de config non appliqué | `kubeProxyReplacement`/CIDR modifié mais non redémarré | Revoir `controllers/base/cilium.yaml`, forcer la réconciliation Flux |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/cilium.yaml` (respecter les
   [notes de release Cilium](https://docs.cilium.io/en/stable/operations/upgrade/) :
   upgrades **un minor à la fois**).
2. Mettre à jour la ligne Cilium dans [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `cilium status --wait` puis `cilium connectivity test` en staging d'abord.

## Sauvegarde / restauration

Pas de données propres (état dans etcd + eBPF). La restauration = re-déploiement via
Flux. En cas de migration de CIDR, prévoir un re-déploiement des pods.

## Métriques & alertes

Métriques `cilium_*` (drops, latence, identités). Dashboard Grafana officiel Cilium.
Alerte critique : nœud sans agent Cilium prêt, taux de `cilium_drop_count_total` anormal.
