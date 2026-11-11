terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  profile             = var.aws_profile
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
  default_tags {
    tags = {
      Project   = "aws-free-tier-lab"
      ManagedBy = "Terraform"
      Temporary = "true"
    }
  }
}

locals {
  name = "aws-free-tier-lab"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "demo" {
  cidr_block = "10.87.0.0/16"
}

resource "aws_subnet" "demo" {
  count                   = 2
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.87.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
}

resource "aws_security_group" "isolated" {
  name_prefix = "${local.name}-"
  description = "No ingress or egress; credit activity resources only"
  vpc_id      = aws_vpc.demo.id
}

data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.linux.id
  instance_type               = "t4g.micro"
  subnet_id                   = aws_subnet.demo[0].id
  vpc_security_group_ids      = [aws_security_group.isolated.id]
  associate_public_ip_address = false
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags = { Name = local.name }
}

resource "aws_budgets_budget" "demo" {
  name         = local.name
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "logs" {
  role = aws_iam_role.lambda.name
  name = "${local.name}-logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }]
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"
  source {
    filename = "index.py"
    content  = <<-PYTHON
      def handler(event, context):
          return {
              "statusCode": 200,
              "headers": {"content-type": "text/html; charset=utf-8"},
              "body": "<!doctype html><title>AWS credit activity</title><h1>Hello from Lambda</h1>"
          }
    PYTHON
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 1
}

resource "aws_lambda_function" "demo" {
  function_name                  = local.name
  role                           = aws_iam_role.lambda.arn
  runtime                        = "python3.13"
  handler                        = "index.handler"
  architectures                  = ["arm64"]
  filename                       = data.archive_file.lambda.output_path
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  memory_size                    = 128
  timeout                        = 3
  reserved_concurrent_executions = -1
  depends_on                     = [aws_iam_role_policy.logs, aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_function_url" "demo" {
  function_name      = aws_lambda_function.demo.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "url" {
  statement_id           = "PublicFunctionURL"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.demo.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invoke" {
  statement_id             = "PublicInvokeViaURLOnly"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.demo.function_name
  principal                = "*"
  invoked_via_function_url = true
}

resource "aws_db_subnet_group" "demo" {
  name       = local.name
  subnet_ids = aws_subnet.demo[*].id
}

resource "aws_db_instance" "demo" {
  identifier                  = local.name
  engine                      = "postgres"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  username                    = "demo_admin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.demo.name
  vpc_security_group_ids      = [aws_security_group.isolated.id]
  publicly_accessible         = false
  multi_az                    = false
  backup_retention_period     = 0
  skip_final_snapshot         = true
  delete_automated_backups    = true
  deletion_protection         = false
}

