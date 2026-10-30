variable "resource_group_name" {
  type        = string
}

variable "location" {
  type        = string
}

variable "aks_cluster_name" {
  type        = string
}

variable "node_count" {
  type        = number
}

variable "vm_size" {
  type        = string
}

variable "kubernetes_version" {
  type        = string
}

variable "environment" {
  type        = string
}
