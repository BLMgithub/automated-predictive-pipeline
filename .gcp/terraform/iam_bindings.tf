# ------------------------------------------------------------
# PROJECT-LEVEL BINDINGS
# ------------------------------------------------------------

# -------------------------------------------
# GitHub Deployer
# -------------------------------------------
locals {
  deployer_roles = [
    "roles/run.developer",                   # Manage Cloud Run jobs
    "roles/workflows.editor",                # Manage Workflows
    "roles/cloudscheduler.admin",            # Manage Scheduler
    "roles/iam.serviceAccountUser",          # Act as SAs for jobs
    "roles/artifactregistry.admin",          # Manage Artifact Registry
    "roles/eventarc.admin",                  # Manage Eventarc triggers
    "roles/storage.admin",                   # Manage buckets and state locking
    "roles/resourcemanager.projectIamAdmin", # Manage the IAM bindings in this code
    "roles/iam.workloadIdentityPoolAdmin",   # Manage WIF in wif.tf
    "roles/monitoring.admin",                # Manage Monitoring in monitoring.tf
    "roles/logging.configWriter",            # Required for log-based alert policies
    "roles/logging.logWriter",               # Write failure logs from GitHub Actions
    "roles/iam.serviceAccountAdmin",         # Manage Alert policies in monitoring.tf
    "roles/iam.admin",                       # Manage Iam roles
    "roles/bigquery.admin",                  # Manage BigQuery datasets and views
    "roles/serviceusage.serviceUsageAdmin",  # Manage APIs
    "roles/secretmanager.admin",             # Manage secrets and their IAM policies
  ]
}

resource "google_project_iam_member" "github_deployer_permissions" {
  for_each = toset(local.deployer_roles)
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.platform_accounts["github-actions-deployer-sa"].email}"
}

resource "google_service_account_iam_member" "github_deployer_sa" {
  service_account_id = google_service_account.platform_accounts["github-actions-deployer-sa"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# -------------------------------------------
# Dataform pipeline
# -------------------------------------------
locals {
  pipeline_roles = [
    "roles/bigquery.admin",      # Manage bigquery datasets/views/tables
    "roles/storage.objectViewer" # Read access to buckets
  ]
}

resource "google_project_iam_member" "dataform_pipeline_access" {
  for_each = toset(local.pipeline_roles)
  project  = var.project_id
  member   = "serviceAccount:${google_service_account.platform_accounts["dataform-pipeline-sa"].email}"
  role     = each.key
}

resource "google_secret_manager_secret_iam_member" "github_token_accessor" {
  project   = var.project_id
  secret_id = "github-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.platform_accounts["dataform-orchestration-sa"].email}"
}

resource "google_secret_manager_secret" "github_token" {
  secret_id = "github-token"
  replication {
    auto {}
  }
  depends_on = [google_project_service.enabled_APIs]
}

# -------------------------------------------
# Orchestrations
# -------------------------------------------

locals {
  dataform_orchestration_roles = [
    "roles/workflows.invoker",
    "roles/logging.logWriter"
  ]
}

resource "google_project_iam_member" "dataform_orchestration_workflow" {
  for_each = toset(local.dataform_orchestration_roles)
  project  = var.project_id
  member   = "serviceAccount:${google_service_account.platform_accounts["dataform-orchestration-sa"].email}"
  role     = each.key
}


resource "google_project_iam_member" "extractor_orchestration_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.platform_accounts["extractor-orchestration-sa"].email}"
}

# ------------------------------------------------------------
# RESOURCE-LEVEL BINDINGS (Storage & Compute)
# ------------------------------------------------------------

resource "google_storage_bucket_iam_member" "googgle_drive_extractor_access" {
  bucket = google_storage_bucket.marketing_archival_bucket.name
  member = "serviceAccount:${google_service_account.platform_accounts["drive-extractor-sa"].email}"
  role   = "roles/storage.objectAdmin"
}
