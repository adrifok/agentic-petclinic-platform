Network policies (PET-9)

Enforcement comes from the VPC CNI network policy agent (vpc-cni add-on,
enableNetworkPolicy = "true", terraform/modules/eks). Policies:

  helm/petclinic-service/templates/networkpolicy.yaml
      one allow-list per service, ingress on its service port only.
      Sources are set per service in helm-values/{service}.yaml.
      Egress: DNS, same namespace, tracing 9411, RDS 3306 (DB services,
      VPC CIDR only), 443 out only for config-server and genai-service
      (networkPolicy.egressInternet).
  k8s/base/network-policies/default-deny-prod.yaml
      namespace-wide deny for anything without its own policy.

Who may call whom (ingress)

  config-server, discovery-server, admin-server   any pod in the namespace
  api-gateway        ALB (VPC CIDR, target-type ip), admin-server, monitoring
  customers-service  api-gateway, visits-service (init wait), genai-service, admin-server, monitoring
  visits-service     api-gateway, admin-server, monitoring
  vets-service       api-gateway, genai-service, admin-server, monitoring
  genai-service      api-gateway, admin-server, monitoring

Accepted risk: the ALB rule is an ipBlock for the whole VPC CIDR, so any node
or pod in the VPC can reach api-gateway:8080. Narrowing it needs security
groups for pods.

Kubelet probes come from the node. Kubernetes NetworkPolicy semantics allow
node-to-pod traffic, but this is not yet verified on this cluster; the "all
pods Ready" check below proves it.

Enabled only in prod (helm-values/prod.yaml networkPolicy.enabled). Dev
renders are unchanged.

Gate: apply the default deny before the first prod sync (PET-14). It is not
managed by ArgoCD, so skipping this step leaves prod without it:

  kubectl apply -f k8s/base/network-policies/default-deny-prod.yaml

First prod sync checks (PET-14). Dev was not used to validate, so do these
before go-live:

  All pods Ready, including init-container waits (visits waits on customers).
  ALB -> api-gateway: the site loads through the Ingress hostname.
  Owners, vets and visits pages load (gateway -> domain services).
  genai chat answers (genai -> customers, vets, OpenAI on 443).
  Spring Boot Admin shows all instances UP (admin-server -> actuator).
  Prometheus targets UP for the 5 scraped services (monitoring -> pods).
  Zipkin shows traces (pods -> tracing 9411).
  Denied path: from api-gateway, config-server is reachable but RDS is not:
    kubectl -n petclinic-prod exec deploy/api-gateway -- sh -c 'timeout 3 bash -c "</dev/tcp/<rds_endpoint>/3306" && echo OPEN || echo BLOCKED'

Kill switch if a missing rule breaks traffic: set networkPolicy.enabled: false
in helm-values/prod.yaml, commit, and sync with prune (prod apps do not prune
by default, a plain sync leaves the old policy in place):

  argocd app sync <service>-prod --prune

The default-deny still applies to pods without a policy, so also remove it if
needed (run it yourself, the Claude hook blocks deletes in petclinic-prod):

  kubectl -n petclinic-prod delete networkpolicy default-deny

Known gap: k8s/base/observability/prometheus.yaml scrape targets are
hardcoded to petclinic-dev; prod needs its own variant.
