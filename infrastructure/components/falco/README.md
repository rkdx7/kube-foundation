<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/falco/icon/color/falco-icon-color.svg" alt="Falco logo" width="160" />
</p>

# Falco

> **Site officiel** : https://falco.org/
> **Documentation** : https://falco.org/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/falcosecurity/falco

## À quoi ça sert ?

Falco est l'outil de **détection d'intrusion et d'anomalies à l'exécution** (runtime
security) de référence sur Kubernetes. Grâce à eBPF/kernel module, il surveille les
**appels système** et déclenche des **alertes** sur les comportements suspects :
exécution d'un shell dans un conteneur, écriture dans `/etc`, accès à des fichiers
sensibles, connexions réseau inattendues, etc.

Il détecte les menaces au moment où elles se produisent (posture *runtime*), en
complément des scans statiques (Trivy) et des politiques d'admission (Kyverno).

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `falco` **9.2.0** (repo `https://falcosecurity.github.io/charts`) |
| Namespace | `falco` |
| `tty` | `true` (sortie lisible des événements) |
| `falcosidekick` | `false` (forwarder d'alertes désactivé) |

Fichier clé : `controllers/base/falco.yaml` — la `HelmRelease`.

## Configurations à considérer

- **`falcosidekick.enabled: true`** : router les alertes vers Slack, webhook, Loki,
  Teams, email… (fortement recommandé en prod, sans quoi les alertes ne sortent pas du pod).
- **Driver** : choisir entre `modern-bpf` (recommandé), `ebpf` ou kernel module selon
  le kernel des nœuds.
- **Règles custom** : ajouter des règles Falco (`falco_rules.custom.yaml`) pour vos cas métier.
- **Plugins** : `k8saudit` pour ingérer les **audit logs** de l'API server Kubernetes
  (détection d'événements au niveau K8s, pas seulement syscalls).
- **Sortie vers Loki** : pousser les événements Falco dans Loki pour corréler avec les logs.
- **Priority / throttle** : ajuster la criticité minimale et le rate-limit.

## Mini-formation

1. Installer (déjà fait via Flux) :
   ```bash
   helm repo add falcosecurity https://falcosecurity.github.io/charts
   helm install falco falcosecurity/falco -n falco --create-namespace
   ```
2. Vérifier que Falco tourne :
   ```bash
   kubectl get pods -n falco
   kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
   ```
3. Générer un événement de test (exécuter un shell dans un pod) :
   ```bash
   kubectl run -it --rm debug --image=alpine -- sh   # puis taper des commandes
   ```
   → Falco logue une alerte type « A shell was spawned in a container ».

## Dashboard

Pas de dashboard intégré à Falco. Options :
- **Falcosidekick UI** (optionnel) : interface web pour visualiser les événements.
- **Grafana** : dashboards communautaires « Falco » (métriques `falco_*`), et
  corrélation des alertes dans **Loki**.
