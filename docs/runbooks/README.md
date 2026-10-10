# Runbooks

Runbooks **opérationnels** de la plateforme : un par composant. Contrairement aux
`README.md` des composants (qui documentent *ce que fait* le composant et *comment il
est configuré*), un runbook répond à *« que faire maintenant ? »* — vérifier l'état,
débloquer, réparer, mettre à jour, sauvegarder/restaurer.

## Sommaire

### Domaine « core » — réseau, ingress & TLS (`shard-core`)
- [cilium](cilium.md) — CNI / eBPF / Hubble
- [kube-vip](kube-vip.md) — LoadBalancer VIP (on-prem)
- [kgateway](kgateway.md) — Gateway API / Envoy (entrée nord-sud)
- [cert-manager](cert-manager.md) — certificats TLS (ACME)
- [external-dns](external-dns.md) — synchronisation DNS

### Domaine « security » — secrets, politique & sécurité (`shard-security`)
- [external-secrets](external-secrets.md) — External Secrets Operator (ESO)
- [openbao](openbao.md) — gestionnaire de secrets (fork Vault, HA)
- [kyverno](kyverno.md) — politiques d'admission
- [falco](falco.md) — détection runtime
- [trivy](trivy.md) — scan de vulnérabilités / conformité

### Domaine « observability » — métriques, logs & traces (`shard-observability`)
- [monitoring](monitoring.md) — Prometheus / Grafana / Alertmanager + metrics-server
- [loki](loki.md) — agrégation de logs
- [tempo](tempo.md) — backend de traces
- [opentelemetry](opentelemetry.md) — collector (routeur de télémétrie)
- [vector](vector.md) — agent de collecte de logs

### Domaine « platform » — mesh, autoscaling, stockage, backup & apps (`shard-platform`)
- [istio](istio.md) — service mesh
- [keda](keda.md) — autoscaling piloté par événements
- [stakater](stakater.md) — Reloader (rechargement ConfigMap/Secret)
- [rook](rook.md) — stockage Ceph (block + S3)
- [velero](velero.md) — sauvegarde / restauration
- [frontend](frontend.md) — application de démonstration (Go)
- [backend](backend.md) — redis + memcached

## Conventions

Chaque runbook suit le même plan :

1. **Rôle** — ce que fait le composant, en une phrase.
2. **Infos clés** — namespace(s), shard, version, dépendances.
3. **Vérifications de santé** — commandes pour confirmer que « tout va bien ».
4. **Opérations courantes** — redémarrer, lire les logs, forcer une réconciliation.
5. **Incidents fréquents** — tableau symptôme → cause probable → action.
6. **Mise à jour (upgrade)** — procédure de bump de version.
7. **Sauvegarde / restauration** — le cas échéant.
8. **Métriques & alertes** — ce qu'il faut surveiller.

> **Rappel Flux** : chaque composant est réconcilié depuis un artefact OCI. Le
> namespace Flux d'un composant héberge un `OCIRepository` + une (ou deux)
> `Kustomization` (`infra-controllers`, `infra-configs`) ; les pods, eux, peuvent
> tourner dans un autre namespace (`kube-system`, `istio-system`, `rook-ceph`,
> `kgateway-system`). La colonne « Namespace » distingue toujours les deux.

## Template (pour créer un nouveau runbook)

```markdown
# <composant> — Runbook

> **Code** : `infrastructure/components/<composant>/` · **Version** : `<chart> <version>`
> **Namespace Flux** : `<ns>` · **Namespace pods** : `<ns>` · **Shard (prod)** : `<shard>`

## Rôle
...

## Infos clés
| | |
|---|---|
| Namespace(s) | ... |
| Dépendances | ... |

## Vérifications de santé
```bash
kubectl -n <ns> get pods
flux get helmrelease -n <ns>
```

## Opérations courantes
...

## Incidents fréquents
| Symptôme | Cause probable | Action |
|---|---|---|
| ... | ... | ... |

## Mise à jour (upgrade)
...

## Sauvegarde / restauration
...

## Métriques & alertes
...
```

## Comment mettre à jour ces runbooks

1. **Lors d'un changement de config** : si tu modifies un `controllers/base/*.yaml`
   (version, valeurs), un `configs/**`, ou un `ResourceSet` (`fleet/tenants/*.yaml`),
   mets à jour les sections « Infos clés », « Vérifications de santé » et
   « Mise à jour » du runbook concerné, **dans le même commit**.
2. **Lors d'un bump de version** : reporte la version dans le tableau « Infos clés »
   du runbook **et** dans [`docs/versions.md`](../versions.md).
3. **Lors d'un incident** : si tu découvres une panne non documentée et sa résolution,
   ajoute une ligne au tableau « Incidents fréquents ». C'est ce qui fait la valeur du
   runbook dans le temps.
4. **Lors de l'ajout/suppression d'un composant** : crée/supprime le fichier, et mets
   à jour le sommaire ci-dessus.

## À prendre en compte (garde-fous)

- **Ne duplique pas la config** : le runbook décrit *les gestes*, pas la valeur des
  `values` (qui reste dans `controllers/base/*.yaml`, source de vérité). Si les deux
  divergent, la config gagne.
- **Environment-aware** : `staging` n'est pas shardé ; `prod` l'est (4 shards). Les
  commandes `flux get ... -A -l sharding.fluxcd.io/key=...` ne s'appliquent qu'en prod.
- **Secrets** : aucune commande de runbook ne doit exposer de secret en clair
  (utiliser `kubectl get secret ... -o jsonpath` avec `base64 -d`, jamais de `-o yaml`
  sur un secret complet dans un doc).
- **Vérifie les commandes** : un runbook périmé est dangereux. Teste les commandes en
  `staging` avant de les documenter pour `prod`.
