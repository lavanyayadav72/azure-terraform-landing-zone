variable "location" {
  type        = string
  default     = "canadacentral"
  description = "Primary Azure region"
}

variable "hub_rg_name" {
  type    = string
  default = "rg-hub-prod-01"
}

variable "spoke_rg_name" {
  type    = string
  default = "rg-spoke-prod-01"
}

variable "hub_vnet_cidr" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "spoke_vnet_cidr" {
  type    = list(string)
  default = ["10.1.0.0/16"]
}