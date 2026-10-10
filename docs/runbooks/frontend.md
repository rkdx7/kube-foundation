# Frontend — Runbook

> **Code** : `apps/components/frontend/` · **Version** : image `latest` (Go)
> **Namespace Flux** : `frontend` · **Namespace pods** : `frontend` · **Shard (prod)** : `shard-platform`

## Rôle

Application de **démonstration** (Go) exposée publiquement via une `HTTPRoute` sur la
Gateway kgateway. C'est la cible des smoke tests de la plateforme.

## Infos clés

| | |
|---|---|
| Namespace(s) | `frontend` |
| Dépendances | kgateway (HTTPRoute), cert-manager (TLS), backend (si l'app l'appelle) |
| Image | `${REGISTRY_HOST}/${REPOSITORY}/images/frontend:latest` |
| Port | `8080`, probes `/healthz` (liveness) et `/readyz` (readiness) |

## Vérifications de santé

```bash
kubectl -n frontend get pods,svc
kubectl -n frontend get httproute
kubectl -n frontend logs deploy/frontend --tail=50
curl -H "Host: frontend.${CLUSTER_DOMAIN}" http://<LB_IP>/
```

Signes de bonne santé : 2 réplicas `Running` et `Ready`, `HTTPRoute` `Accepted`, et le
`curl` renvoie une réponse HTTP 200.

## Opérations courantes

- **Redémarrer** : `kubectl -n frontend rollout restart deploy/frontend`
- **Scaler** : `kubectl -n frontend scale deploy/frontend --replicas=N`
- **Voir les logs** : `kubectl -n frontend logs -l app.kubernetes.io/name=frontend --tail=100`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci apps -n frontend
  flux reconcile kustomization apps -n frontend
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `HTTPRoute` `ResolvedRefs=False` | Service/backend manquant | `kubectl describe httproute frontend -n frontend` |
| 503/502 depuis la Gateway | Pods pas `Ready` | Vérifier les probes `/healthz` `/readyz` |
| Image `ErrImagePull` | Registry injoignable / tag `latest` introuvable | Vérifier le build et le registry |
| App down après un push | `latest` redéployé mais pas reconcilié | Forcer la réconciliation Flux |

## Mise à jour (upgrade)

1. Modifier l'app (`apps/components/frontend/app/`), puis rebuilder l'image
   (`./scripts/devbox.sh build`) et pousser l'artefact OCI.
2. Bumper le `tag:` dans `fleet/tenants/apps.yaml` si tu pinces une version, puis
   mettre à jour [`docs/versions.md`](../versions.md).
3. Valider : `curl -H "Host: frontend.${CLUSTER_DOMAIN}" http://<LB_IP>/` → 200.

## Sauvegarde / restauration

App **stateless** (pas de données). Restauration = re-déploiement via Flux. Le backup
du namespace passe par Velero (voir son runbook).

## Métriques & alertes

Métriques applicatives exposées (`/metrics` si implémenté) scrapées par Prometheus.
Alerte : aucun réplica `Ready`, taux de 5xx sur la route.
