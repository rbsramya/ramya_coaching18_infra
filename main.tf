terraform {
  backend "s3" {
    bucket = "sctp-ce10-tfstate"
    key    = "ramya-coaching18-infra.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  prefix = "ramya-coaching18-infra"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ECR repository 1 S3 bucket
resource "aws_ecr_repository" "ecr-s3" {
  name         = "${local.prefix}-ecr-s3"
  force_delete = true
}

# ECR repository 2 SQS
resource "aws_ecr_repository" "ecr-sqs" {
  name         = "${local.prefix}-ecr-sqs"
  force_delete = true
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.prefix}-ecs-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${local.prefix}-s3-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for SQS access
resource "aws_iam_role_policy" "sqs_access" {
  name = "${local.prefix}-sqs-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:DeleteMessage"
        ]
        Resource = aws_sqs_queue.message_input_queue.arn
      }
    ]
  })
}

# # IAM Role for ECR Push
# resource "aws_iam_role" "ecr_push_role" {
#   name = "${local.prefix}-ecr-push-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecr_push_attach" {
#   role       = aws_iam_role.ecr_push_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
# }

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${local.prefix}-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.prefix}-public-${count.index}"
  }
}

data "aws_availability_zones" "available" {}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.prefix}-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.prefix}-public-rt"
  }
}

# Associate Route Table with Subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
  name        = "${local.prefix}-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5002
    to_port     = 5002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix}-sg"
  }
}
# S3 Bucket
resource "aws_s3_bucket" "app_bucket" {
  bucket = "${local.prefix}-app-bucket"
}

# ECS Cluster
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "4.1.3"

  cluster_name = "${local.prefix}-ecs"
}

# ECS Task Definition-S3 (update)
resource "aws_ecs_task_definition" "app-s3" {
  family                   = "${local.prefix}-task-s3"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn  
  container_definitions = jsonencode([{
    name      = "${local.prefix}-container"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com/${local.prefix}-ecr-s3:latest"
    essential = true
    environment = [
      {
        name  = "S3_BUCKET_NAME"
        value = aws_s3_bucket.app_bucket.bucket
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      }
    ]
    portMappings = [{
      containerPort = 5001
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "s3-service"
      }
    }
  }])
}

# ECS Task Definition-SQS (update)
resource "aws_ecs_task_definition" "app-sqs" {
  family                   = "${local.prefix}-task-sqs"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "${local.prefix}-container"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.id}.amazonaws.com/${local.prefix}-ecr-sqs:latest"
    essential = true
    environment = [
      {
        name  = "SQS_QUEUE_URL"
        value = aws_sqs_queue.message_input_queue.url
      },
      {
        name  = "AWS_REGION"
        value = data.aws_region.current.name
      }
    ]
    portMappings = [{
      containerPort = 5002
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "sqs-service"
      }
    }
  }])
}


# ECS Service -S3
resource "aws_ecs_service" "app-s3" {
  name            = "${local.prefix}-service-s3"
  cluster         = module.ecs_cluster.cluster_id
  launch_type     = "FARGATE"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.app-s3.arn
  
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_iam_role_policy_attachment.ecs_task_exec_attach]
}

# ECS Service -SQS
resource "aws_ecs_service" "app-sqs" {
  name            = "${local.prefix}-service-sqs"
  cluster         = module.ecs_cluster.cluster_id
  launch_type     = "FARGATE"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.app-sqs.arn

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [aws_iam_role_policy_attachment.ecs_task_exec_attach]
}

#SQS infa
resource "aws_sqs_queue" "message_input_queue" {
  name                      = "${local.prefix}-message-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 days

  tags = {
    Name        = "Service2MessageQueue"
    #Environment = "dev"
  }
}

# IAM Role for ECR Push from other repo (app team)
resource "aws_iam_role" "cross_account_ecr_push_role" {
  name = "${local.prefix}-cross-account-ecr-push-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::255945442255:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cross_account_ecr_push_attach" {
  role       = aws_iam_role.cross_account_ecr_push_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}


# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.prefix}"
  retention_in_days = 7
}
