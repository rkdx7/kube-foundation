# kgateway — Runbook

> **Code** : `infrastructure/components/kgateway/` · **Version** : `kgateway` **v2.4.3** (+ Gateway API CRDs **v1.6.1**)
> **Namespace Flux** : `kgateway` · **Namespace contrôleur** : `kgateway-system` · **Shard (prod)** : `shard-core`
> Voir : [README du composant](../../infrastructure/components/kgateway/README.md)

## Rôle

kgateway (ex-Gloo Gateway) est la **passerelle d'entrée nord-sud** basée sur Envoy et
la **Gateway API**. Tout le trafic HTTP/HTTPS externe passe par lui. Une panne =
applications inaccessibles de l'extérieur.

## Infos clés

| | |
|---|---|
| Namespace(s) | contrôleur Envoy dans `kgateway-system`, ressources Gateway/HTTPRoute dans `kgateway` |
| Dépendances | Gateway API CRDs, cert-manager (TLS), ExternalDNS (DNS) |
| Gateway | `kgateway` (namespace `kgateway`), listeners 80 + 443 |
| TLS | `Certificate` `kgateway-tls` (cert-manager, HTTP-01) |

## Vérifications de santé

```bash
kubectl get gatewayclass kgateway
kubectl -n kgateway get gateway
kubectl get httproute -A
kubectl -n kgateway-system get pods
kubectl -n kgateway get certificate kgateway-tls
```

Signes de bonne santé : `GatewayClass` `Accepted`, `Gateway` `Programmed=True`, tous
les `HTTPRoute` avec une `ResolvedRefs` et un `Accepted` à `True`.

## Opérations courantes

- **Voir les logs du contrôleur** : `kubectl -n kgateway-system logs -l app.kubernetes.io/name=kgateway --tail=100`
- **Voir les logs du proxy Envoy** : `kubectl -n kgateway-system logs -l gateway.kgateway.dev/role=gateway --tail=100`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n kgateway
  flux reconcile kustomization infra-controllers -n kgateway
  flux reconcile kustomization infra-configs -n kgateway
  ```
- **Tester une route** : `curl -H "Host: <hostname>" http://<LB_IP>/` ou
  `kubectl -n kgateway get svc` pour retrouver le service du proxy.

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `Gateway` non `Programmed` | CRDs Gateway API manquantes/mal versionnées | Vérifier `gateway-api-crds.yaml` et la compatibilité de version |
| `HTTPRoute` `ResolvedRefs=False` | backend ou parent inexistant | `kubectl describe httproute <r> -n <ns>` |
| 404/502 sur un hostname | Pas de `HTTPRoute` avec ce hostname | `kubectl get httproute -A -o wide`, vérifier `spec.hostnames` |
| TLS invalide / cert manquante | `Certificate` non `Ready` (ACME en échec) | Voir le runbook [cert-manager](cert-manager.md) |
| Ajout d'app → pas de TLS | hostname absent du `Certificate` `kgateway-tls` | Ajouter le host au `Certificate` (`configs/base/certificate.yaml`) |

## Mise à jour (upgrade)

1. Bumper `version:` des deux releases (`kgateway-crds` puis `kgateway`) dans
   `controllers/base/kgateway.yaml`.
2. Si tu bumpes aussi les **Gateway API CRDs**, lire les règles d'upgrade de la
   Gateway API (upgrades ordonnés, pas de saut de version).
3. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
4. Valider : `kubectl get gatewayclass` + un `curl` sur chaque app.

## Sauvegarde / restauration

Sans état (config déclarative). La restauration = re-déploiement via Flux. Garder la
`Gateway` et les `Certificate` sous contrôle de version.

## Métriques & alertes

Métriques Envoy (`envoy_*`, `envoy_cluster_upstream_cx_*`) et du contrôleur. Alerte
critique : `Gateway` non programmé, hausse du taux de 5xx, proxy non prêt.
