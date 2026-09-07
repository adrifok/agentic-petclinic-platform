EKS cluster access and add-on upgrades

Implements PETPLAT-14 (kubectl access documentation) and PETPLAT-84
(add-on upgrade documentation).

Connecting kubectl

Every environment's Terraform output includes a ready-to-run command:

  terraform -chdir=terraform/environments/dev output -raw kubeconfig_command
  terraform -chdir=terraform/environments/prod output -raw kubeconfig_command

Each resolves to:

  aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
  aws eks update-kubeconfig --name petclinic-prod --region eu-central-1

Run it, then confirm access:

  kubectl get nodes
  kubectl get pods -n kube-system

Who has access today

The eks module grants cluster-admin to whichever IAM principal ran
terraform apply, via an aws_eks_access_entry + aws_eks_access_policy_association
pair (AmazonEKSClusterAdminPolicy, cluster-scoped). This is controlled by the
grant_caller_cluster_admin variable (default true) — set it to false in a
terraform.tfvars to stop granting standing admin to whoever applies, and
manage every grant explicitly via additional_access_entries instead.

If Terraform is applied via an assumed role (federated SSO, OIDC-federated
CI, etc.), the module converts the STS session ARN
(arn:aws:sts::<acct>:assumed-role/<role>/<session>) to the underlying IAM
role ARN before creating the access entry, since EKS access entries reject
session ARNs. No action needed — this happens automatically.

Adding another user or role

Add an entry to additional_access_entries in the environment's
terraform.tfvars (or main.tf module call) for the environment that needs it.
Entries default to read-only (AmazonEKSViewPolicy) and cluster-wide scope;
add namespaces to scope to specific namespaces instead:

  additional_access_entries = [
    {
      principal_arn     = "arn:aws:iam::<account>:role/some-team-role"
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
      kubernetes_groups = []
      namespaces        = ["petclinic-dev"]
    }
  ]

Available cluster-access-policy ARNs (AWS managed):
  arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
  arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy
  arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy
  arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy

Note: principal_arn must be the IAM user or role ARN (not the STS session
ARN — see the automatic conversion above, which only applies to the
Terraform-caller grant, not to entries you add here). Run terraform
plan/apply after editing.

To revoke access, remove the entry and apply — Terraform deletes the
access entry and its policy association.

Upgrading add-on versions (PETPLAT-84)

coredns, kube-proxy, vpc-cni, and aws-ebs-csi-driver each resolve to the
most recent version compatible with the cluster's Kubernetes version via
the aws_eks_addon_version data source, unless pinned explicitly.

To pin an exact version (e.g. before a planned upgrade, or to stop an
add-on from moving when cluster_version changes), set the corresponding
variable in terraform.tfvars:

  coredns_addon_version    = "v1.11.1-eksbuild.4"
  kube_proxy_addon_version = "v1.29.0-eksbuild.2"
  vpc_cni_addon_version    = "v1.18.1-eksbuild.1"
  ebs_csi_addon_version    = "v1.30.0-eksbuild.1"

List versions available for the cluster's Kubernetes version before
picking one:

  aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version 1.29 \
    --query 'addons[].addonVersions[].addonVersion' --region eu-central-1

Run terraform plan to review the change, then terraform apply. Add-ons use
resolve_conflicts_on_update = OVERWRITE, so an upgrade replaces any
manual changes made to the add-on's Kubernetes resources outside Terraform.
