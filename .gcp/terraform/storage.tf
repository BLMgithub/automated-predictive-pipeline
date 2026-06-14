resource "google_storage_bucket" "marketing_archival_bucket" {
  name                        = "marketing-archival-${var.environment}"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  # Move to Coldline after 400 days
  lifecycle_rule {
    condition {
      age                   = 400
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Delete after 3 years
  lifecycle_rule {
    condition {
      age = 1095
    }
    action {
      type = "Delete"
    }
  }
}
