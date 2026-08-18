<div align="center">

  [![CI - Dataform Pipeline](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-dataform.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-dataform.yml)
  [![CI - Infra Enforcement](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-infra.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-infra.yml)
  [![CI/CD - Data Extractor](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-cd-extract.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-cd-extract.yml) 
  <br>
  [![ML - Monthly Retrain](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/monthly-retrain.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/monthly-retrain.yml)
  [![ML - Weekly Prediction](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/weekly-prediction.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/weekly-prediction.yml)

</div>

## System Design: Trust-Gated Forecasting

Google Cloud + Dataform + BQML produce weekly next-week-revenue forecasts, gated on model confidence and input integrity.

### Medallion to Machine Learning

Rows violating the contract are subtractively dropped and counted in metrics; the pipeline does not repair them.

![dataform-pipeline-diagram](/assets/diagram/dataform-pipeline-diagram.png)

The Dataform pipeline transforms external and core data into ML-ready datasets through a medallion architecture with assertion-gated promotion:

* **Source:** Pass-through views of core e-commerce tables; external GCS-backed CSV declarations for marketing spend.
* **Contract:** Cleans, deduplicates, and joins. `nonNull` and `rowCondition` violations drop rows and count in metrics.
* **ML Data:** Split-by-date feature views: training (pre-2026), holdout (2026 weeks), live prediction (latest week), with lag/lead feature engineering.
* **ML Model:** BQML lifecycle: `CREATE OR REPLACE MODEL` training, holdout prediction comparison, evaluation.
* **Published:** Final output tables: live predictions, feature weights, evaluation metrics, `pipeline_health` data-quality monitor.

### Serverless Infrastructure and Orchestration

![gcp-orchestration-diagram](/assets/diagram/gcp-orchestration-diagram.drawio.png)

* **Frequency split:** Maps each stage to a schedule: daily extract, weekly predict, monthly retrain.

| Frequency | Trigger | Action |
| :--- | :--- | :--- |
| Daily (00:00 PHT) | Cloud Scheduler → Cloud Run Job | Google Drive extraction to GCS |
| Weekly (Mon 03:00 PHT) | Cloud Scheduler → Cloud Workflows → GitHub Actions | Dataform `ml:predict` → `predictions_nextweek` |
| Monthly (First Mon 02:00 PHT) | Cloud Scheduler → Cloud Workflows → GitHub Actions | Dataform `ml:train` + `ml:evaluate` → model retrain + holdout evaluation |

### Integrity Gates and Delivery

* **Contract Assertions:** `nonNull` and `rowCondition` violations block the node build before feature engineering.
* **Data-Loss Gate:** `pipeline_health` enforces `data_loss_percentage <= 0.10` via a `rowCondition` assertion; row loss above 10% aborts the run.
* **Grain Enforcement:** One row per `(week_start, traffic_source, product_category)`, verified by `GROUP BY` and `nonNull` assertions across contract, ML data, and published layers.
* **Stage Promotion:** Assertion-gated; `predictions_nextweek` publishes weekly via `ml:predict`.

### BQML Model Lifecycle

Linear regression forecasting next-week revenue per campaign at grain `(week_start, traffic_source, product_category)`.

* **Model:** BQML `LINEAR_REG`; feature weights publish as a final table feeding the dashboard Explain layer.
* **Monthly Retrain:** `CREATE OR REPLACE MODEL` on `ml_training_data` (pre-2026). Rebuilt from scratch each cycle; no warm start.
* **Weekly Predict:** `ML.PREDICT` on `ml_weekly_data` (latest 2026 week) → `predictions_nextweek` with point estimates.
* **Holdout Evaluate:** `ML.EVALUATE` on `ml_holdout_data` (2026 weeks excluding latest) → `evaluation_metrics` (R², RMSE, MAE, MedAE). This is the model-trust gate: evaluation results surface on the dashboard Trust page before the forecast is consumed.

> Hyperparameters, lag/lead feature engineering, and training specifications: [`docs/dataform_pipeline/`](docs/dataform_pipeline/)

## System Health & Observability

![predictive-pipeline-health-monitoring](/assets/screenshots/predictive-pipeline-health-monitoring.png)

Fully codified via Terraform: seven Cloud Monitoring alert policies.

* **Scheduler Failures:** CRITICAL on Cloud Scheduler job failure for daily extraction, weekly prediction, and monthly retrain triggers.
* **Extractor Failures:** CRITICAL on Cloud Run job ERROR logs from the extractor.
* **Workflow Failures:** CRITICAL on Cloud Workflows execution ERROR for the GitHub Actions dispatcher.
* **ML Pipeline Failures:** CRITICAL on GitHub Actions workflow failure for weekly predictions and monthly retrain.
* **Data-Quality Metrics:** `pipeline_health` tracks row loss, rejections, and unmapped sources; surfaced on the dashboard Trust page.
* **Automated Responders:** All policies notify three email channels (`engineer`, `manager`, `admin`); auto-close after 6 hours, re-notify every 30 minutes.

## Operational Intelligence

The dashboard follows a Trust → Explain → Forecast page sequence.

![revenue_forecast_demo](/assets/gif/revenue_forecast_demo.gif)

* **Trust:** Model health: R², RMSE, MAE, MedAE, prediction error against realized revenue, residual distribution, data-loss headroom, assertion status, source freshness.
* **Explain:** Driver contributions: features ranked by standardized contribution; numeric weights show per-unit dollar sensitivity, categorical weights show level lift or drag.
* **Forecast:** Next-week revenue with lower and upper bounds, broken down by the categorical features from Explain.

> [Power BI directory](/power_bi): [operational guide](power_bi/docs/operational_guide.md), [`.pbix` releases](power_bi/releases/).

## CI/CD & Security

Zero-Trust deployment model.

* **Workload Identity Federation (WIF):** GitHub Actions authenticate to Google Cloud via short-lived OIDC tokens; no permanent service account keys.
* **Infrastructure as Code:** All GCP resources (Cloud Run, Cloud Workflows, Cloud Scheduler, BigQuery datasets, GCS buckets, IAM, monitoring) managed via Terraform with a GCS backend for state locking.
* **Containerized Artifacts:** Extractor packaged into a Docker image; pushed to Artifact Registry only after CI checks pass.

## Repository Structure

```
automated-predictive-pipeline/
├── .gcp/
│   ├── terraform/            # IaC for all GCP resources (Cloud Run, Workflows, Scheduler, BigQuery, Storage, IAM, Monitoring)
│   └── workflow/             # Cloud Workflows definition (GitHub Actions dispatcher)
├── .github/
│   └── workflows/            # CI/CD pipelines (Dataform CI, Infra enforcement, Extractor CI/CD, Monthly retrain, Weekly prediction)
├── data_extractor/
│   ├── shared/               # Extractor logic and I/O adapters
│   ├── test/                 # Pytest suite for extractor logic
│   ├── run_extract.py        # The Drive extractor orchestrator
│   └── Dockerfile            # Container image definition
├── definitions/
│   ├── contract/             # Cleaned and joined contract tables
│   ├── ml_data/              # Split-by-date feature views (train/holdout/weekly)
│   ├── ml_model/             # BQML model training and evaluation
│   ├── published/            # Final output tables (predictions, weights, metrics, health)
│   └── source/               # Pass-through views and external table declarations
├── includes/
│   └── registry.js           # Shared JavaScript utilities (source mapping, dedup, date normalization)
├── docs/                     # Technical documentation (data_extract, dataform_pipeline, terraform)
├── script/                   # Utility scripts (Synthetic data scripts, SQL validation queries)
├── power_bi/
│   ├── .shared/              # Global BI assets (themes, M queries, assets)
│   ├── dashboards/           # Source control (PBIP)
│   ├── docs/                 # Operational guide, DAX dictionary, technical architecture
│   └── releases/             # Deliverables (PBIX)
└── data/                     # Local test data (marketing CSVs, holiday calendar)
```
