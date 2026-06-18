resource "google_monitoring_notification_channel" "email" {
  for_each     = nonsensitive(var.alert_email_map)
  display_name = "Pipeline Alert - ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }
}

# Severity: CRITICAL - Opens for 6 hours w/ 30 mins interval repeats notifications
resource "google_monitoring_alert_policy" "scheduler_midnight_failure" {
  display_name = "Midnight Scheduler Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "scheduler_midnight_failed"

    condition_matched_log {
      filter = <<-EOT
				resource.type="cloud_scheduler_job"
				jsonPayload.debugInfo="URL_ERROR-ERROR_NOT_FOUND. Original HTTP response code number = 404" OR jsonPayload.debugInfo="URL_ERROR-ERROR_AUTHENTICATION. Original HTTP response code number = 401"
				resource.labels.job_id="midnight-trigger-${var.environment}"
			EOT
    }
  }
  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }
  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: Midnight Google Drive Extraction Scheduler Failed!

      **What Happened:** The `midnight-trigger-${var.environment}` Cloud Scheduler job failed to invoke the extraction workflow.

      **Impact:**
      - Daily marketing CSVs were not pulled from Google Drive.
      - Runtime `metadata.json` and `.success` flags were not written.
      - Downstream predictions will run on stale data if not resolved.

      **Troubleshooting Order:**
      1. Check Cloud Scheduler logs for the 404/401 debug info.
      2. Verify the Cloud Run job `google-drive-extractor-${var.environment}` exists and is deployed.
      3. Confirm the Scheduler SA has `roles/run.invoker` on the extractor job.
      4. Once fixed, trigger the scheduler manually or wait for the next midnight run.
      EOT
  }
}


resource "google_monitoring_alert_policy" "extractor_failure" {
  display_name = "Google Drive Extractor Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "google_drive_extractor_crashed"

    condition_matched_log {
      filter = <<-EOT
        resource.type="cloud_run_job"
        resource.labels.job_name="google-drive-extractor-${var.environment}"
        severity="ERROR"
      EOT
    }
  }

  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: Google Drive Extractor Crashed!

      **What Happened:** the `google-drive-extractor-${var.environment}` Cloud Run Job threw fatal error.

      **Impact:**
      - Marketing CSVs were not successfully pulled from Google Drive.
      - Runtime `metadata.json` and `.success` flags were not written.

      **Troubleshooting Order:**
      1. Check Cloud Run Job logs for the python tracebacks.
      2. Verify Google Drive is shared with `google-drive-extractor-${var.environment}` SA email.
      3. Once fixed, execute the job manually.
      EOT
  }
}

resource "google_monitoring_alert_policy" "scheduler_weekly_failure" {
  display_name = "Weekly Prediction Scheduler Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "scheduler_weekly_prediction_failed"

    condition_matched_log {
      filter = <<-EOT
				resource.type="cloud_scheduler_job"
				jsonPayload.debugInfo="URL_ERROR-ERROR_NOT_FOUND. Original HTTP response code number = 404" OR jsonPayload.debugInfo="URL_ERROR-ERROR_AUTHENTICATION. Original HTTP response code number = 401"
				resource.labels.job_id="weekly-prediction-trigger-${var.environment}"
			EOT
    }
  }
  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }
  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: Weekly Prediction Scheduler Failed!

      **What Happened:** The `weekly-prediction-trigger-${var.environment}` Cloud Scheduler job failed to invoke the prediction workflow.

      **Impact:**
      - Weekly revenue predictions were not generated.
      - Dashboards and downstream reports may be stale.

      **Troubleshooting Order:**
      1. Check Cloud Scheduler logs for the 404/401 debug info.
      2. Verify the target (Cloud Run job / Workflows / GitHub Actions dispatcher) exists and is deployed.
      3. Confirm the Scheduler SA has the required invoke permissions.
      4. Once fixed, trigger the scheduler manually or wait for the next weekly run.
      EOT
  }
}

resource "google_monitoring_alert_policy" "scheduler_monthly_failure" {
  display_name = "Monthly Model Retrain Cloud Scheduler Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "scheduler_monthly_retrain_failed"

    condition_matched_log {
      filter = <<-EOT
				resource.type="cloud_scheduler_job"
				jsonPayload.debugInfo="URL_ERROR-ERROR_NOT_FOUND. Original HTTP response code number = 404" OR jsonPayload.debugInfo="URL_ERROR-ERROR_AUTHENTICATION. Original HTTP response code number = 401"
				resource.labels.job_id="monthly-retrain-trigger-${var.environment}"
			EOT
    }
  }
  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }
  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: Monthly Model Retrain Cloud Scheduler Failed!

      **What Happened:** The `monthly-retrain-trigger-${var.environment}` Cloud Scheduler job failed to invoke the retrain workflow.

      **Impact:**
      - The revenue forecast model was not retrained.
      - Prediction quality may degrade over time if not addressed.

      **Troubleshooting Order:**
      1. Check Cloud Scheduler logs for the 404/401 debug info.
      2. Verify the target (Cloud Run job / Workflows / GitHub Actions dispatcher) exists and is deployed.
      3. Confirm the Scheduler SA has the required invoke permissions.
      4. Once fixed, trigger the scheduler manually or wait for the next monthly run.
      EOT
  }
}

resource "google_monitoring_alert_policy" "github_actions_dispatcher_failure" {
  display_name = "GitHub Actions Dispatcher Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "github_actions_dispatcher_failure"

    condition_matched_log {
      filter = <<-EOT
					resource.type="workflows.googleapis.com/Workflow"
					resource.labels.workflow_id="github-actions-dispatcher-${var.environment}"
					severity>=ERROR
				EOT
    }
  }
  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }
  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: GitHub Actions Dispatcher Failed!

      **What Happened:** The `github-actions-dispatcher-${var.environment}` Workflows execution encountered a fatal error.

      **Impact:**
      - The scheduled GitHub Actions workflow was not triggered.
      - Downstream pipeline stage (prediction or retrain) did not execute.

      **Troubleshooting Order:**
      1. Open Cloud Workflows executions for `github-actions-dispatcher-${var.environment}` and review the failed step.
      2. Check whether the GitHub PAT or installation token has expired.
      3. Verify the target repository and workflow file still exist and are accessible.
      4. Once fixed, trigger the workflow manually.
      EOT
  }
}


resource "google_monitoring_alert_policy" "weekly_prediction_failure" {
  display_name = "Dataform Weekly Prediction GitHub Actions Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "weekly_prediction_github_actions_failed"

    condition_matched_log {
      filter = <<-EOT
        resource.type="global"
        logName="projects/${var.project_id}/logs/github-actions-workflows"
        jsonPayload.event_type="weekly-predict"
        jsonPayload.status="failure"
      EOT
    }
  }

  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: Dataform Weekly Prediction GitHub Actions Failed

      **What Happened:** The `weekly-prediction.yml` GitHub Actions workflow reported a failure back to Cloud Logging.

      **Impact:**
      - Weekly revenue predictions were not generated.
      - Dashboards and downstream reports may be stale.

      **Troubleshooting Order:**
      1. Open the failed run: look for `jsonPayload.run_url` in the matched log entry.
      2. Check the GitHub Actions logs for Dataform compilation or execution errors.
      3. Verify BigQuery permissions for the GitHub Actions service account.
      4. Verify source data freshness in `${var.marketing_dataset}` and `${var.core_ecom_dataset}`.
      EOT
  }
}

resource "google_monitoring_alert_policy" "monthly_retrain_failure" {
  display_name = "Dataform Monthly Model Retrain GitHub Actions Failure Alert"
  combiner     = "OR"
  severity     = "CRITICAL"

  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "monthly_retrain_github_actions_failed"

    condition_matched_log {
      filter = <<-EOT
        resource.type="global"
        logName="projects/${var.project_id}/logs/github-actions-workflows"
        jsonPayload.event_type="monthly-retrain"
        jsonPayload.status="failure"
      EOT
    }
  }

  alert_strategy {
    auto_close           = "21600s"
    notification_prompts = ["OPENED"]

    notification_rate_limit {
      period = "1800s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      ## ALERT: Dataform Monthly Retrain GitHub Actions Failed

      **What Happened:** The `monthly-retrain.yml` GitHub Actions workflow reported a failure back to Cloud Logging.

      **Impact:**
      - The revenue forecast model was not retrained.
      - Prediction quality may degrade over time if not addressed.

      **Troubleshooting Order:**
      1. Open the failed run: look for `jsonPayload.run_url` in the matched log entry.
      2. Check the GitHub Actions logs for Dataform compilation or execution errors.
      3. Verify BigQuery permissions and the `ml:train` model definition.
      4. Review model quality metrics before approving a manual retrain.
      EOT
  }
}
