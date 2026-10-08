<p align="center">
  <img src="https://raw.githubusercontent.com/kgateway-dev/kgateway/main/website/public/img/logo-kgateway-envoy.svg" alt="kgateway logo" width="160" />
</p>

# kgateway

> **Site officiel** : https://kgateway.dev/
> **Documentation** : https://kgateway.dev/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/kgateway/kgateway

## À quoi ça sert ?

**kgateway** (ex-Gloo Gateway, projet CNCF Sandbox) est la **passerelle d'entrée
nord-sud** basée sur **Envoy** et la **Kubernetes Gateway API**. Il remplace
ingress-nginx dans ce dépôt : il reçoit le trafic HTTP/HTTPS externe et le route
vers les services du cluster via des `Gateway` et `HTTPRoute`.

Contrairement à un contrôleur Ingress, kgateway consomme les ressources de la
**Gateway API** (`GatewayClass`, `Gateway`, `HTTPRoute`) et fournit un plan de
données Envoy (proxy) dédié.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `kgateway` **v2.4.3** + `kgateway-crds` **v2.4.3** (OCI `oci://cr.kgateway.dev/kgateway-dev/charts/...`) |
| Namespace contrôleur | `kgateway-system` (`targetNamespace`) |
| Namespace des ressources Flux | `kgateway` |
| Gateway API CRDs | standard channel **v1.6.1** (`controllers/base/gateway-api-crds.yaml`, pré-requis) |
| `Gateway` | `kgateway` (namespace `kgateway`), listeners HTTP (80) + HTTPS (443) |
| TLS | `Certificate` `kgateway-tls` via cert-manager (`http01` + solver `gatewayHTTPRoute`) |

Fichiers clés :
- `controllers/base/kgateway.yaml` — les deux `HelmRelease` (`kgateway-crds` puis `kgateway`).
- `controllers/base/gateway-api-crds.yaml` — les CRDs standard de la Gateway API (pré-requis).
- `configs/base/gateway.yaml` — la `Gateway` partagée.
- `configs/base/certificate.yaml` — le `Certificate` TLS (SAN `frontend.<dom>` + `openbao.<dom>`).

## À propos des hostnames

Les hostnames sont configurés **au niveau du tenant** (champ `host` des `inputs`
dans `fleet/tenants/{apps,infra}.yaml`), puis injectés dans les `HTTPRoute` via une
`ConfigMap` générée + `postBuild.substituteFrom` (`${HOST}`).

Le `Certificate` de la `Gateway` énumère les hostnames qu'il termine en TLS
(`frontend.${CLUSTER_DOMAIN}`, `openbao.${CLUSTER_DOMAIN}`). Ajouter une app =
ajouter son host à ce `Certificate` (le TLS se termine à la `Gateway`, pas sur la
route).

## Configurations à considérer

- **Plan de données / `Service`** : par défaut kgateway crée un proxy Envoy par
  `Gateway`. Ajuster le type de `Service` (LoadBalancer, ClusterIP + IP statique)
  via une `GatewayParameters` (`gateway.kgateway.dev`).
- **`hostNetwork` / IP statique** : sur on-prem, prévoir une annotation/IP de LB.
- **Policies kgateway** : `TrafficPolicy`, `BackendConfigPolicy`, `ListenerPolicy`
  pour rate-limiting, timeouts, retries, auth externe, CORS, etc.
- **HA** : `controller.replicas`, anti-affinité, `PodDisruptionBudget`.
- **Upgrade Gateway API** : lire les release notes avant de bumper la version des CRDs
  (la Gateway API impose des règles d'upgrade spécifiques).

## Mini-formation

1. Vérifier la GatewayClass et la Gateway :
   ```bash
   kubectl get gatewayclass kgateway
   kubectl get gateway -n kgateway
   ```
2. Déployer une app + un `HTTPRoute` :
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata: { name: demo, namespace: demo }
   spec:
     parentRefs: [ { name: kgateway, namespace: kgateway } ]
     hostnames: [ demo.example.com ]
     rules:
       - backendRefs: [ { name: demo, port: 80 } ]
   ```
3. Tester :
   ```bash
   curl -H "Host: demo.example.com" http://<LB_IP>/
   ```
4. Inspecter le statut des routes :
   ```bash
   kubectl get httproute -A
   ```

## Dashboard

Pas de dashboard intégré. Les métriques Prometheus du contrôleur et d'Envoy sont
exposées (`controller.serviceMonitor` / annotations `prometheus.io`) : dashboards
Grafana kgateway/Envoy disponibles sur grafana.com.
