terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod-01"
    storage_account_name = "sttfstatelav01" # <--- UPDATE THIS NAME
    container_name       = "tfstate"
    key                  = "hub-spoke.tfstate"
  }
}

provider "azurerm" {
  features {}
}