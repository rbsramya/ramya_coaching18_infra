
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}
output "ecs_cluster_id" {
  value = module.ecs_cluster.cluster_id
}

output "ecr_repository_url_s3" {
  value = aws_ecr_repository.ecr-s3.repository_url
}

output "ecr_repository_url_sqs" {
  value = aws_ecr_repository.ecr-sqs.repository_url
}

# Add these to output.tf (keep existing outputs)
output "ecr_repository_s3_name" {
  value       = aws_ecr_repository.ecr-s3.name
  description = "The name of the ECR repository"
}

output "ecr_repository_sqs_name" {
  value       = aws_ecr_repository.ecr-sqs.name
  description = "The name of the ECR repository"
}

output "ecs_service_s3_name" {
  value       = aws_ecs_service.app-s3.name
  description = "The name of the ECS service"
}

output "ecs_service_sqs_name" {
  value       = aws_ecs_service.app-sqs.name
  description = "The name of the ECS service"
}

output "task_definition_family_s3" {
  value       = aws_ecs_task_definition.app-s3.family
  description = "The family of the task definition"
}

output "task_definition_family_sqs" {
  value       = aws_ecs_task_definition.app-sqs.family
  description = "The family of the task definition"
}

output "container_name" {
  value       = "${local.prefix}-container"
  description = "The name of the container"
}


# Output the ECR Push Role ARN
output "ecr_push_role_arn" {
  value = aws_iam_role.cross_account_ecr_push_role.arn
}