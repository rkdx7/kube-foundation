# Falco — Runbook

> **Code** : `infrastructure/components/falco/` · **Version** : `falco` **9.2.0**
> **Namespace Flux** : `falco` · **Namespace pods** : `falco` · **Shard (prod)** : `shard-security`
> Voir : [README du composant](../../infrastructure/components/falco/README.md)

## Rôle

Falco est la **détection runtime** (intrusion/anomalies) via eBPF/syscalls. Il ne
bloque rien, il **alerte**. Une panne = plus de détection (silencieuse).

## Infos clés

| | |
|---|---|
| Namespace(s) | `falco` |
| Driver | eBPF / kernel module (selon nœuds) |
| Forwarder | `falcosidekick` **désactivé** (⚠️ les alertes restent dans les logs du pod) |

## Vérifications de santé

```bash
kubectl -n falco get pods
kubectl -n falco logs -l app.kubernetes.io/name=falco --tail=50
```

Signes de bonne santé : un pod Falco **par nœud** (DaemonSet) `Running`, logs sans
erreur de chargement du driver.

## Opérations courantes

- **Voir les alertes** : `kubectl -n falco logs -l app.kubernetes.io/name=falco --tail=100`
- **Tester la détection** (générer un shell dans un conteneur) :
  ```bash
  kubectl run -it --rm debug --image=alpine -- sh
  # → Falco doit logger "A shell was spawned in a container"
  ```
- **Redémarrer l'agent sur un nœud** :
  `kubectl -n falco delete pod -l app.kubernetes.io/name=falco --field-selector spec.nodeName=<node>`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n falco
  flux reconcile kustomization infra-controllers -n falco
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Pod en `CrashLoopBackOff` | Driver eBPF incompatible avec le kernel | Passer à `modern-bpf`/`ebpf`, vérifier logs |
| Aucune alerte visible | `falcosidekick` désactivé (sortie pod uniquement) | Activer `falcosidekick` + destination (Slack/Loki) |
| Forte conso CPU | Règles trop larges / driver kernel module | Revoir les règles, `priority`, throttle |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/falco.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : relancer le test « shell dans un conteneur ».

## Sauvegarde / restauration

Sans état (règles dans le chart/Git). Restauration = re-déploiement.

## Métriques & alertes

Métriques `falco_*`. Alerte critique : absence de pod Falco sur un nœud. Recommandé :
router les événements vers Loki/Slack via Falcosidekick.
