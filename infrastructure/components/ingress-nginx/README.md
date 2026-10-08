<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/kubernetes/icon/color/kubernetes-icon-color.svg" alt="ingress-nginx (Kubernetes) logo" width="160" />
</p>

# ingress-nginx

> **Site / projet** : https://kubernetes.github.io/ingress-nginx/
> **Documentation** : https://kubernetes.github.io/ingress-nginx/
> **Chart Helm** : https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx

## À quoi ça sert ?

**ingress-nginx** est le **contrôleur Ingress** basé sur NGINX. Il gère l'entrée du
trafic HTTP/HTTPS vers les services du cluster : routing par nom d'hôte et chemin,
terminaison TLS, réécritures, rate-limiting, authentification, etc.

C'est le point d'entrée réseau standard (en amont d'Istio si le mesh est utilisé) :
il reçoit le trafic externe et le route vers les bonnes applications.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `ingress-nginx` **4.15.1** (repo `https://kubernetes.github.io/ingress-nginx/`) |
| Namespace | `ingress-nginx` |
| `controller.service.type` | `LoadBalancer` |
| `controller.metrics.enabled` | `true` |
| `controller.metrics.serviceMonitor.enabled` | `true` |

Fichier clé : `controllers/base/ingress-nginx.yaml` — la `HelmRelease`.

## Configurations à considérer

- **`externalTrafficPolicy: Local`** : préserver l'IP source du client (important pour
  les logs et la géolocalisation), au prix d'un équilibrage moins uniforme.
- **`hostNetwork` / IP statique** : sur on-prem, prévoir une IP/annotation de LB.
- **`proxy-body-size`, `proxy-buffer-size`** : pour les uploads volumineux.
- **`ssl-redirect`, `hsts`** : durcir le TLS (force HTTPS).
- **`default-backend`** : page 404 personnalisée.
- **`tcp` / `udp` services** : exposer des services non-HTTP (base de données, etc.).
- **Annotations d'Ingress** : rate-limit (`nginx.ingress.kubernetes.io/limit-rps`),
  auth basic/OAuth, CORS, `canary` pour le déploiement progressif.
- **HA** : `replicaCount`, `PodDisruptionBudget`, anti-affinité.

## Mini-formation

1. Déployer une app et un Ingress :
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata: { name: demo }
   spec:
     ingressClassName: nginx
     rules:
       - host: demo.example.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service: { name: demo, port: { number: 80 } }
   ```
2. Tester :
   ```bash
   kubectl get ingress demo
   curl -H "Host: demo.example.com" http://<LB_IP>/
   ```
3. Inspecter la config générée :
   ```bash
   kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- cat /etc/nginx/nginx.conf
   ```

## Dashboard

Pas de dashboard intégré. Les **métriques Prometheus** sont activées
(`controller.metrics`) : dashboards Grafana communautaires « NGINX Ingress Controller »
disponibles sur grafana.com.
