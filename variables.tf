variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair to use for SSH access"
  type        = string
}

variable "my_ip" {
  description = "Your public IP address in CIDR format for SSH access (e.g., 49.36.216.125/32)"
  type        = string
}

variable "db_user" {
  description = "Master username for the Aurora PostgreSQL database"
  type        = string
}

variable "db_password" {
  description = "Master password for the Aurora PostgreSQL database"
  type        = string
  sensitive   = true
}
