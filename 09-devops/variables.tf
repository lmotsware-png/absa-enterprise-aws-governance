# ============================================
# ABSA Enterprise AWS — Week 9: DevOps
# variables.tf
# ============================================

# ============================================
# REGION CONFIGURATION
# ============================================

variable "primary_region" {
  description = "Primary AWS region (Cape Town) — all pipeline resources live here"
  type        = string
  default     = "af-south-1"
}

variable "dr_region" {
  description = "DR AWS region (Ireland) — secondary deployment target"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment identifier"
  type        = string
  default     = "Production"
}

# ============================================
# APPLICATION CONFIGURATION
# ============================================

variable "applications" {
  description = <<-EOT
    Map of applications managed by the DevOps pipeline.
    Each application gets:
      - A CodeCommit repository
      - An ECR repository
      - A CodePipeline pipeline
      - CodeBuild projects (build, test, deploy)
      - A CodeDeploy application
    Keys are used as resource name prefixes throughout.
  EOT
  type = map(object({
    # Human-readable display name
    display_name = string
    # Kubernetes namespace the app lives in (Week 5)
    k8s_namespace = string
    # Kubernetes deployment name to update on deploy
    k8s_deployment = string
    # Container name within the pod spec to update
    k8s_container = string
    # Default branch to trigger pipeline on
    branch = string
    # CodeBuild compute type for build stage
    # BUILD_GENERAL1_SMALL  = 3GB RAM,  2 vCPU  ($0.005/min)
    # BUILD_GENERAL1_MEDIUM = 7GB RAM,  4 vCPU  ($0.01/min)
    # BUILD_GENERAL1_LARGE  = 15GB RAM, 8 vCPU  ($0.02/min)
    build_compute_type = string
    # Minutes before CodeBuild times out
    build_timeout = number
    # Port the container listens on (for health checks)
    container_port = number
    # Minimum healthy pods during rolling update (percent)
    min_healthy_percent = number
    # Maximum pods during rolling update (percent)
    max_surge_percent = number
  }))
  default = {
    payment_api = {
      display_name        = "ABSA Payment API"
      k8s_namespace       = "payment-api"
      k8s_deployment      = "payment-api"
      k8s_container       = "payment-api"
      branch              = "main"
      build_compute_type  = "BUILD_GENERAL1_MEDIUM"
      build_timeout       = 20
      container_port      = 8080
      min_healthy_percent = 100
      max_surge_percent   = 125
    }
    fraud_detection = {
      display_name        = "ABSA Fraud Detection"
      k8s_namespace       = "fraud-detection"
      k8s_deployment      = "fraud-detection"
      k8s_container       = "fraud-detection"
      branch              = "main"
      build_compute_type  = "BUILD_GENERAL1_LARGE"
      build_timeout       = 30
      container_port      = 8081
      min_healthy_percent = 50
      max_surge_percent   = 150
    }
  }
}

# ============================================
# ECR CONFIGURATION
# ============================================

variable "ecr_image_retention_count" {
  description = <<-EOT
    Number of images to retain per ECR repository.
    Older images beyond this count are automatically deleted
    by ECR lifecycle policy. Prevents unbounded storage growth.
    Each Docker image layer is typically 100-500MB.
    30 images = approximately the last 30 deployments.
  EOT
  type    = number
  default = 30
}

variable "ecr_scan_on_push" {
  description = <<-EOT
    Enable ECR vulnerability scanning on every image push.
    Uses AWS Inspector (enhanced scanning) to check for:
      - OS package CVEs
      - Language runtime CVEs (Java, Python, Node.js)
      - Application dependency CVEs
    Results appear in the ECR console within 5 minutes.
    Pipeline does NOT block on scan findings — findings are
    reported but deployment continues. For blocking behavior,
    add a CodeBuild step that calls ecr:DescribeImageScanFindings
    and fails if CRITICAL severity findings exist.
  EOT
  type    = bool
  default = true
}

# ============================================
# CODEBUILD CONFIGURATION
# ============================================

variable "codebuild_timeout_minutes" {
  description = <<-EOT
    Default timeout for CodeBuild projects in minutes.
    Individual applications can override via the
    applications variable's build_timeout field.
    After this duration, CodeBuild marks the build as failed.
  EOT
  type    = number
  default = 20
}

variable "codebuild_image" {
  description = <<-EOT
    Docker image used as the CodeBuild build environment.
    aws/codebuild/standard:7.0 includes:
      - Amazon Linux 2023
      - Docker 24.x
      - Java 21 (Corretto)
      - Python 3.11
      - Node.js 18
      - kubectl 1.32
      - AWS CLI v2
    This image has native Docker daemon support for
    building Docker images within CodeBuild.
  EOT
  type    = string
  default = "aws/codebuild/standard:7.0"
}

variable "codebuild_privileged_mode" {
  description = <<-EOT
    Enable privileged mode in CodeBuild.
    REQUIRED for building Docker images within CodeBuild.
    Privileged mode gives the build container access to
    the Docker daemon socket (/var/run/docker.sock).
    Without this, 'docker build' commands fail with:
    "Cannot connect to the Docker daemon"
    Security note: privileged containers have elevated
    host access. The risk is acceptable here because
    CodeBuild containers are ephemeral, isolated, and
    run in AWS-managed infrastructure.
  EOT
  type    = bool
  default = true
}

# ============================================
# CODEPIPELINE CONFIGURATION
# ============================================

variable "pipeline_notification_email" {
  description = <<-EOT
    Email address for pipeline success/failure notifications.
    An SNS subscription is created for this address.
    The subscriber must confirm the subscription via email
    before notifications are delivered.
    In production, use a team distribution list rather
    than an individual address.
  EOT
  type    = string
  default = "devops-team@absa.co.za"
}

variable "require_manual_approval" {
  description = <<-EOT
    Require manual approval before deploying to production EKS.
    true:  Pipeline pauses after integration tests.
           A designated approver reviews test results and
           approves or rejects the deployment.
           Approval timeout: 7 days (AWS CodePipeline default).
    false: Pipeline deploys automatically after tests pass.
           Suitable for: hotfix pipelines, non-critical services.
    Payment API: true  (financial transactions — manual gate)
    Fraud Detection: false (ML model — auto-deploy on test pass)
    This variable sets the DEFAULT. Individual pipelines can
    override via the applications map if needed.
  EOT
  type    = bool
  default = true
}

variable "artifact_retention_days" {
  description = <<-EOT
    Days to retain CodePipeline artifacts in S3.
    Artifacts include: compiled binaries, test reports,
    Docker image digests, buildspec outputs.
    30 days covers: incident investigation window,
    compliance audit requirements for recent deployments,
    and rollback artifact availability.
    After 30 days, artifacts move to S3 GLACIER (see lifecycle policy).
    After 90 days, artifacts are permanently deleted.
  EOT
  type    = number
  default = 30
}

# ============================================
# DEPLOYMENT CONFIGURATION
# ============================================

variable "deploy_to_dr" {
  description = <<-EOT
    Deploy successfully built images to the DR EKS cluster
    in eu-west-1 after successful primary deployment.
    true:  Adds a DR deployment stage to each pipeline.
           DR cluster always runs the same version as primary.
           DR failover is immediately usable — no version gap.
    false: Only deploys to primary EKS.
           DR cluster must be manually updated during failover.
           Saves CodeBuild compute costs (~$5-10/month).
    Recommendation: true for production, false for learning.
  EOT
  type    = bool
  default = true
}

variable "eks_kubectl_role_arn" {
  description = <<-EOT
    IAM role ARN that CodeBuild assumes to run kubectl commands
    against the EKS cluster. This role must be listed in the
    EKS cluster's aws-auth ConfigMap.
    Format: arn:aws:iam::<account>:role/<role-name>
    If empty, the CodeBuild execution role itself is used
    (must then be in aws-auth ConfigMap directly).
    Best practice: use a dedicated deployment role with
    minimal Kubernetes RBAC permissions (only the namespaces
    and resource types the pipeline needs to update).
  EOT
  type    = string
  default = ""
}

# ============================================
# SONARQUBE / CODE QUALITY CONFIGURATION
# ============================================

variable "enable_sonar_scan" {
  description = <<-EOT
    Enable SonarQube code quality scanning in CodeBuild.
    Requires a SonarQube server or SonarCloud account.
    When true: SONAR_TOKEN must be stored in Secrets Manager
    at 'absa/devops/sonar-token' before pipeline runs.
    Scans for: code smells, duplications, coverage gaps,
    security hotspots beyond what SAST (Semgrep) finds.
  EOT
  type    = bool
  default = false
}

variable "semgrep_rules" {
  description = <<-EOT
    Semgrep ruleset for SAST (Static Application Security Testing).
    Applied during the build stage CodeBuild project.
    Options:
      "p/java"         — Java-specific security rules
      "p/python"       — Python security rules
      "p/owasp-top-ten" — OWASP Top 10 coverage
      "p/r2c-security-audit" — Comprehensive security audit
    Multiple rulesets: separate with space "p/java p/owasp-top-ten"
  EOT
  type    = string
  default = "p/java p/owasp-top-ten"
}