# Remote state backend — prod environment
# Same state bucket as dev, separate state key. See
# docs/technical-spec.md#terraform-state-backend.
#
#   terraform init -backend-config="bucket=petclinic-terraform-state-<ACCOUNT_ID>"
#
# or copy backend.hcl.example to backend.hcl (gitignored) and run:
#
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key            = "petclinic/prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
