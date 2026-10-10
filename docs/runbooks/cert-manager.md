# cert-manager — Runbook

> **Code** : `infrastructure/components/cert-manager/` · **Version** : `cert-manager` **v1.21.2**
> **Namespace Flux** : `cert-manager` · **Namespace pods** : `cert-manager` · **Shard (prod)** : `shard-core`
> Voir : [README du composant](../../infrastructure/components/cert-manager/README.md)

## Rôle

cert-manager automatise l'émission et le **renouvellement** des certificats TLS
(ACME Let's Encrypt, via HTTP-01 sur la Gateway kgateway). Une panne à l'approche de
l'expiration = services en TLS cassé.

## Infos clés

| | |
|---|---|
| Namespace(s) | `cert-manager` |
| Dépendances | kgateway (solver HTTP-01 `gatewayHTTPRoute`) |
| ClusterIssuers | `letsencrypt-staging`, `letsencrypt-prod` (par environnement) |
| Email ACME | `letsencrypt@example.com` (⚠️ à remplacer) |

## Vérifications de santé

```bash
kubectl -n cert-manager get pods
kubectl get clusterissuer
kubectl get certificate -A
kubectl get certificaterequest,order,challenge -A
```

Signes de bonne santé : `ClusterIssuer` `Ready=True`, tous les `Certificate` `Ready=True`
(surtout `kgateway-tls`), aucun `challenge` bloqué en `Pending`.

## Opérations courantes

- **Voir l'état d'un certificat** : `kubectl describe certificate <name> -n <ns>`
  (les **Events** indiquent la cause d'échec).
- **Forcer un renouvellement** :
  ```bash
  kubectl delete secret <secretName> -n <ns>   # supprime le secret → ré-émission
  # ou : cmctl renew <name> -n <ns> (plugin cert-manager)
  ```
- **Forcer la réconciliation Flux** :
  ```bash
  flux reconcile source oci infra -n cert-manager
  flux reconcile kustomization infra-controllers -n cert-manager
  flux reconcile kustomization infra-configs -n cert-manager
  ```
- **Vérifier les dates d'expiration** : `kubectl get certificate -A -o wide` (colonne `Ready`) ou `cmctl status certificate <name>`.

## Incidents fréquents

| Symptôme | Cause probable | Action |
|---|---|---|
| `Certificate` `Ready=False` + `Order` en échec | Challenge HTTP-01 non résolu | `kubectl describe challenge -A`, vérifier la Gateway et le DNS |
| Challenge `Pending` indéfiniment | Le solver `gatewayHTTPRoute` ne joint pas la Gateway | Vérifier que la Gateway `kgateway` est `Programmed` |
| « rate limit » Let's Encrypt | Trop de demandes / domaine invalide | `kubectl describe order`, attendre ou passer en staging |
| Email ACME faux | `letsencrypt@example.com` | Remplacer par une vraie adresse dans les `ClusterIssuer` |
| Renouvellement ne se déclenche pas | `renewBefore`/`duration` mal réglés | Ajuster dans le `Certificate` (défaut 30 j) |

## Mise à jour (upgrade)

1. Bumper `version:` dans `controllers/base/cert-manager.yaml`.
2. Mettre à jour [`docs/versions.md`](../versions.md) et ce runbook.
3. Valider : `kubectl get clusterissuer` puis un renouvellement de test.

## Sauvegarde / restauration

Les certificats sont des `Secret` régénérés automatiquement (pas de backup nécessaire).
Backup éventuel de la clé de compte ACME (`letsencrypt-*-account-key`) si tu veux
éviter de recréer un compte.

## Métriques & alertes

Métriques `certmanager_*` (`certmanager_certificate_expiration_timestamp_seconds`).
Alerte critique : certificat proche de l'expiration (moins de 14 j) ou non `Ready`.
