
variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "cluster_name" {
    type = string
    default ="eks-demo"
}

variable "owner" {
  type = string
}

variable "project" {
    type = string
}

variable "environment" {
    type = string
}