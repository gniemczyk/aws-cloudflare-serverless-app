# --- 9. OUTPUTS ---
output "frontend_url" {
  value = "https://${var.sub_domain}.${var.main_domain}"
}

output "api_url" {
  value = "https://${var.sub_domain_api}.${var.main_domain}"
}

output "sns_topic_arn" {
  description = "ARN tematu SNS dla powiadomień"
  value       = aws_sns_topic.alerts_topic.arn
}
