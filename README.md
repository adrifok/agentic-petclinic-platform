agentic-petclinic-platform

AWS platform for Spring Petclinic Microservices (8 Spring Boot services, one of them a GenAI service), built with Terraform, EKS, Helm and ArgoCD.

The app is the open source spring-petclinic-microservices project. The platform around it is mine, and I built it with Claude Code as a working partner. Every Terraform module, manifest and pipeline it wrote went through terraform plan or kubectl dry-run and a review before anything was applied.


How I worked with Claude Code

  MCP servers give the agent real context instead of guesses:
    terraform-mcp-server      Terraform registry docs and provider schemas
    aws-knowledge-mcp         AWS documentation
    aws-pricing-mcp-server    cost estimates before choosing a resource
    context7                  current library docs
    atlassian                 Jira tickets, so each branch and PR maps to a PET issue

  Six review agents, each with one job: terraform-reviewer, k8s-validator, pipeline-reviewer, security-auditor, cost-reviewer, doc-reviewer. The agent that writes the code is never the one that grades it.

  Skills for repeatable tasks: terraform-plan, terraform-apply, deploy-dev, deploy-prod, rollback, smoke-test, security-scan, logs.

  Hooks that run before every command, no matter what the model decides:
    block terraform destroy, including through the Terraform MCP server
    block dangerous rm commands
    block commits that contain secrets
    warn when apply runs without a plan
  The hooks have their own test suite: 122 cases in .claude/hooks/tests, run with run-hook-tests.sh.

  Rules per area (Terraform, Kubernetes, Helm, pipelines, docs) live in .claude/rules.


The platform

  Region       eu-central-1, two environments (dev and prod) with separate Terraform state in S3 and DynamoDB locking
  Network      VPC with public subnets only, no NAT gateway, to keep costs down
  Cluster      EKS with managed node groups and Karpenter for node scaling (Spot in dev, on-demand Graviton in prod)
  Images       ECR, one repo per service per environment, scan on push
  Database     RDS MySQL, db.t4g.micro single-AZ
  Secrets      AWS Secrets Manager, pulled into the cluster by External Secrets Operator
  Ingress      AWS Load Balancer Controller, TLS with ACM, DNS in Route 53
  Delivery     ARM64 images are built and scanned with Trivy in dev. update-image-tags.yml commits the new tag to Git and ArgoCD picks it up. promote-images.yml copies the exact same image (same digest) to the immutable prod repos over OIDC, with no AWS keys and no cluster access. Auto-sync in dev, manual sync in prod.
  Packaging    one generic Helm chart for all 8 services, values per service and per environment
  Security     default-deny NetworkPolicy in prod


Observability

  Prometheus and Alertmanager for metrics and alerting rules, Grafana with a dashboard per service, FluentBit and Loki for logs, Zipkin for distributed tracing across the 8 services.


Repository layout

  terraform/modules         vpc, eks, karpenter, ecr, rds, dns, secrets, github-oidc, observability
  terraform/environments    dev and prod root modules
  k8s/base                  namespaces, ingress, external secrets, Karpenter, network policies, observability, DB bootstrap
  k8s/argocd                ArgoCD install, projects, RBAC and applications per environment
  helm/petclinic-service    the shared chart
  helm-values               one file per service, plus dev.yaml and prod.yaml
  .github/workflows         promote-images.yml, update-image-tags.yml
  scripts                   state bootstrap, ECR login, image build, start and stop env, Helm validation
  docs                      technical spec, Helm guide, rollback runbook, Jira backlog
  docs/runbooks             EKS access, ECR build and push, network policies, pod security, prod bootstrap, RDS init
  .claude                   agents, skills, hooks, rules and settings


Trade-offs I chose on purpose

  Public subnets and no NAT gateway: cheaper for a portfolio project, but nodes get public IPs. In production the nodes would go to private subnets behind a NAT.

  Single-AZ RDS on the smallest instance, in both environments: fine for a demo, not for real traffic.


Costs

  EKS, RDS and the load balancer bill by the hour. scripts/stop-env.sh stops RDS and scales the nodes to zero when I'm not using the environment. The EKS control plane keeps running and billing (about 3.30 USD a day), so a long pause still needs terraform destroy.
