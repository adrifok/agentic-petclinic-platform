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
