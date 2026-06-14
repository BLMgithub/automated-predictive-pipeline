# ------------------------------------------------------------
# PROJECT-LEVEL BINDINGS
# ------------------------------------------------------------








# ------------------------------------------------------------
# RESOURCE-LEVEL BINDINGS (Storage & Compute)
# ------------------------------------------------------------

resource "google_storage_bucket_iam_member" "googgle_drive_extractor_access" {
  bucket = google_storage_bucket.marketing_archival_bucket.name
  member = "serviceAccount:${google_service_account.platform_accounts["drive-extractor-sa"].email}"
  role   = "roles/storage.objectAdmin"
}
