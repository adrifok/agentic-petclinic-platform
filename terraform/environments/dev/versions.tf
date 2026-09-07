terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Required transitively by the eks module (OIDC issuer certificate
    # lookup). Declared explicitly here too for clarity/reproducibility.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
