variable "log_archive_email" {
  description = "Email for the log archive account (must be unique)"
  type        = string
}

variable "audit_email" {
  description = "Email for the security audit account"
  type        = string
}

variable "default_governed_regions" {
  description = "Regions ABSA will govern in Control Tower"
  type        = list(string)
  default     = ["eu-west-1", "eu-west-2", "af-south-1"]
}