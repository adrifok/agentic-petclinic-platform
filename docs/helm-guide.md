Helm chart guide

Last updated: 2026-09-19

Purpose: how the generic Helm chart at helm/petclinic-service/ is put
together, and how to deploy, add, or change a service with it. Implements
PETPLAT-111. See docs/technical-spec.md#helm-charts for the underlying
architecture decision (ADR-0007) and the full field reference.

Chart structure

One chart, helm/petclinic-service/, is shared by all 8 services. Nothing in
the chart itself names a specific service — every difference (ports, env
vars, probes, secrets, init containers) comes from values.

  helm/petclinic-service/
    Chart.yaml              name: petclinic-service, version: 0.1.0
    values.yaml              chart defaults — these match dev exactly
                              (1 replica, no HPA, no PDB)
    templates/
      deployment.yaml        Deployment: probes, resources, env, init containers
      service.yaml            ClusterIP Service
      configmap.yaml           non-secret config
      serviceaccount.yaml      ServiceAccount
      hpa.yaml                 HPA — only renders if autoscaling is enabled
      pdb.yaml                 PDB — only renders if podDisruptionBudget is enabled
      _helpers.tpl             label/name helpers

The release name IS the service name (see "Deploy a service" below), so the
chart never needs a separate nameOverride — every template just uses
.Release.Name for the Deployment/Service/ConfigMap/ServiceAccount name.

Values hierarchy

Three layers merge at install time, each one able to override the last:

  1. helm/petclinic-service/values.yaml   chart defaults (= dev's settings)
  2. helm-values/{service}.yaml            per-service: image repo suffix,
                                            port, configMap data, secretEnv,
                                            initContainers, component label
  3. helm-values/{dev,prod}.yaml           per-environment: image registry
                                            (petclinic-dev vs petclinic-prod),
                                            pullPolicy, RDS endpoint, and —
                                            for prod only — a perService map
                                            keyed by service name overriding
                                            replicaCount / autoscaling / PDB

The perService map in helm-values/prod.yaml exists because replica counts,
HPA targets, and PDB settings are NOT the same across all 8 services in
prod (see docs/technical-spec.md#kubernetes-overlays) — a single blanket
"replicas: 2" in prod.yaml would be wrong for genai-service and
admin-server, which stay at 1. dev.yaml sets no perService, so every
service just falls through to the chart defaults (replicas=1, no HPA, no
PDB), matching k8s/overlays/dev exactly with zero per-service overrides
needed.

What the chart does NOT manage: Namespaces and ExternalSecret CRs
(k8s/base/namespaces.yaml, k8s/base/external-secrets/) stay outside Helm,
applied directly with kubectl — same as today. Apply the namespace and the
relevant ExternalSecret CRs before installing a release that depends on
them (e.g. rds-credentials must exist before customers-service/
visits-service/vets-service will start).

Deploy a service manually with Helm

  helm upgrade --install customers-service helm/petclinic-service/ \
    -n petclinic-dev \
    -f helm-values/customers-service.yaml \
    -f helm-values/dev.yaml \
    --set image.tag=v1.0.0

The release name (customers-service here) must match the service's
helm-values file name — the chart derives every resource name from it.
Swap -f helm-values/dev.yaml for -f helm-values/prod.yaml and the
namespace to petclinic-prod to deploy to prod instead. image.tag is set at
install time, not baked into the values files, matching the CI convention
of commit-SHA tags (docs/technical-spec.md#cicd-pipeline).

To check what would be deployed without touching the cluster:

  helm template customers-service helm/petclinic-service/ \
    -n petclinic-dev \
    -f helm-values/customers-service.yaml -f helm-values/dev.yaml \
    --set image.tag=v1.0.0

Run scripts/validate-helm.sh any time the chart or values change — it runs
helm lint, helm template, and kubectl apply --dry-run=client across all 8
services and both environments in one pass (PETPLAT-110).

Add a new service

1. Create helm-values/{new-service}.yaml. Set at minimum: image.repository
   (the ECR repo suffix, e.g. new-service), service.port, and configMap
   (SPRING_PROFILES_ACTIVE, CONFIG_SERVER_URL). Add initContainers if the
   service depends on others being up first (config-server and
   discovery-server, at minimum, unless this is config-server itself). Add
   secretEnv if it needs a secret (match the ExternalSecret's target name
   and key exactly — see k8s/base/external-secrets/).
2. If the new service needs different replicas/HPA/PDB in prod than the
   chart default (1 replica, no HPA, no PDB), add an entry for it under
   perService in helm-values/prod.yaml.
3. Add the matching ExternalSecret CR under k8s/base/external-secrets/ if
   the service needs a secret, and an ECR repository in
   terraform/modules/ecr (see terraform/environments/{dev,prod}).
4. Add an ArgoCD Application CRD per environment under
   k8s/argocd/applications/{dev,prod}/ pointing at helm/petclinic-service/
   with the two -f value files, same pattern as the other 8 services
   (E-17 — see docs/jira-backlog.md).
5. Run scripts/validate-helm.sh and confirm the new service renders
   cleanly in both environments before committing.

Change resources, replicas, or environment variables

Resources (CPU/memory requests+limits): set resources in the service's
helm-values file if it needs to differ from the chart default
(100m/128Mi request, 500m/512Mi limit) — see helm-values/api-gateway.yaml
for an example (200m/1000m CPU, since it fronts all incoming traffic).

Replicas: dev is always 1 (chart default, not overridden anywhere). For
prod, edit that service's replicaCount under perService in
helm-values/prod.yaml — never edit replicaCount at the top level of
prod.yaml, since that would apply to every service.

Environment variables: non-secret vars go in the service's configMap map
in helm-values/{service}.yaml. Secret-backed vars go in that file's
secretEnv list (name, secretName, secretKey) — the secret itself must
already exist as a K8s Secret (synced by an ExternalSecret CR) with that
exact name and key. An env-specific value that's the same across all
services in one environment (like the RDS endpoint) belongs in
helm-values/{dev,prod}.yaml instead — see datasource.url and how
customers-service/visits-service/vets-service pick it up via
datasource.enabled: true.
