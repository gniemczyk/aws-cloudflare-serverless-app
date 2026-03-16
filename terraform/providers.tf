terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # Konfiguracja Backend S3 z placeholderem
  backend "s3" {
    bucket  = "REPLACE_ME_STATE_BUCKET_NAME"
    key     = "state/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
