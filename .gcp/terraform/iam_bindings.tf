# ------------------------------------------------------------
# PROJECT-LEVEL BINDINGS
# ------------------------------------------------------------

# Roles for dataform pipeline
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

# ------------------------------------------------------------
# RESOURCE-LEVEL BINDINGS (Storage & Compute)
# ------------------------------------------------------------

resource "google_storage_bucket_iam_member" "googgle_drive_extractor_access" {
  bucket = google_storage_bucket.marketing_archival_bucket.name
  member = "serviceAccount:${google_service_account.platform_accounts["drive-extractor-sa"].email}"
  role   = "roles/storage.objectAdmin"
}
