resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool-${var.environment}"
  display_name              = "Github Pool (${var.environment})"

  depends_on = [google_project_service.enabled_APIs]
}

# Access authentication provider for Github
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "Github Provider"

  # Map <GCP attributes> = <GitHub OIDC token claims>
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attributes.actor"     = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # Allowed repository
  attribute_condition = "attribute.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Extract provider name using after 'terraform apply': 
# terraform output -raw GITHUB_WIF_PROVIDER_NAME
output "GITHUB_WIF_PROVIDER_NAME" {
  value       = google_iam_workload_identity_pool_provider.github_provider.name
  description = "Github Repository Secret: WIF PROVIDER"
  sensitive   = true
}
