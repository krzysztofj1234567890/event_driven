#######################################################
# create S3
#######################################################

# create S3 bucket
resource "aws_s3_bucket" "lambda_bucket" {
    bucket = var.bucket_name
}

# bucket ownership
resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
    bucket = aws_s3_bucket.lambda_bucket.id
    rule {
        object_ownership = "BucketOwnerPreferred"
    }
}

# bucket acl
resource "aws_s3_bucket_acl" "lambda_bucket" {
    depends_on = [
        aws_s3_bucket_ownership_controls.lambda_bucket,
    ]
    bucket  = aws_s3_bucket.lambda_bucket.id
    acl     = "private"
}


#######################################################
# create API Gateway
#######################################################

module "api_gateway" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 4.0"
  name          = "kj-api-gateway"
  description   = "HTTP API Gateway"
  protocol_type = "HTTP"
  create_api_domain_name = false
  integrations = {
    "POST /orders/create" = {
      integration_type    = "AWS_PROXY"
      integration_subtype = "EventBridge-PutEvents"
      credentials_arn     = module.apigateway_put_events_to_eventbridge_role.iam_role_arn
      request_parameters = jsonencode({
        EventBusName = module.eventbridge.eventbridge_bus_name,
        Source       = "api.gateway.orders.create",
        DetailType   = "Order Create",
        Detail       = "$request.body",
        Time         = "$context.requestTimeEpoch"
      })
      payload_format_version = "1.0"
    }
  }
}

module "apigateway_put_events_to_eventbridge_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 4.0"
  create_role = true
  role_name         = "apigateway-put-events-to-eventbridge"
  role_requires_mfa = false
  trusted_role_services = ["apigateway.amazonaws.com"]
  custom_role_policy_arns = [
    module.apigateway_put_events_to_eventbridge_policy.arn
  ]
}

module "apigateway_put_events_to_eventbridge_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 4.0"
  name        = "apigateway-put-events-to-eventbridge"
  description = "Allow PutEvents to EventBridge"
  policy = data.aws_iam_policy_document.apigateway_put_events_to_eventbridge_policy.json
}

data "aws_iam_policy_document" "apigateway_put_events_to_eventbridge_policy" {
  statement {
    sid       = "AllowPutEvents"
    actions   = ["events:PutEvents"]
    resources = [module.eventbridge.eventbridge_bus_arn]
  }
  depends_on = [module.eventbridge]
}

#######################################################
# Redshift serverless
#######################################################

data "aws_availability_zones" "available" {}

locals {
  # name     = "kj-${basename(path.cwd)}"
  name        = "kj-redshift"
  vpc_cidr    = var.vpc_cidr
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
  s3_prefix   = "redshift/${local.name}/"
}

resource "aws_redshiftserverless_namespace" "serverless" {
  namespace_name      = var.redshift_serverless_namespace_name
  db_name             = var.redshift_serverless_database_name
  admin_username      = var.redshift_serverless_admin_username
  admin_user_password = var.redshift_serverless_admin_password
  iam_roles           = [aws_iam_role.redshift-serverless-role.arn]
}

resource "aws_redshiftserverless_workgroup" "serverless" {
  depends_on = [aws_redshiftserverless_namespace.serverless]
  namespace_name = aws_redshiftserverless_namespace.serverless.id
  workgroup_name = var.redshift_serverless_workgroup_name
  base_capacity  = var.redshift_serverless_base_capacity
  security_group_ids = [module.security_group.security_group_id]
  subnet_ids         = module.vpc.redshift_subnets
  publicly_accessible = var.redshift_serverless_publicly_accessible
  config_parameter {
    parameter_key = "enable_case_sensitive_identifier"
    parameter_value = true
  }
}

resource "aws_iam_role" "redshift-serverless-role" {
  name = "${var.app_name}-${var.app_environment}-redshift-serverless-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "redshift.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "redshift-lambda-full-access-policy" {
  name = "${var.app_name}-${var.app_environment}-redshift-serverless-role-lambda-policy"
  role = aws_iam_role.redshift-serverless-role.id
  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
     {
       "Effect": "Allow",
       "Action": "lambda:*",
       "Resource": "*"
      }
   ]
}
EOF
}

# Get the AmazonRedshiftAllCommandsFullAccess policy
data "aws_iam_policy" "redshift-full-access-policy" {
  name = "AmazonRedshiftAllCommandsFullAccess"
}

# Attach the policy to the Redshift role
resource "aws_iam_role_policy_attachment" "attach-lambda" {
  role       = aws_iam_role.redshift-serverless-role.name
  policy_arn = data.aws_iam_policy.redshift-full-access-policy.arn
}

module "vpc" {
  source            = "terraform-aws-modules/vpc/aws"
  version           = "~> 5.0"
  name              = local.name
  cidr              = local.vpc_cidr
  azs               = local.azs
# /20
  private_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k)]
  redshift_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 10)]
# /24
#  private_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
#  redshift_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 4)]
  create_redshift_subnet_group = false
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/redshift"
  version = "~> 5.0"
  name        = local.name
  description = "Redshift security group"
  vpc_id      = module.vpc.vpc_id
  # Allow ingress rules to be accessed only within current VPC
  ingress_rules       = ["redshift-tcp"]
  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  # Allow all rules for all protocols
  egress_rules = ["all-all"]
}

#######################################################
# SecretsManager to access Redshift ????????????????????????????????????????????????????/
#######################################################

resource "aws_secretsmanager_secret" "redshift" {
  name = "kj_redshift_secret"
}

resource "aws_secretsmanager_secret_version" "redshift" {
  secret_id     = aws_secretsmanager_secret.redshift.id
  secret_string = <<EOF
{
  "username": "${var.redshift_serverless_admin_username}",
  "password": "${var.redshift_serverless_admin_password}"
}
EOF
}

#######################################################
# Lambda(s)
#######################################################

## write_redshift_order

module "lambda_write_redshift_order" {
  source = "terraform-aws-modules/lambda/aws"
  function_name = "WriteRedshiftOrder"
  handler       = "write_redshift_order.lambda_handler"
  runtime       = "python3.8"
  source_path = "src/write_redshift_order"
  store_on_s3 = true
  s3_bucket   = aws_s3_bucket.lambda_bucket.id
  environment_variables = {
    DB_TABLE = "order_table"
  }
  logging_log_group             = "/aws/lambda/write_redshift_order_group"
  logging_log_format            = "JSON"
  logging_application_log_level = "INFO"
  logging_system_log_level      = "DEBUG"

  create_current_version_allowed_triggers = false
  allowed_triggers = {
    ScanAmiRule = {
      principal  = "events.amazonaws.com"
      source_arn = module.eventbridge.eventbridge_rule_arns["rule_sqs"]
    }
  }

  attach_policy_jsons = true
  policy_jsons = [
    <<-EOT
      {
          "Version": "2012-10-17",
          "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "redshift-data:ExecuteStatement",
                    "redshift-serverless:GetCredentials",
                    "redshift-data:GetStatementResult",
                    "redshift-data:CancelStatement",
                    "redshift-data:DescribeStatement",
                    "redshift-data:ListStatements",
                    "redshift-data:ListTables",
                    "redshift-data:ListSchemas"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            }
          ]
      }
    EOT
  ]
  number_of_policy_jsons = 1
}

## read_redshift_order.py

module "lambda_read_redshift_order" {
  source = "terraform-aws-modules/lambda/aws"
  function_name = "ReadRedshiftOrder"
  handler       = "read_redshift_order.lambda_handler"
  runtime       = "python3.8"
  source_path = "src/read_redshift_order"
  store_on_s3 = true
  s3_bucket   = aws_s3_bucket.lambda_bucket.id
  environment_variables = {
    REDSHIFT_WORKGROUP = "${var.redshift_serverless_workgroup_name}"
    REDSHIFT_DATABASE = "${var.redshift_serverless_database_name}"
    REDSHIFT_SECRET_ARN = "${aws_secretsmanager_secret.redshift.arn}"
  }
  logging_log_group             = "/aws/lambda/read_redshift_order"
  logging_log_format            = "JSON"
  logging_application_log_level = "INFO"
  logging_system_log_level      = "DEBUG"

  create_current_version_allowed_triggers = false
  allowed_triggers = {
    APIGatewayAny = {
      principal  = "apigateway.amazonaws.com"
      source_arn = module.api_gateway.default_apigatewayv2_stage_arn
    }
    ScanAmiRule = {
      principal  = "apigateway.amazonaws.com"
      source_arn = module.api_gateway.default_apigatewayv2_stage_arn
    }
  }

  attach_policy_jsons = true
  policy_jsons = [
    <<-EOT
      {
          "Version": "2012-10-17",
          "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "redshift-data:ExecuteStatement",
                    "redshift-serverless:GetCredentials",
                    "redshift-data:GetStatementResult",
                    "redshift-data:CancelStatement",
                    "redshift-data:DescribeStatement",
                    "redshift-data:ListStatements",
                    "redshift-data:ListTables",
                    "redshift-data:ListSchemas"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "secretsmanager:GetSecretValue"
                ],
                "Resource": "*"
            }
          ]
      }
    EOT
  ]
  number_of_policy_jsons = 1
}


resource "aws_apigatewayv2_integration" "read_redshift_order" {
  api_id = module.api_gateway.apigatewayv2_api_id
  integration_uri    = module.lambda_read_redshift_order.lambda_function_arn
  integration_type   = "AWS_PROXY"
  integration_method = "GET"
}

resource "aws_apigatewayv2_route" "read_redshift_order" {
  api_id = module.api_gateway.apigatewayv2_api_id
  route_key = "GET /orders"
  target    = "integrations/${aws_apigatewayv2_integration.read_redshift_order.id}"
}

resource "aws_lambda_permission" "api_gw_read_redshift_order" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_read_redshift_order.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*"
}


#######################################################
# Eventbridge
#######################################################

module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"
  version = "3.13.0"
  bus_name = "kj-bus"
  rules = {
    rule_sqs = {
      event_pattern = jsonencode({
        "detail-type" : ["Order Create"],
        "source" : ["api.gateway.orders.create"]
      })
    }
  }
  targets = {
    rule_sqs = [
      {
        name            = "send-orders-to-sqs"
        arn             = aws_sqs_queue.queue.arn
        dead_letter_arn = aws_sqs_queue.dlq.arn
        target_id       = "send-orders-to-sqs"
      },
      {
        name = "event-to-lambda"
        arn  = "${module.lambda_write_redshift_order.lambda_function_arn}"
        target_id       = "send-orders-to-redshift"
      }
    ]
  }
}

#######################################################
# SQS
#######################################################

resource "aws_sqs_queue" "dlq" {
  name = "kj-dlq"
}

resource "aws_sqs_queue" "queue" {
  name = "kj-queue"
}

resource "aws_sqs_queue_policy" "queue" {
  queue_url = aws_sqs_queue.queue.id
  policy    = data.aws_iam_policy_document.queue.json
}

data "aws_iam_policy_document" "queue" {
  statement {
    sid     = "AllowSendMessage"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sqs_queue.queue.arn]
  }
}
