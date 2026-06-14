# Create required SAs
locals {
  service_accounts = [
    "drive-extractor-sa",
    "dataform-pipeline-sa",
  ]
}

resource "google_service_account" "platform_accounts" {
  for_each     = toset(local.service_accounts)
  account_id   = each.key
  display_name = "Managed by Terraform: ${each.key}"
  project      = var.project_id

  depends_on = [google_project_service.enabled_APIs]
}
