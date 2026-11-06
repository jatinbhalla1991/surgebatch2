# Add the Terraform and AzureRM provider configuration here.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "9693fbdd-ebff-4b91-8eec-6a8aa0d5add2"
}