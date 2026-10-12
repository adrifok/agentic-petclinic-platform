Prod cluster bootstrap (PET-14)

Order for petclinic-prod-eks after terraform apply. App sync is PET-15.
Run from the repo root. genai-service is not run in prod (no OpenAI account,
prod.yaml sets it to 0 replicas). Alerts are skipped: Alertmanager gets a
placeholder Slack webhook so it starts, and notifications just fail.

  1. Kubeconfig (prod context only, never the dev one):

       aws eks update-kubeconfig --name "$(terraform -chdir=terraform/environments/prod output -raw cluster_name)" --region eu-central-1 --alias petclinic-prod && kubectl config current-context

  2. Namespaces with PSA labels and the default deny, before anything else:

       kubectl apply -f k8s/base/namespaces.yaml -l environment=prod && kubectl apply -f k8s/base/network-policies/default-deny-prod.yaml

     (-l environment=prod keeps petclinic-dev out of the prod cluster.)

  3. LB controller and ESO (ESO script also applies the ClusterSecretStore):

       ./scripts/install-lb-controller.sh prod && ./scripts/install-external-secrets.sh prod

  4. Karpenter controller (chart brings the CRDs), then the prod
     NodePool/EC2NodeClass. replicas=1 because the t4g.small nodes are
     memory-bound:

       cd terraform/environments/prod && helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.14.1 --namespace kube-system --set settings.clusterName="$(terraform output -raw cluster_name)" --set settings.interruptionQueue="$(terraform output -raw karpenter_queue_name)" --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform output -raw karpenter_role_arn)" --set replicas=1 --set controller.resources.requests.cpu=100m --set controller.resources.requests.memory=256Mi --set controller.resources.limits.memory=512Mi --wait && cd - && kubectl apply -f k8s/base/karpenter/nodepool-prod.yaml

  5. DB bootstrap: follow docs/runbooks/rds-database-init.md, "Prod: one-time
     bootstrap" (refill <RDS_ENDPOINT> in helm-values/prod.yaml and the
     bootstrap kustomization, commit prod.yaml, run the job, delete its
     namespace, apply db-credentials-prod.yaml).

  6. Observability secrets (values never in Git), then the stack rendered
     for prod:

       aws secretsmanager create-secret --region eu-central-1 --name petclinic/prod/grafana-admin --secret-string "{\"username\":\"admin\",\"password\":\"$(openssl rand -base64 24)\"}"

     (On a re-run the secrets already exist: create-secret fails, which is
     fine; use put-secret-value only to change a value.) Read the Grafana
     password back when needed:

       aws secretsmanager get-secret-value --region eu-central-1 --secret-id petclinic/prod/grafana-admin --query SecretString --output text

       aws secretsmanager create-secret --region eu-central-1 --name petclinic/prod/alertmanager-slack --secret-string '{"webhook_url":"https://hooks.slack.com/services/disabled/disabled/disabled"}'

       kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.94.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml

       kubectl kustomize k8s/base/observability | sed -e 's/petclinic-dev/petclinic-prod/g' -e 's|petclinic/dev/|petclinic/prod/|g' | kubectl apply -f -

     The genai-service scrape target stays down (0 replicas), so ServiceDown
     fires for it. Silence it once Alertmanager is up:

       kubectl -n monitoring exec deploy/alertmanager -- amtool silence add --alertmanager.url=http://localhost:9093 --duration=720h --comment="genai not run in prod" job=genai-service

  7. ArgoCD, port-forward only (no Ingress for it):

       kubectl apply -f k8s/argocd/install/namespace.yaml && kubectl apply -n argocd --server-side --force-conflicts -f k8s/argocd/install/install.yaml && kubectl apply -f k8s/argocd/argocd-rbac-cm.yaml

       kubectl -n argocd port-forward svc/argocd-server 8443:443

     Log in with the initial password, change it in the UI, then delete the
     initial secret:

       kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

       kubectl -n argocd delete secret argocd-initial-admin-secret

  8. AppProject, then the prod Applications only (manual sync, nothing
     deploys yet):

       kubectl apply -f k8s/argocd/projects/petclinic-prod.yaml && kubectl apply -n argocd -f k8s/argocd/applications/prod/

  Moved to the start of PET-15 (no ALB sitting in front of nothing): prod
  Ingress and DNS alias. Refill and apply ingress-prod.yaml (command in its
  header), then set dns_create_alb_record = true, dns_alb_dns_name and
  dns_alb_zone_id (Z215JYRZR1TBD5 for eu-central-1 ALBs) in the prod
  terraform.tfvars, plan to plan.out and apply.

Checks: kubectl get ns petclinic-prod --show-labels shows restricted;
kubectl get clustersecretstore aws-secrets-manager is Ready; kubectl -n
monitoring get pods all Running; argocd apps listed as OutOfSync (expected
before PET-15).
