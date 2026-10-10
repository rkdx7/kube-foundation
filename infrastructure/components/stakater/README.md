<p align="center">
  <img src="https://raw.githubusercontent.com/stakater/Reloader/master/assets/web/reloader.jpg" alt="Reloader logo" width="180" />
</p>

# Stakater Reloader

> **Runbook** : [docs/runbooks/stakater.md](../../../docs/runbooks/stakater.md)

> **Site officiel** : https://stakater.com/opensource/reloader
> **Documentation** : https://docs.stakater.com/reloader/
> **Chart Helm** : https://artifacthub.io/packages/helm/stakater/reloader

## À quoi ça sert ?

**Reloader** (de Stakater) est un **contrôleur Kubernetes** qui surveille les
**ConfigMaps** et les **Secrets** et déclenche automatiquement un **rolling upgrade**
(redémarrage progressif) des workloads qui les référencent.

Sans Reloader, un `Deployment` ne redémarre pas quand le contenu d'une ConfigMap ou
d'un Secret qu'il monte change : l'app tourne avec d'anciennes valeurs jusqu'au
prochain rollout manuel. Reloader comble ce trou en « notifiant » le workload et en
provoquant son redéploiement en douceur.

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `reloader` **2.2.18** (app v1.4.22, repo `https://stakater.github.io/stakater-charts`) |
| Namespace | `stakater` |
| `reloader.watchGlobally` | `true` (surveille toutes les namespaces) |

Fichier clé : `controllers/base/stakater.yaml` — la `HelmRelease` (`reloader`).

## Comment ça marche ?

Reloader utilise des **annotations** sur les workloads et/ou sur les ConfigMaps/Secrets :

- **Annoter un workload** : relier explicitement un `Deployment`/`StatefulSet`/
  `DaemonSet` aux ConfigMaps/Secrets qu'il consomme.
- **Annoter une ConfigMap/Secret** : demander le redémarrage de *tous* les workloads
  qui la/le référencent.
- **`auto`** : avec `watchGlobally=true`, Reloader détecte automatiquement les
  ConfigMaps/Secrets montés et redémarre les workloads concernés, sans annotation.

## Configurations à considérer

- **`reloader.watchGlobally`** : passer à `false` pour restreindre la surveillance à
  la namespace de Reloader (et y déployer une instance par namespace si besoin).
- **`reloader.ignoreSecrets` / `reloader.ignoreConfigMaps`** : exclure certains
  types (utile si un autre mécanisme gère déjà le redémarrage).
- **Annotations ciblées** : `reloader.stakater.com/auto`, `reloader.stakater.com/search`
  pour relier précisément un workload à une ConfigMap/Secret (en limitant la portée
  du redémarrage).
- **`reloader.deployment.securityContext`** : durcir le contexte de sécurité du
  contrôleur (runAsNonRoot, readOnlyRootFilesystem).
- **Métriques & logs** : activer la sortie métriques/opentel pour l'observabilité.

## Mini-formation

1. Annoter un `Deployment` pour le relier à une ConfigMap :
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: demo
     annotations:
       reloader.stakater.com/auto: "true"
   spec:
     template:
       spec:
         containers:
           - name: demo
             image: nginx
             envFrom:
               - configMapRef: { name: demo-config }
   ```
2. Modifier la ConfigMap et constater le rolling upgrade :
   ```bash
   kubectl edit configmap demo-config
   kubectl rollout status deployment/demo
   kubectl get pods -w
   ```
3. Vérifier l'état du contrôleur :
   ```bash
   kubectl -n stakater get pods
   kubectl -n stakater logs deploy/reloader-reloader --tail=50
   ```

## Dashboard

Pas de dashboard intégré. Reloader expose des **métriques Prometheus**
(`reloader_*`) sur `/metrics`, intégrables au monitoring de la plateforme.
