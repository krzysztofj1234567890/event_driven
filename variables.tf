variable "bucket_name" {}
variable "region" {}
variable "vpc_cidr" {}

##########################
# Application Definition 
##########################
variable "app_name" {
  type        = string
  description = "Application name"
}

variable "app_environment" {
  type        = string
  description = "Application environment"
}


#######################################################
# Redshift serverless
#######################################################
variable "redshift_serverless_namespace_name" {
  type        = string
  description = "Redshift Serverless Namespace Name"
}

variable "redshift_serverless_database_name" { 
  type        = string
  description = "Redshift Serverless Database Name"
}

variable "redshift_serverless_admin_username" {
  type        = string
  description = "Redshift Serverless Admin Username"
}

variable "redshift_serverless_admin_password" { 
  type        = string
  description = "Redshift Serverless Admin Password"
}

variable "redshift_serverless_workgroup_name" {
  type        = string
  description = "Redshift Serverless Workgroup Name"
}

variable "redshift_serverless_base_capacity" {
  type        = number
  description = "Redshift Serverless Base Capacity"
  default     = 32 // 32 RPUs to 512 RPUs in units of 8 (32,40,48...512)
}

variable "redshift_serverless_publicly_accessible" {
  type        = bool
  description = "Set the Redshift Serverless to be Publicly Accessible"
  default     = false
}
