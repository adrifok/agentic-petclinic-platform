Pod security and secret store scope (PET-10)

What is enforced

  petclinic-prod      PSA enforce/audit/warn = restricted (k8s/base/namespaces.yaml,
                      and managedNamespaceMetadata in k8s/argocd/applications/prod/
                      so a namespace ArgoCD creates gets the same labels)
  monitoring          enforce privileged (fluent-bit hostPath), warn/audit baseline
  tracing             enforce baseline, warn/audit restricted
  prod chart pods     hardening.enabled in helm-values/prod.yaml:
                      readOnlyRootFilesystem on every container, emptyDir /tmp,
                      automountServiceAccountToken: false
  ClusterSecretStore  spec.conditions: only petclinic-dev, petclinic-prod,
                      petclinic-db-bootstrap and monitoring can use it

Accepted gap: any ExternalSecret in petclinic-prod can still reference any
petclinic/prod/* secret, including the master rds-credentials. Narrowing that
needs a namespaced SecretStore with its own IAM role.

Before the first prod sync (PET-14)

  kubectl apply -f k8s/base/namespaces.yaml -f k8s/base/observability/namespaces.yaml && kubectl get ns petclinic-prod monitoring tracing --show-labels

First prod sync checks (dev was not used to validate)

  kubectl -n petclinic-prod get pods
      all Ready, none stuck on admission (kubectl -n petclinic-prod get events | grep -i forbidden)
  kubectl -n petclinic-prod logs deploy/<service> | grep -i "read-only file system"
      expect nothing, for every service
  genai chat answers (writes its vector store temp file to /tmp)
  ExternalSecrets synced: kubectl -n petclinic-prod get externalsecret
  Scope check: an ExternalSecret created in another namespace (for example
  default) must stay not Ready and create no Secret (kubectl describe shows
  the store rejecting the namespace; exact wording depends on the ESO version)

Rollback if a service breaks on the read-only filesystem: set
hardening.enabled: false in helm-values/prod.yaml, commit, and sync that app.
If PSA rejects a pod, the events show which field; fix the chart rather than
lowering the namespace label.
