# ------------------------------------------------------------
# MARKETING DATASET (EXTERNALIZED)
# ------------------------------------------------------------

resource "google_bigquery_dataset" "marketing_dataset" {
  dataset_id = var.marketing_dataset
  location   = var.dataset_location

  delete_contents_on_destroy = false
}

locals {
  marketing_external_tables = {
    # <persist table name> = <GCS file name>
    ext_campaign_registry     = "campaign_registry"
    ext_marketing_spend_daily = "marketing_spend_daily"
  }
}

resource "google_bigquery_table" "external_marketing" {
  for_each   = local.marketing_external_tables
  dataset_id = google_bigquery_dataset.marketing_dataset.dataset_id
  table_id   = each.key

  external_data_configuration {
    autodetect    = true
    source_format = "CSV"

    csv_options {
      encoding          = "UTF-8"
      field_delimiter   = ","
      skip_leading_rows = 1
      quote             = ""
    }

    source_uris = [
      "gs://${google_storage_bucket.marketing_archival_bucket.name}/data/${each.value}_*.csv"
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}


# ------------------------------------------------------------
# CORE MARKETING DATASET
# ------------------------------------------------------------

resource "google_bigquery_dataset" "core_ecom_dataset" {
  dataset_id = var.core_ecom_dataset
  location   = var.dataset_location

  delete_contents_on_destroy = false
}

# ------------------------------------------------------------
# SOURCE DATASET
# ------------------------------------------------------------

resource "google_bigquery_dataset" "source_dataset" {
  dataset_id = var.source_dataset
  location   = var.dataset_location

  delete_contents_on_destroy = false
}

# ------------------------------------------------------------
# CONTRACTED DATASET
# ------------------------------------------------------------

resource "google_bigquery_dataset" "contracted_dataset" {
  dataset_id = var.contracted_dataset
  location   = var.dataset_location

  delete_contents_on_destroy = false
}

# ------------------------------------------------------------
# PUBLISHED DATASET
# ------------------------------------------------------------

resource "google_bigquery_dataset" "published_dataset" {
  dataset_id = var.published_dataset
  location   = var.dataset_location

  delete_contents_on_destroy = false
}
