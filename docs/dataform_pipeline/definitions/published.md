# Published Layer

**Purpose:** Terminal output tables live predictions, model weights, evaluation metrics, and data-quality monitoring.

## 1. DAG Position

ml_model/ → `published/` → (external consumers, dashboards)

## 2. Node Inventory

| Node | Type | Schema | Description | Tags |
| :--- | :--- | :--- | :--- | :--- |
| `predictions_nextweek` | table | `published_dataset` | Live weekly model predictions | `ml:predict` |
| `features_weights` | table | `published_dataset` | Model feature weights, showing features influence | `ml:evaluate` |
| `evaluation_metrics` | table | `published_dataset` | Model performance metrics on unseen data (evaluated on `ml_holdout_data`) | `ml:evaluate` |
| `pipeline_health` | table | `published_dataset` | Marketing pipeline data-quality monitor tracking row loss, rejections, and unmapped sources | `build_pipeline` |

## 3. Severity Model

- **Operational (Fatal):** Assertion violations block the node build. Missing model or upstream refs break the node.
- **Functional (Warning):** Empty prediction or evaluation results due to empty upstream views no hard failure, but consumer dashboards show no data.

## 4. predictions_nextweek

Live weekly model predictions.

### 4.1 Grain

One row per (`week_start`, `traffic_source`, `product_category`) verified by `GROUP BY week_start, traffic_source, product_category` and `nonNull` assertions on all columns.

### 4.2 Invariants

- `week_start`, `traffic_source`, `product_category`, `predicted_next_week_revenue` are non-null (assertions)
- `predicted_next_week_revenue` is the `SUM` of per-row `predicted_next_week_revenue_per_campaign` from `ML.PREDICT`
- `ORDER BY week_start` chronologically sorted output
- Explicit dependency on `revenue_forecast_model` ensures execution after model training

### 4.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | Table build fails; prediction consumers see no data |
| `revenue_forecast_model` not found | Operational | `ML.PREDICT` fails; table not created |
| `ml_weekly_data` is empty (no 2026 data) | Functional | Table contains zero rows; no predictions for consumers |

## 5. features_weights

Model feature weights, showing features influence.

### 5.1 Grain

One row per feature output of `ML.WEIGHTS()`, ordered by absolute weight descending.

### 5.2 Invariants

- Results ordered by `ABS(weight) DESC` most influential features appear first
- Explicit dependency on `revenue_forecast_model`

### 5.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| `revenue_forecast_model` not found | Operational | `ML.WEIGHTS` fails; table not created |

## 6. evaluation_metrics

Model performance metrics on unseen data (evaluated on `ml_holdout_data`).

### 6.1 Grain

Single row `ML.EVALUATE` returns aggregate metrics across the entire holdout set.

### 6.2 Invariants

- `ML.EVALUATE` runs against `revenue_forecast_model` using `ml_holdout_data` as input
- Explicit dependency on `revenue_forecast_model`

### 6.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| `revenue_forecast_model` not found | Operational | `ML.EVALUATE` fails; table not created |
| `ml_holdout_data` empty or missing | Operational | `ML.EVALUATE` fails; table not created |

## 7. pipeline_health

Marketing pipeline data-quality monitor tracking row loss, rejections, and unmapped sources.

### 7.1 Grain

Single row one snapshot row per execution with `CURRENT_TIMESTAMP()`.

### 7.2 Invariants

- `data_loss_percentage <= 0.10` (rowCondition assertion) row loss exceeding 10% blocks the node
- `pipeline_name` is always `'marketing_csv_ingestion'`
- `data_loss_percentage` = (raw_count - contract_count) / raw_count via `SAFE_DIVIDE`

### 7.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| `data_loss_percentage > 0.10` | Operational | Assertion fails; node build fails; pipeline run marked as failed |
| `ext_marketing_spend_daily` not found | Operational | Subquery fails; table not created |
| `marketing_data` not found | Operational | Subquery fails; table not created |
