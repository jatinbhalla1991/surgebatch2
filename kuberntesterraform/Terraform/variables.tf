variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}
variable "sql_server_name" {
  type = string
}

variable "sql_db_name" {
  type = string
}

variable "aks_cluster_name" {
  description = "Name of the AKS Cluster"
  type        = string
  default     = "aks-demo-cluster"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for node pool"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version"
  type        = string
  default     = "1.29.2"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}
