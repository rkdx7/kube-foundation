<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/istio/icon/color/istio-icon-color.svg" alt="Istio logo" width="160" />
</p>

# Istio

> **Runbook** : [docs/runbooks/istio.md](../../../docs/runbooks/istio.md)

> **Site officiel** : https://istio.io/
> **Documentation** : https://istio.io/latest/docs/
> **Charts Helm** : https://artifacthub.io/packages/helm/istio-official/base

## À quoi ça sert ?

**Istio** est le **service mesh** : il gère le trafic **est-ouest** (entre services)
avec des sidecars Envoy injectés dans chaque pod. Il fournit :

- **mTLS** automatique entre services,
- **routage avancé** (canary, blue/green, retries, timeouts, fault injection),
- **observabilité** (télémétrie, tracing distribué),
- **politiques** (autorisation, rate-limiting) via `VirtualService`,
  `DestinationRule`, `PeerAuthentication`, `AuthorizationPolicy`.

Dans ce dépôt il fonctionne en complément de kgateway (entrée nord-sud) et
d'ExternalDNS/cert-manager.

## Configuration appliquée (dans ce dépôt)

Trois `HelmRelease` (`controllers/base/istio.yaml`, version **1.30.5**) :

| Release | Chart | Détails |
|---|---|---|
| `istio-base` | `base` | CRDs + composants de base |
| `istiod` | `istiod` | `dependsOn: istio-base`, `meshConfig.accessLogFile: /dev/stdout`, `pilot.autoscaleEnabled: false`, `pilot.replicas: 1` |
| `istio-ingress` | `gateway` | `dependsOn: istiod`, passerelle d'entrée |

Namespace de déploiement : `istio-system` (`targetNamespace`), créé automatiquement.

## Configurations à considérer

- **mTLS strict** : `PeerAuthentication` en mode `STRICT` pour forcer le chiffrement.
- **Addons d'observabilité** : installer **Kiali** (UI), Prometheus, Grafana, Jaeger
  pour exploiter le mesh (non inclus ici, Grafana/Prometheus étant gérés par `monitoring`).
- **Sidecar injection** : label `istio-injection=enabled` sur les namespaces ciblés,
  ou `Sidecar`/`PeerAuthentication` par workload.
- **Ressources du gateway** : `requests/limits` et `replicaCount` pour la passerelle.
- **Multi-cluster** : `istioctl` multi-cluster / mesh fédéré.
- **`meshConfig.defaultConfig`** : ajuster timeouts, retries par défaut.
- **CNI Istio** : `istio-cni` pour éviter le besoin de privilèges d'init-container.

## Mini-formation

1. Activer l'injection dans un namespace :
   ```bash
   kubectl label namespace default istio-injection=enabled
   ```
2. Déployer une app et un `VirtualService` :
   ```yaml
   apiVersion: networking.istio.io/v1
   kind: VirtualService
   metadata: { name: demo }
   spec:
     hosts: [ demo.example.com ]
     gateways: [ demo-gateway ]
     http:
       - route: [ { destination: { host: demo.default.svc.cluster.local, port: { number: 80 } } } ]
   ```
3. Vérifier l'état du mesh :
   ```bash
   istioctl analyze
   istioctl proxy-status
   ```
4. Faire un canary avec des `DestinationRule` + poids, puis observer dans **Kiali**.

## Dashboard

- **Kiali** (dashboard officiel du mesh) : graphe des services, trafic, santé, config.
  À installer séparément (chart `kiali-server`).
- **Grafana / Jaeger / Prometheus** : dashboards Istio officiels (télémétrie, tracing).
