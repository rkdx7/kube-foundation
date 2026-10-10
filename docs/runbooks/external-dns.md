# ExternalDNS — Runbook

> **Code** : `infrastructure/components/external-dns/` · **Version** : `external-dns` **1.23.0**
> **Namespace Flux** : `external-dns` · **Namespace pods** : `external-dns` · **Shard (prod)** : `shard-core`
> Voir : [README du composant](../../infrastructure/components/external-dns/README.md)

## Rôle

ExternalDNS **synchronise les enregistrements DNS** (ici AWS Route53) à partir des
hostnames déclarés par les `HTTPRoute`/`Service`. Une panne = plus de mise à jour des
DNS (nouveaux hostnames absents, anciens orphelins).

## Infos clés

| | |
|---|---|
| Namespace(s) | `external-dns` |
| Provider | `aws` (Route53) — `policy: sync`, sources `service` + `gateway-httproute` |
| Dépendances | credentials AWS (IRSA recommandé en prod) |

## Vérifications de santé

```bash
kubectl -n external-dns get pods
kubectl -n external-dns logs deploy/external-dns --tail=50
```

Signes de bonne santé : pod `Running`, logs sans erreur d'authentification AWS, et
entrées DNS présentes côté Route53 pour chaque hostname déclaré.

## Opérations courantes

- **Vérifier qu'un hostname est bien créé** : déclarer l'`HTTPRoute`, puis
  `kubectl -n external-dns logs deploy/external-dns | grep <hostname>`.
- **Forcer une resync** : relancer le pod
  `kubectl -n external-dns rollout restart deploy/external-dns`.
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n external-dns
  flux reconcile kustomization infra-controllers -n external-dns
  ```
- **Inspecter l'état** : `kubectl -n external-dns logs deploy/external-dns -f`.

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| Erreur `UnauthorizedOperation` dans les logs | Credentials AWS absents/insuffisants | Vérifier IRSA / rôle IAM, scope Route53 |
| Aucune entrée créée | Source non couverte ou hostname non déclaré | Vérifier `sources` et `spec.hostnames` |
| Entrées supprimées à tort | `policy: sync` + filtre trop large | Passer à `upsert-only` ou restreindre `domainFilters` |
| `txtPrefix`/ownership conflictuel | Deux instances gèrent le même domaine | Aligner `registry`/`txtPrefix` |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/external-dns.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider en staging (dry-run `--dry-run` ou `policy: upsert-only` temporairement).

## Sauvegarde / restauration

Pas d'état local (état = le DNS provider). Un `kubectl delete` de l'objet supprime
l'enregistrement (policy `sync`) ; restaurer = re-créer l'objet.

## Métriques & alertes

Métriques `external_dns_*` (`external_dns_registry_endpoints_total`,
`external_dns_controller_last_sync_timestamp`). Alerte : dernier sync trop ancien ou
erreurs d'API DNS répétées.
