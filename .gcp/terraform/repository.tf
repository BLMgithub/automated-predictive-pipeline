resource "google_artifact_registry_repository" "marketing_pipeline_repo" {
  repository_id = "marketing-predictive-pipeline-${var.environment}"
  description   = "Docker repository for marketing data pipeline images"
  format        = "DOCKER"
  location      = var.region
  project       = var.project_id

  depends_on = [google_project_service.enabled_APIs]
}
