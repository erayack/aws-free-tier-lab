variable "expected_account_id" {
  description = "Your AWS account ID. Terraform refuses to run against another account."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Enter your 12-digit AWS account ID."
  }
}

variable "aws_profile" {
  description = "Your AWS CLI profile, or null to use the standard credential chain."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region for the temporary resources."
  type        = string
  default     = "eu-central-1"
  nullable    = false
}
