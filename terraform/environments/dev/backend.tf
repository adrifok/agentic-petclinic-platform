# Remote state backend — dev environment
# State bucket and lock table are provisioned by scripts/bootstrap-state.sh
# (outside Terraform — see docs/technical-spec.md#terraform-state-backend).
#
# The bucket name includes the AWS account ID and is therefore NOT hardcoded
# here (backend blocks can't reference variables or data sources). Supply it
# at init time:
#
#   terraform init -backend-config="bucket=petclinic-terraform-state-<ACCOUNT_ID>"
#
# or copy backend.hcl.example to backend.hcl (gitignored) and run:
#
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key            = "petclinic/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
