# ============================================
# CodeDeploy — Deployment Infrastructure
# ============================================
#
# ARCHITECTURAL NOTE — Why CodeDeploy is not the
# active EKS deployment mechanism:
#
# CodeDeploy supports three compute platforms:
#   - Server  (EC2/on-premises)
#   - Lambda  (Lambda functions)
#   - ECS     (Elastic Container Service)
#
# CodeDeploy does NOT natively support EKS.
# There is no "EKS" compute platform in CodeDeploy.
#
# Current EKS deployment mechanism (ACTIVE):
#   codebuild.tf → deploy and dr_deploy projects
#   These projects run kubectl commands:
#     1. aws eks update-kubeconfig --name <cluster>
#     2. kubectl set image deployment/<name> <container>=<image>:<tag>
#     3. kubectl rollout status deployment/<name> --timeout=10m
#   This gives us a rolling update with health verification.
#
# Future blue/green EKS options (not implemented):
#   Option A: AWS Load Balancer Controller +
#             Kubernetes native traffic splitting
#   Option B: Argo Rollouts (open source progressive delivery)
#   Option C: Flagger (automated canary deployments)
#   None of these use CodeDeploy — they use Kubernetes
#   custom resources and the AWS Load Balancer Controller.
#
# What this file creates:
#   1. CodeDeploy application for ECS (valid platform)
#      Reserved for future use if ABSA adds ECS workloads
#      alongside the existing EKS deployment.
#   2. IAM role — already defined in iam_roles.tf
#      No duplicate here — see iam_roles.tf for the role.
#
# The IAM role aws_iam_role.codedeploy is defined in
# iam_roles.tf — not here — to avoid circular dependencies
# between iam_roles.tf and codedeploy.tf.
# ============================================

# ============================================
# SECTION 1 — CodeDeploy Application
# ============================================
# compute_platform = "ECS" is the correct platform
# for container workloads with CodeDeploy.
# This application is reserved for future use if
# any ECS services are added to the platform.
#
# Note: EKS workloads (payment-api, fraud-detection)
# are deployed via kubectl in codebuild.tf — not here.

resource "aws_codedeploy_app" "payment_api" {
  name             = "ABSA-Payment-API"
  compute_platform = "ECS"

  tags = merge(local.common_tags, {
    Name   = "ABSA-Payment-API-CodeDeploy"
    Status = "Reserved-Future-Use"
    Note   = "EKS deployments use kubectl in codebuild.tf not CodeDeploy"
  })
}

resource "aws_codedeploy_app" "fraud_detection" {
  name             = "ABSA-Fraud-Detection"
  compute_platform = "ECS"

  tags = merge(local.common_tags, {
    Name   = "ABSA-Fraud-Detection-CodeDeploy"
    Status = "Reserved-Future-Use"
    Note   = "EKS deployments use kubectl in codebuild.tf not CodeDeploy"
  })
}

# ============================================
# SECTION 2 — Deployment Configuration
# ============================================
# Custom deployment configuration for canary-style
# traffic shifting if ECS workloads are added.
# Uses 10% traffic shift every minute — safer than
# CodeDeployDefault.ECSAllAtOnce for banking services.
#
# This configuration is created but not attached to
# any deployment group — it is ready for future use.

resource "aws_codedeploy_deployment_config" "canary_10_percent" {
  deployment_config_name = "ABSA-ECS-Canary-10-Percent"
  compute_platform       = "ECS"

  traffic_routing_config {
    type = "TimeBasedCanary"

    time_based_canary {
      # Shift 10% of traffic to new version
      interval   = 1
      percentage = 10
    }
  }
}

# ============================================
# SECTION 3 — IAM Role Reference
# ============================================
# The CodeDeploy service role is defined in iam_roles.tf:
#   resource "aws_iam_role" "codedeploy"
#   resource "aws_iam_role_policy_attachment" "codedeploy"
#
# Referenced here as: aws_iam_role.codedeploy.arn
# That role uses principal: codedeploy.amazonaws.com
# and has AWSCodeDeployRoleForECS policy attached.
#
# To use CodeDeploy for ECS in future:
#
#   resource "aws_codedeploy_deployment_group" "payment_api_prod" {
#     app_name               = aws_codedeploy_app.payment_api.name
#     deployment_group_name  = "production"
#     service_role_arn       = aws_iam_role.codedeploy.arn
#     deployment_config_name = aws_codedeploy_deployment_config.canary_10_percent.id
#
#     deployment_style {
#       deployment_type   = "BLUE_GREEN"
#       deployment_option = "WITH_TRAFFIC_CONTROL"
#     }
#
#     blue_green_deployment_config {
#       deployment_ready_option {
#         action_on_timeout    = "CONTINUE_DEPLOYMENT"
#         wait_time_in_minutes = 0
#       }
#       terminate_blue_instances_on_deployment_success {
#         action                           = "TERMINATE"
#         termination_wait_time_in_minutes = 15
#       }
#     }
#
#     auto_rollback_configuration {
#       enabled = true
#       events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
#     }
#
#     # ECS-specific — not EKS
#     ecs_service {
#       cluster_name = "<ecs-cluster-name>"
#       service_name = "<ecs-service-name>"
#     }
#
#     load_balancer_info {
#       target_group_pair_info {
#         prod_traffic_route {
#           listener_arns = ["<alb-listener-arn>"]
#         }
#         target_group {
#           name = "<blue-target-group-name>"
#         }
#         target_group {
#           name = "<green-target-group-name>"
#         }
#       }
#     }
#   }

# ============================================
# SECTION 4 — Current Deployment Reference
# ============================================
# Document what is actually doing deployments so
# any engineer reading this file understands the
# complete picture.
#
# ACTIVE deployment path for EKS workloads:
#
#   CodePipeline stage: Deploy-Primary
#     → CodeBuild project: absa-devops-deploy-payment-api
#     → buildspec: buildspec_deploy.yml
#     → Commands:
#         aws sts assume-role --role-arn $EKS_DEPLOY_ROLE_ARN
#         aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
#         kubectl set image deployment/payment-api \
#           payment-api=$ECR_REPOSITORY_URI:$IMAGE_TAG \
#           -n payment-api
#         kubectl rollout status deployment/payment-api \
#           -n payment-api --timeout=10m
#
#   CodePipeline stage: Deploy-DR
#     → CodeBuild project: absa-devops-dr-deploy-payment-api
#     → Same buildspec, targets DR EKS cluster
#     → EKS cluster: local.dr_eks_cluster_name
#         = data.terraform_remote_state.disaster_recovery
#           .outputs.dr_eks_cluster_name
#
# Rolling update parameters per application:
#   payment_api:
#     min_healthy_percent = 100  (zero downtime)
#     max_surge_percent   = 125  (25% extra pods during update)
#   fraud_detection:
#     min_healthy_percent = 50   (faster rollout)
#     max_surge_percent   = 150  (50% extra pods during update)
#
# These are set in var.applications in variables.tf
# and injected as environment variables into the
# deploy CodeBuild projects in codebuild.tf.
# ============================================

# No active deployment group resources in this file.
# All EKS deployments run through codebuild.tf.
# This file exists to:
#   1. Create CodeDeploy app resources for future ECS use
#   2. Create a deployment configuration for future use
#   3. Document the architectural decision clearly
#   4. Serve as the migration guide when blue/green
#      EKS deployments are adopted