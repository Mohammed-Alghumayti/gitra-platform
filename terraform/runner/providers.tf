terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State lives in an Azure Storage account so every GitHub Actions run sees
  # the same infrastructure. The workflow creates the account and passes its
  # name with -backend-config (see .github/workflows/deploy.yml).
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    # gitra-runner-rg only holds the runner. When it moves region, it must be
    # deletable even if a failed VM attempt left a disk behind in it.
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # Authenticates with ARM_* environment variables (GitHub Actions) or `az login`.
  subscription_id = var.subscription_id
}
