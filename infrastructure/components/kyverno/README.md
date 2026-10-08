<p align="center">
  <img src="https://raw.githubusercontent.com/cncf/artwork/main/projects/kyverno/icon/color/kyverno-icon-color.svg" alt="Kyverno logo" width="160" />
</p>

# Kyverno

> **Site officiel** : https://kyverno.io/
> **Documentation** : https://kyverno.io/docs/
> **Chart Helm** : https://artifacthub.io/packages/helm/kyverno/kyverno

## À quoi ça sert ?

**Kyverno** est un moteur de **politiques Kubernetes** (policy-as-code) écrites en
YAML natif (pas de langage dédié comme Rego/OPA). Il agit comme un webhook d'admission
qui **valide, mute et génère** des ressources :

- **Validate** : bloquer/autoriser des déploiements (ex. images signées, labels requis).
- **Mutate** : modifier des ressources (ex. injecter des annotations, défauts).
- **Generate** : créer des ressources (ex. NetworkPolicy par namespace).
- **Cleanup** : supprimer des ressources orphelines.

C'est la brique « admission control / conformité » du cluster, en complément de Falco
(runtime) et Trivy (scan statique).

## Configuration appliquée (dans ce dépôt)

| Élément | Valeur |
|---|---|
| Chart / version | `kyverno` **3.9.1** (repo `https://kyverno.github.io/kyverno/`) |
| Namespace | `kyverno` |
| `installCRDs` | `true` |
| `admissionController.replicas` | `1` |

Fichier clé : `controllers/base/kyverno.yaml` — la `HelmRelease`.

## Configurations à considérer

- **`backgroundController`** : scan continu des ressources existantes (pas seulement à l'admission).
- **`cleanupController`** : nettoyage automatique.
- **`reportsController`** : génération de `PolicyReport` (audit).
- **Politiques** : `ClusterPolicy` pour la conformité (ex. « require-labels »,
  « disallow-latest-tag », « require-image-signature » via cosign).
- **`policyExceptions`** : exempter des workloads précis d'une politique.
- **`verifyImages`** : vérifier les signatures cosign/Notation des images.
- **Kyverno CLI** : tester les politiques en local avant de les appliquer.
- **HA** : augmenter `replicas`, activer la mise à l'échelle.

## Mini-formation

1. Créer une `ClusterPolicy` de validation :
   ```yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata: { name: require-labels }
   spec:
     validationFailureAction: Enforce
     rules:
       - name: check-team
         match:
           any: [ { resources: { kinds: [ Pod ] } } ]
         validate:
           message: "Le label 'team' est obligatoire"
           pattern:
             metadata:
               labels:
                 team: "?*"
   ```
2. Tester (un pod sans label doit être bloqué) :
   ```bash
   kubectl run nginx --image=nginx          # doit échouer
   kubectl run nginx --image=nginx --labels team=platform   # ok
   ```
3. Vérifier les rapports :
   ```bash
   kubectl get policyreports -A
   ```
4. (Local) `kyverno apply policies/ --resource pod.yaml`.

## Dashboard

Pas de dashboard intégré. Les **PolicyReports** sont consultables via `kubectl`, ou
avec l'UI optionnelle **Policy Reporter** (Kyverno). Dashboards Grafana communautaires
disponibles (métriques `kyverno_*`).
