# --- 1. BAZA DANYCH DYNAMODB AWS ---
resource "aws_dynamodb_table" "cards_table" {
  name           = "${var.db_name}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "${var.db_hash_key}"

  attribute {
    name = "${var.db_hash_key}"
    type = "S"
  }
}

# --- 2. S3 DLA FRONTENDU ---
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.sub_domain}.${var.main_domain}"
}

resource "aws_s3_bucket_website_configuration" "frontend_config" {
  bucket = aws_s3_bucket.frontend_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "frontend_public_access" {
  bucket = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.frontend_public_access]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
    }]
  })
}

# Rekord CNAME w Cloudflare dla Frontendu (S3)
resource "cloudflare_record" "frontend_cname" {
  zone_id = var.cloudflare_zone_id
  name    = var.sub_domain
  content = aws_s3_bucket_website_configuration.frontend_config.website_endpoint
  type    = "CNAME"
  proxied = true
}

# --- 3. LAMBDA (BACKEND) ---
data "archive_file" "lambda_dummy" {
  type        = "zip"
  output_path = "${path.module}/lambda_function_payload.zip"
  source {
    content  = "def handler(event, context): return {'statusCode': 200, 'body': 'API Working'}"
    filename = "main.py"
  }
}

resource "aws_lambda_function" "api_lambda" {
  filename      = data.archive_file.lambda_dummy.output_path
  function_name = "${var.sub_domain_api}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "main.handler"
  runtime       = "python3.9"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.cards_table.name
    }
  }
}

# --- 4. UPRAWNIENIA (IAM) ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.sub_domain}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_dynamo_policy" {
  name = "LambdaDynamoPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan", "dynamodb:DeleteItem"]
      Effect   = "Allow"
      Resource = aws_dynamodb_table.cards_table.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamo_policy.arn
}

# --- 5. API GATEWAY (HTTP API) ---
resource "aws_apigatewayv2_api" "http_api" {
  name = "${var.sub_domain_api}-HTTPAPI"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "api_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit = 500  # Pozwala na nagły skok ruchu
    throttling_rate_limit  = 100  # Pozwala na stały ruch 100 zapytań na sekundę
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- 6. AUTOMATYKA CERTYFIKATU I DOMENY API ---
resource "aws_acm_certificate" "api_cert" {
  domain_name = "${var.sub_domain_api}.${var.main_domain}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "api_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  content   = each.value.record
  type    = each.value.type
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "api_cert_validation" {
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in cloudflare_record.api_validation : record.hostname]
}

resource "aws_apigatewayv2_domain_name" "api_custom_domain" {
  domain_name = "${var.sub_domain_api}.${var.main_domain}"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api_cert_validation.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
  depends_on = [aws_acm_certificate_validation.api_cert_validation]
}

resource "aws_apigatewayv2_api_mapping" "api_mapping" {
  api_id      = aws_apigatewayv2_api.http_api.id
  domain_name = aws_apigatewayv2_domain_name.api_custom_domain.id
  stage       = aws_apigatewayv2_stage.api_stage.id
}

resource "cloudflare_record" "api_cname" {
  zone_id = var.cloudflare_zone_id
  name    = var.sub_domain_api
  content   = aws_apigatewayv2_domain_name.api_custom_domain.domain_name_configuration[0].target_domain_name
  type    = "CNAME"
  proxied = true
}

# --- 7. MONITORING: CLOUDWATCH DASHBOARD ---
resource "aws_cloudwatch_dashboard" "main_dashboard" {
  dashboard_name = "DevOps_Monitoring"

  dashboard_body = jsonencode({
    widgets = [
      # Wykres 1: Liczba wywołań Lambdy i błędy
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.sub_domain_api, { "label": "Liczba wywołań" }],
            [".", "Errors", ".", ".", { "label": "Błędy Lambdy", "color": "#d62728" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "Statystyki Lambdy (Invocations vs Errors)"
        }
      },
      # Wykres 2: Czas trwania wykonania (Latency)
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.sub_domain_api, { "stat": "Average", "label": "Średni czas (ms)" }],
            [".", ".", ".", ".", { "stat": "Maximum", "label": "Max czas (ms)" }]
          ]
          period = 60
          region = var.aws_region
          title  = "Czas trwania wykonania (Latency)"
        }
      },
      # Wykres 3: API Gateway - Ruch i błędy 4XX/5XX
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.http_api.id, { "label": "Liczba zapytań HTTP" }],
            [".", "4xx", ".", ".", { "label": "Błędy Klienta (4xx)", "color": "#ff7f0e" }],
            [".", "5xx", ".", ".", { "label": "Błędy Serwera (5xx)", "color": "#d62728" }],
            [".", "IntegrationError", ".", ".", { "label": "Błędy Integracji", "color": "#b22222" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
          title  = "Statystyki API Gateway"
        }
      }
    ]
  })
}

# --- 8. ALARMY I POWIADOMIENIA ---

# Temat powiadomień (kanał, na który będą wysyłane info)
resource "aws_sns_topic" "alerts_topic" {
  provider = aws.us_east_1
  name = "devops-alerts"
}

resource "aws_sns_topic" "alerts_topic_eu" {
  name = "devops-alerts-eu"
}

# Subskrypcja dla US
resource "aws_sns_topic_subscription" "email_subscription" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Subskrypcja dla UE
resource "aws_sns_topic_subscription" "email_subscription_eu" {
  topic_arn = aws_sns_topic.alerts_topic_eu.arn
  protocol  = "email"
  endpoint  = var.alert_email
}


# Alarm CloudWatch
resource "aws_cloudwatch_metric_alarm" "api_5xx_alarm" {
  alarm_name          = "API_Gateway_5xx_Errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Ten alarm monitoruje błędy 5xx API Gateway"
  alarm_actions       = [aws_sns_topic.alerts_topic_eu.arn]
  ok_actions          = [aws_sns_topic.alerts_topic_eu.arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.http_api.id
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  alarm_name          = "DynamoDB_System_Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Wykryto błędy systemowe po stronie DynamoDB"
  alarm_actions       = [aws_sns_topic.alerts_topic_eu.arn]
  ok_actions          = [aws_sns_topic.alerts_topic_eu.arn]

  dimensions = {
    TableName = aws_dynamodb_table.cards_table.name
  }
}

# Sprawdzanie dostępności strony (Health Check)
resource "aws_route53_health_check" "website_health_check" {
  fqdn              = "${var.sub_domain}.${var.main_domain}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = "3"
  request_interval  = "30"
  regions = ["eu-west-1", "us-east-1", "us-west-1"]
  tags = {
    Name = "Website-Content-Check"
  }
}

# 2. Alarm CloudWatch powiązany z powyższym sprawdzeniem
resource "aws_cloudwatch_metric_alarm" "website_uptime_alarm" {
  provider            = aws.us_east_1
  alarm_name          = "Website_Uptime_Down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"

  alarm_description   = "Alarm!!! Strona WWW przestała odpowiadać."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]
  ok_actions          = [aws_sns_topic.alerts_topic.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.website_health_check.id
  }
}
