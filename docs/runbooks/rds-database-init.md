RDS database initialization strategy

Implements PETPLAT-24. See docs/technical-spec.md#rds-database.

Strategy: Spring Boot auto-init, not manual scripts

The rds module (PETPLAT-22) provisions one RDS MySQL instance with a single
empty database, named petclinic (aws_db_instance.db_name). It does not run
any schema SQL — the application repo (spring-petclinic-microservices,
read-only from this repo) owns that.

Each of the three database-backed services ships its own schema.sql under
src/main/resources/db/mysql/ in the application repo, starting with:

  CREATE DATABASE IF NOT EXISTS petclinic;
  USE petclinic;

With spring.sql.init.mode=always and the mysql Spring profile active, each
service runs its own schema.sql automatically on startup. No init container
or manual mysql client step is needed — that's the "implement" half of this
story; the rest is getting the startup order right.

Why auto-init and not a manual/init-container approach: the three schemas
have a cross-service foreign key (visits.pet_id -> pets.id, and pets lives
in the customers schema), so whichever mechanism runs the SQL has to run it
in a specific order. Kubernetes deployment ordering already gives us that
order for free (see below), so a separate init-container/job would just be
duplicating logic Spring already provides via sql.init.mode.

Schema initialization order (must be respected)

  1. customers-service  — creates types, owners, pets
  2. vets-service        — creates vets, specialties, vet_specialties (independent of the others)
  3. visits-service      — creates visits, which has FOREIGN KEY (pet_id) REFERENCES pets(id)

visits-service will fail to initialize if it starts before customers-service
has created the pets table. This is enforced at the Kubernetes layer, not
by Terraform: customers-service's Deployment must roll out (readiness probe
passing) before visits-service starts. vets-service has no dependency and
can start any time after the database is reachable. Config Server and
Discovery Server still come first for all services per the platform-wide
startup order in CLAUDE.md.

Tables (7 total, for reference — full column list in docs/technical-spec.md#rds-database)

  customers-service: types, owners, pets
  vets-service:       vets, specialties, vet_specialties
  visits-service:     visits

Connection string format

  jdbc:mysql://{rds-endpoint}:3306/petclinic

{rds-endpoint} is the rds module's endpoint output (hostname only, no
port) — for dev:

  terraform -chdir=terraform/environments/dev output -raw rds_endpoint

Example:

  jdbc:mysql://petclinic-dev-mysql.abc123.eu-central-1.rds.amazonaws.com:3306/petclinic

K8s ConfigMaps for each database-backed service should set SPRING_DATASOURCE_URL
to this format, with username/password injected from the rds-credentials
ExternalSecret (PETPLAT-35) rather than hardcoded — see
docs/technical-spec.md#secrets-management.

Testing connectivity and table creation (PETPLAT-26)

Once the dev RDS instance is deployed and at least one service has started,
verify from a throwaway debug pod on the EKS cluster (never expose RDS
publicly to test this from a laptop):

  kubectl run mysql-debug --rm -it --restart=Never --image=mysql:8.0 -- \
    mysql -h <rds_endpoint> -u petclinic -p petclinic

  -- inside the mysql client:
  SHOW TABLES;

Expect to see all 7 tables once customers-service, vets-service, and
visits-service have each started at least once, in the order above. The
password comes from Secrets Manager (petclinic/{env}/rds-credentials) —
retrieve it for this manual check with:

  aws secretsmanager get-secret-value \
    --secret-id petclinic/dev/rds-credentials \
    --region eu-central-1 \
    --query SecretString --output text

Prod: one-time bootstrap and per-service users (PET-8)

Prod does not use Spring auto-init. helm-values/prod.yaml sets
SPRING_SQL_INIT_MODE=never, and each DB service connects as its own user
(customers, visits, vets) with SELECT/INSERT/UPDATE/DELETE on its own tables
only. The master user never reaches petclinic-prod.

What enforces what

  RDS parameter group   require_secure_transport=1, non-TLS connections rejected
  MySQL users           REQUIRE SSL, DML-only grants per table
  App JDBC URL          sslMode=VERIFY_IDENTITY against the RDS CA truststore
                        built by the chart's build-rds-truststore init container
  Secrets               petclinic/prod/db-<svc> (rds module), synced by
                        k8s/base/external-secrets/db-credentials-prod.yaml

Run once, after terraform apply and ESO install, before the first ArgoCD sync
of customers/visits/vets (PET-14):

  1. Refill the endpoint placeholder in the bootstrap job and in helm-values/prod.yaml
     (the chart refuses to render customers/visits/vets while it is still there),
     then commit prod.yaml so ArgoCD picks it up:

       sed -i "s|<RDS_ENDPOINT>|$(terraform -chdir=terraform/environments/prod output -raw rds_endpoint)|" k8s/base/db-bootstrap/kustomization.yaml helm-values/prod.yaml

  2. Apply and wait for the job:

       kubectl apply -k k8s/base/db-bootstrap && kubectl -n petclinic-db-bootstrap wait --for=condition=complete job/db-bootstrap --timeout=300s && kubectl -n petclinic-db-bootstrap logs job/db-bootstrap

     The job is idempotent (CREATE TABLE IF NOT EXISTS, INSERT IGNORE,
     CREATE USER IF NOT EXISTS + ALTER USER). Rerun it after rotating a
     db-<svc> secret.

  3. Remove the master credentials from the cluster:

       kubectl delete namespace petclinic-db-bootstrap

  4. Apply the app ExternalSecrets, then sync customers, vets, visits in that order:

       kubectl apply -f k8s/base/external-secrets/db-credentials-prod.yaml

Runtime checks (PET-14), from a debug pod:

  A connection with --ssl-mode=DISABLED must fail.
  SHOW GRANTS FOR 'visits'@'%'; lists only petclinic.visits.
  The app pods reach Ready with the db-<svc> users.

Schema changes: the SQL in k8s/base/db-bootstrap/sql/ is copied from the app
repo at commit 440b9ad. If the app's schema.sql changes, copy it again and
rerun the job.

Final snapshot: prod storage and the final snapshot are encrypted with the
RDS customer-managed key. After a terraform destroy that key is scheduled for
deletion (kms_deletion_window_days, 30 in prod). Once the window passes the
snapshot cannot be restored, so cancel the key deletion first if the snapshot
is needed:

  aws kms cancel-key-deletion --region eu-central-1 --key-id "$(aws kms describe-key --region eu-central-1 --key-id alias/petclinic-prod-rds --query KeyMetadata.KeyId --output text)"
