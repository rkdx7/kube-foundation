# OpenBao — Runbook

> **Code** : `infrastructure/components/openbao/` · **Version** : `openbao` **0.30.3**
> **Namespace Flux** : `openbao` · **Namespace pods** : `openbao` · **Shard (prod)** : `shard-security`
> Voir : [README du composant](../../infrastructure/components/openbao/README.md)

## Rôle

OpenBao (fork Linux Foundation de Vault) est la **source de vérité des secrets**,
consommée par ESO. Mode **HA Raft** (3 réplicas). Doit être **initialisé puis
déscellé** avant usage.

## Infos clés

| | |
|---|---|
| Namespace(s) | `openbao` |
| Mode | HA Raft, `replicas: 3`, `setNodeId: true`, dataStorage 10Gi |
| Dépendances | aucune (mais ESO, ci-dessus, en dépend) |
| UI | activée (`ui.enabled: true`), HTTPRoute `openbao.<dom>` |

## Vérifications de santé

```bash
kubectl -n openbao get pods
kubectl -n openbao get sts openbao
kubectl -n openbao exec openbao-0 -- bao status
```

Signes de bonne santé : 3 pods `Running`, `bao status` → `Sealed: false` et leader
élu. **`Sealed: true` est critique** : ESO ne peut plus lire les secrets.

## Opérations courantes

- **Voir l'état (scellé / leader)** : `kubectl -n openbao exec openbao-0 -- bao status`
- **Désceller** (après un redémarrage) :
  ```bash
  kubectl -n openbao exec openbao-0 -- bao operator unseal <key1>
  kubectl -n openbao exec openbao-0 -- bao operator unseal <key2>
  ```
  (à répéter sur les autres réplicas si besoin, threshold = 2 sur 3 shares)
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n openbao
  flux reconcile kustomization infra-controllers -n openbao
  flux reconcile kustomization infra-configs -n openbao
  ```

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `Sealed: true` après reboot | OpenBao requiert un unseal manuel | `bao operator unseal` (ou activer auto-unseal) |
| ESO en échec `connection refused` | Service actif injoignable / pods down | `kubectl -n openbao get pods,svc` |
| Pods en boucle (raft) | Split-brain ou storage Raft corrompu | Inspecter logs `openbao-0`, vérifier `dataStorage` |
| `Permission denied` côté ESO | Rôle `eso` / politique manquant | Re-créer le rôle Kubernetes + politique (voir README) |
| UI inaccessible | HTTPRoute / Gateway en échec | `kubectl -n openbao get httproute`, vérifier kgateway |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/openbao.yaml`.
2. **Avant tout upgrade**, faire un snapshot Raft et vérifier l'état HA :
   `kubectl -n openbao exec openbao-0 -- bao operator raft snapshot save /tmp/raft.snap`
3. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
4. Valider : `bao status` sur chaque réplica après upgrade.

## Sauvegarde / restauration

- **Snapshot Raft** (état complet) :
  ```bash
  kubectl -n openbao exec openbao-0 -- bao operator raft snapshot save /tmp/raft.snap
  kubectl -n openbao cp openbao-0:/tmp/raft.snap ./raft.snap
  ```
- **Restaurer** : `bao operator raft snapshot restore <file>` sur un réplica arrêté.
- Les **clés d'unseal** et le **token root** doivent être stockés hors cluster
  (gestionnaire de secrets), sinon impossibilité de désceller après un incident.

## Métriques & alertes

Métriques `bao_*` (état scellé `bao_core_unsealed`, leader). Alerte critique :
`Sealed: true`, réplicas HA < 3, échec d'écriture Raft.
