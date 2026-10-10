# Istio — Runbook

> **Code** : `infrastructure/components/istio/` · **Version** : `istio` **1.30.5**
> **Namespace Flux** : `istio` · **Namespace pods** : `istio-system` · **Shard (prod)** : `shard-platform`
> Voir : [README du composant](../../infrastructure/components/istio/README.md)

## Rôle

Istio est le **service mesh** (trafic est-ouest, mTLS, routage avancé). Trois
`HelmRelease` : `istio-base`, `istiod`, `istio-ingress` (gateway).

## Infos clés

| | |
|---|---|
| Namespace(s) | pods dans `istio-system`, sources Flux dans `istio` |
| Releases | `istio-base` → `istiod` → `istio-ingress` (dépendances chaînées) |
| `pilot.autoscaleEnabled` | `false`, `pilot.replicas: 1` |

## Vérifications de santé

```bash
kubectl -n istio-system get pods
istioctl analyze          # analyse de la config du mesh
istioctl proxy-status     # sync des sidecars
kubectl -n istio-system get svc
```

Signes de bonne santé : `istiod` et `istio-ingressgateway` `Running`, `istioctl
proxy-status` sans `STALE`, `istioctl analyze` sans erreur bloquante.

## Opérations courantes

- **Activer l'injection sidecar sur un namespace** :
  `kubectl label namespace <ns> istio-injection=enabled`
- **Voir les logs d'istiod** : `kubectl -n istio-system logs deploy/istiod --tail=100`
- **Diagnostiquer un pod** : `istioctl proxy-status`, `istioctl x describe pod <pod> -n <ns>`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n istio
  flux reconcile kustomization infra-controllers -n istio
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `istiod` en `CrashLoop` | CRDs pas encore appliquées (`istio-base`) | Vérifier l'ordre des releases, `flux get helmrelease -n istio` |
| Sidecars `STALE`/non injectés | Label d'injection absent | Labeler le namespace, redémarrer les pods |
| Trafic est-ouest cassé | `PeerAuthentication`/`AuthorizationPolicy` | `istioctl analyze`, inspecter les politiques |
| `istio-ingress` non prêt | dépendance `istiod` en échec | Résoudre `istiod` d'abord |

## Mise à jour (upgrade)

1. Bumper les trois `version:` dans `controllers/base/istio.yaml` (même version).
2. Suivre le [guide d'upgrade Istio](https://istio.io/latest/docs/setup/upgrade/)
   (upgrade canary / `istioctl upgrade` recommandé en prod).
3. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
4. Valider : `istioctl analyze` + `istioctl proxy-status` après upgrade.

## Sauvegarde / restauration

Sans état (config déclarative). Restauration = re-déploiement. Le plan de contrôle
peut être recréé ; les sidecars se reconnectent.

## Métriques & alertes

Télémétrie `istio_*` (requêtes, latence, erreurs par service). Dashboards Grafana
Istio + Kiali. Alerte : `istiod` down, `proxy-status` STALE massif.
