# Vector — Runbook

> **Code** : `infrastructure/components/vector/` · **Version** : `vector` **0.59.0**
> **Namespace Flux** : `vector` · **Namespace pods** : `vector` · **Shard (prod)** : `shard-observability`
> Voir : [README du composant](../../infrastructure/components/vector/README.md)

## Rôle

Vector est l'**agent de collecte de logs** (DaemonSet par nœud). Il collecte les logs
des conteneurs (`kubernetes_logs`) et les envoie vers **Loki**. Une panne = plus de
logs collectés (silencieux côté Loki).

## Infos clés

| | |
|---|---|
| Namespace(s) | `vector` |
| Mode | `role: Agent` (DaemonSet) |
| Source / Sink | `kubernetes_logs` → Loki `http://loki.loki.svc.cluster.local:3100` |
| `tenant_id` | `fake` (multi-tenancy Loki) |
| Dépendances | Loki (aval) |

## Vérifications de santé

```bash
kubectl -n vector get pods
kubectl -n vector logs -l app.kubernetes.io/name=vector --tail=50
```

Signes de bonne santé : un pod Vector **par nœud** `Running`, logs sans erreur d'envoi
vers Loki (pas de `error` / `request failed`).

## Opérations courantes

- **Vérifier que les logs arrivent dans Loki** :
  ```bash
  kubectl -n loki port-forward svc/loki 3100:3100 &
  curl -s http://localhost:3100/loki/api/v1/labels
  ```
- **Voir les logs de l'agent** : `kubectl -n vector logs -l app.kubernetes.io/name=vector --tail=100`
- **Redémarrer l'agent sur un nœud** :
  `kubectl -n vector delete pod -l app.kubernetes.io/name=vector --field-selector spec.nodeName=<node>`
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n vector
  flux reconcile kustomization infra-controllers -n vector
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Aucun log dans Loki | Agent Vector down / sink Loki injoignable | Vérifier Vector puis Loki |
| Logs manquants sur un nœud | Pas de pod Vector sur ce nœud | Vérifier le DaemonSet / taints/tolérations |
| Erreurs d'envoi massives | Loki sous pression | Voir le runbook [loki](loki.md) |
| Forte conso mémoire | Volume de logs élevé | Ajouter buffers/limits, surveiller le DaemonSet |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/vector.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : logs frais visibles dans Loki/Grafana.

## Sauvegarde / restauration

Sans état (config dans le chart/Git). Restauration = re-déploiement.

## Métriques & alertes

Métriques `vector_*` (events traités, erreurs). Alerte : absence de pod Vector sur un
nœud, taux d'erreurs d'envoi élevé.
