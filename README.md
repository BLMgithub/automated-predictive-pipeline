# Automated Predictive Pipeline: ML Forecasting Lifecycle

<div align="center">

  [![CI - Dataform Pipeline](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-dataform.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-dataform.yml)
  [![CI - Infra Enforcement](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-infra.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-infra.yml)
  [![CI/CD - Data Extractor](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-cd-extract.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/ci-cd-extract.yml) 
  <br>
  [![ML - Monthly Retrain](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/monthly-retrain.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/monthly-retrain.yml)
  [![ML - Weekly Prediction](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/weekly-prediction.yml/badge.svg)](https://github.com/BLMgithub/automated-predictive-pipeline/actions/workflows/weekly-prediction.yml)

</div>

## Overview
Organizations without a reliable revenue forecast face two blind spots: marketing spend is allocated without revenue linkage, and next-week revenue is estimated manually with no governance over input quality or model performance. The pipeline produces next-week revenue predictions and exposes the drivers behind each forecast. Spend decisions can be evaluated against revenue outcomes.

## System Architecture: Trust-Gated Forecasting

![gcp-orchestration-diagram](/assets/diagram/gcp-orchestration-diagram.drawio.png)

The architecture is designed under a trust-gated forecasting rule where a prediction is not actionable until model confidence and input integrity are verified. Three constraints shape the system:

* **Weekly frequency:** Forces a daily/weekly/monthly orchestration split: extract daily, predict weekly (Mon 03:00 PHT), retrain monthly (first Mon 02:00 PHT).
* **≤10% data-loss tolerance:** Enforced by the `pipeline_health` assertion gate; row loss exceeding the threshold aborts the run before predictions are consumed.
* **Explainable / linear (not black-box):** BQML `LINEAR_REG` with feature weights published as a final table, which enables the dashboard's Explain layer.

### Lifecycle Frequency

| Frequency | Trigger | Action |
| :--- | :--- | :--- |
| Daily (00:00 PHT) | Cloud Scheduler → Cloud Run Job | Google Drive extraction to GCS |
| Weekly (Mon 03:00 PHT) | Cloud Scheduler → Cloud Workflows → GitHub Actions | Dataform `ml:predict` → `predictions_nextweek` |
| Monthly (First Mon 02:00 PHT) | Cloud Scheduler → Cloud Workflows → GitHub Actions | Dataform `ml:train` + `ml:evaluate` → model retrain + holdout evaluation |

## Model-Input Governance: Medallion to ML

![dataform-pipeline-diagram](/assets/diagram/dataform-pipeline-diagram.png)

The Dataform pipeline transforms external and core data into ML-ready datasets through a medallion architecture with assertion-gated promotion:

* **Source:** Pass-through views of core e-commerce tables and external GCS-backed CSV declarations for marketing spend.
* **Contract:** Cleaned, deduplicated, and joined datasets enforcing `nonNull` and `rowCondition` assertions. Rows violating the contract are subtractively dropped and counted in metrics. The pipeline does not repair them.
* **ML Data:** Split-by-date feature views splitting the contract dataset into training (pre-2026), holdout (2026 weeks), and live-prediction (latest week) windows with lag/lead feature engineering.
* **ML Model:** BQML model lifecycle: `CREATE OR REPLACE MODEL` training, holdout prediction comparison, and evaluation.
* **Published:** Final output tables: live predictions, feature weights, evaluation metrics, and the `pipeline_health` data-quality monitor.

### Integrity Gates

* **Contract Assertions:** `nonNull` and `rowCondition` violations block the node build. Malformed data is stopped before feature engineering.
* **Data-Loss Gate:** `pipeline_health` enforces `data_loss_percentage <= 0.10` via a `rowCondition` assertion. Row loss exceeding 10% aborts the pipeline run.
* **Grain Enforcement:** One row per `(week_start, traffic_source, product_category)`, verified by `GROUP BY` and `nonNull` assertions across contract, ML data, and published layers.

## Automated ML Lifecycle: Retrain, Evaluate, Predict

BQML linear regression producing next-week revenue forecasts at a weekly grain `(week_start, traffic_source, product_category)`; target is next-week revenue per campaign. Feature weights are published as a final table for explainability.

* **Monthly Retrain:** `CREATE OR REPLACE MODEL` on `ml_training_data` (pre-2026). No warm start. The model is rebuilt from scratch each cycle.
* **Weekly Predict:** `ML.PREDICT` on `ml_weekly_data` (latest 2026 week) → `predictions_nextweek` with point estimates.
* **Holdout Evaluate:** `ML.EVALUATE` on `ml_holdout_data` (2026 weeks excluding latest) → `evaluation_metrics` (R², RMSE, MAE, MedAE). This is the model-trust gate: evaluation results surface on the dashboard's Trust page before the forecast is consumed.

> Model hyperparameters, lag/lead feature engineering, and training specifications are documented in [`docs/dataform_pipeline/`](docs/dataform_pipeline/).

## Forecast Decision Support: Trust → Explain → Forecast

<div align="center"> 

![revenue_forecast_demo](/assets/gif/revenue_forecast_demo.gif)

</div>

The Power BI dashboard follows a **Trust → Explain → Forecast** page sequence. A forecast is not actionable until the reader verifies model health, understands driver contributions, and then consumes the live prediction through that driver lens.

### Trust (Model Confidence)
Verify the model is currently usable. Performance metrics (R², RMSE, MAE, MedAE, prediction error) are checked against realized revenue. Residual distribution, data-loss headroom, pipeline assertion status, and source freshness confirm the upstream data is intact and current. The reader does not proceed if any of these fail.

### Explain (Revenue Drivers)
Surface what drives the predicted target. Features are ranked by standardized contribution, broken down into numeric and categorical drivers. Numeric weights show per-unit dollar sensitivity; categorical weights show which levels lift or drag the forecast. This is the spend→revenue linkage: the reader uses driver contributions to decide where to allocate resources and what to deprioritize.

### Forecast (Live Prediction)
Deliver the next-week revenue number with lower and upper bounds, broken down by the same categorical features shown on the prior page. The categorical breakdown is interpreted through the driver lens. Each category is read as a contributor to the forecast.

> Explore the **[Power BI Directory](/power_bi)** for the detailed [operational guide](power_bi/docs/operational_guide.md) or download the `.pbix` [release](power_bi/releases/).

## Codified Observability

![predictive-pipeline-health-monitoring](/assets/screenshots/predictive-pipeline-health-monitoring.png)

The system health suite is fully codified via Terraform, including seven Cloud Monitoring alert policies:

* **Scheduler Failures:** CRITICAL alerts on Cloud Scheduler job failure for daily extraction, weekly prediction, and monthly retrain triggers.
* **Extractor Failures:** CRITICAL alerts on Cloud Run job ERROR logs from the extractor.
* **Workflow Failures:** CRITICAL alerts on Cloud Workflows execution ERROR for the GitHub Actions dispatcher.
* **ML Pipeline Failures:** CRITICAL alerts on GitHub Actions workflow failure for weekly predictions and monthly retrain.
* **Data-Quality Metrics:** `pipeline_health` tracks row loss, rejections, and unmapped sources, surfaced on the dashboard's Trust page.

All alert policies notify three email channels (`engineer`, `manager`, `admin`) and auto-close after 6 hours with 30-minute re-notification intervals.

## CI/CD & Security

The project adheres to a strict **Zero-Trust** deployment model.

* **Workload Identity Federation (WIF):** Authenticates GitHub Actions to Google Cloud via short-lived OIDC tokens instead of permanent service account keys.
* **Infrastructure as Code:** All GCP resources (Cloud Run, Cloud Workflows, Cloud Scheduler, BigQuery datasets, GCS buckets, IAM, monitoring) are managed via Terraform with a GCS backend for state locking.
* **Containerized Artifacts:** The extractor is packaged into a Docker image and pushed to Artifact Registry only after passing CI checks.

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