variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "environment" {
  description = "The environment (e.g. Dev, Staging, Production)"
  type        = string
}

variable "region" {
  description = "The Project GCP Region"
  type        = string
}

variable "dataset_location" {
  description = "The location of BigQuery dataset"
  type        = string
}

variable "github_repo" {
  description = "Github Repository (Format: owner/repository)"
  type        = string
}

variable "alert_email_map" {
  type        = map(string)
  description = "List of emails to receive pipeline alerts"
  sensitive   = true
}

variable "marketing_dataset" {
  description = "BigQuery dataset containing marketing campaign externalized tables"
  type        = string
}

variable "core_ecom_dataset" {
  description = "BigQuery dataset containing core marketing data"
  type        = string
}

variable "source_dataset" {
  description = "BigQuery dataset containing filtered views of core marketing data"
  type        = string
}

variable "contracted_dataset" {
  description = "BigQuery dataset containing contracted marketing data (from externalized and core)"
  type        = string
}

variable "published_dataset" {
  description = "BigQuery dataset containing presentation ready datasets"
  type        = string
}
