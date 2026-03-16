variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "main_domain" {
  type = string
}

variable "sub_domain" {
  type = string
}

variable "sub_domain_api" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_hash_key" {
  type = string
}

variable "alert_email" {
  type        = string
  description = "Adres e-mail do powiadomień"
}
