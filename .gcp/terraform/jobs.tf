resource "google_cloud_run_v2_job" "extractor" {
  name       = "google-drive-extract-${var.environment}"
  location   = var.region
  depends_on = [google_project_service.enabled_APIs]

  template {
    template {
      service_account = google_service_account.platform_accounts["drive-extractor-sa"].email

      # 15-minute timeout and 2 retry
      timeout     = "900s"
      max_retries = 2

      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello"

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version
    ]
  }
}
