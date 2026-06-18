# ------------------------------------------------------------
# DRIVE EXTRACTOR TRIGGER
# ------------------------------------------------------------

resource "google_cloud_scheduler_job" "extractor_trigger" {
  name        = "midnight-trigger-${var.environment}"
  description = "Execute drive-extractor-sa daily 12AM (PHT)"
  schedule    = "every day 12:00"
  time_zone   = "Asia/Manila"
  region      = var.region

  depends_on = [google_project_service.enabled_APIs]

  # URI to run google drive extractor job
  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/google-drive-extractor-${var.environment}:run"

    oauth_token {
      service_account_email = google_service_account.platform_accounts["extractor-orchestration-sa"].email
    }
  }
}


# ------------------------------------------------------------
# WEEKLY PREDICTION, MONTHLY RETRAIN TRIGGERS AND WORKFLOW
# ------------------------------------------------------------

resource "google_cloud_scheduler_job" "trigger_weekly_prediction" {
  name        = "weekly-prediction-trigger-${var.environment}"
  description = "Triggers dataform pipeline everyweek (Monday) 3AM (PHT)"
  schedule    = "every mon 03:00"
  time_zone   = "Asia/Manila"
  region      = var.region

  depends_on = [google_project_service.enabled_APIs, google_workflows_workflow.github_actions_dispatcher]

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.github_actions_dispatcher.name}/executions"

    oauth_token {
      service_account_email = google_service_account.platform_accounts["dataform-orchestration-sa"].email
    }

    body = base64encode(
      jsonencode(
        {
          argument = jsonencode(
            {
              project_id  = var.project_id
              github_repo = var.github_repo
              event_type  = "weekly-predict"
            }
          )
        }
      )
    )
  }
}


resource "google_cloud_scheduler_job" "trigger_monthly_retrain" {
  name        = "monthly-retrain-trigger-${var.environment}"
  description = "Triggers dataform pipeline every start of the Month (Monday) 2AM (PHT)"
  schedule    = "first monday of month 02:00"
  time_zone   = "Asia/Manila"
  region      = var.region

  depends_on = [google_project_service.enabled_APIs, google_workflows_workflow.github_actions_dispatcher]

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.github_actions_dispatcher.name}/executions"

    oauth_token {
      service_account_email = google_service_account.platform_accounts["dataform-orchestration-sa"].email
    }

    body = base64encode(
      jsonencode(
        {
          argument = jsonencode(
            {
              project_id  = var.project_id
              github_repo = var.github_repo
              event_type  = "monthly-retrain"
            }
          )
        }
      )
    )
  }
}


resource "google_workflows_workflow" "github_actions_dispatcher" {
  name            = "github-actions-dispatcher-${var.environment}"
  region          = var.region
  description     = "Triggers GitHub Actions for dataform pipeline executions"
  source_contents = file("${path.module}/../workflow/github-actions-dispatcher.yml")
  service_account = google_service_account.platform_accounts["dataform-orchestration-sa"].email

  depends_on = [google_project_service.enabled_APIs]
}
