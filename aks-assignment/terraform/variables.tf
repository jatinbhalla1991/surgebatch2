# Declare Terraform input variables here.
variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "resource_group_name" {
  type    = string
  default = "aks-assignment-rg"
}

variable "cluster_name" {
  type    = string
  default = "my-aks-cluster"
}

variable "acr_name" {
  type        = string
  description = "Globally unique, lowercase letters and numbers only"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}