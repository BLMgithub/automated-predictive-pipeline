# ML Model Layer

**Purpose:** BQML model lifecycle training, prediction comparison, and evaluation of the revenue forecast model.

## 1. DAG Position

ml_data/ → `ml_model/` → published/

## 2. Node Inventory

| Node | Type | Schema | Description | Tags |
| :--- | :--- | :--- | :--- | :--- |
| `revenue_forecast_model` | operations | `published_dataset` | BQML LINEAR_REG training on `ml_training_data` to forecast `revenue_per_campaign` | `ml:train` |
| `predictions_evaluation` | table | `published_dataset` | Model predictions evaluation on holdout set joined with actuals for comparison | `ml:evaluate` |

## 3. Severity Model

- **Operational (Fatal):** Model creation failure blocks all downstream `ML.PREDICT`, `ML.EVALUATE`, and `ML.WEIGHTS` calls. Assertion violations block `predictions_evaluation`.
- **Functional (Warning):** Model training completes but produces poor fit downstream predictions are low-quality without a hard failure.

## 4. revenue_forecast_model

BQML LINEAR_REG training on `ml_training_data` to forecast `revenue_per_campaign`.

### 4.1 Model Specification

| Attribute | Value |
| :--- | :--- |
| Model type | `LINEAR_REG` |
| Input label | `next_week_revenue_per_campaign` |
| Source dataset | `ml_training_data` (all columns except `week_start`) |
| Data split | `NO_SPLIT` (no internal train/test split) |
| L1 regularization | 0.1 |
| L2 regularization | 0.1 |
| Max iterations | 20 |
| Early stopping | `true` |
| Min relative progress | 0.01 |
| Initial learn rate | 0.1 (line search) |
| Warm start | `false` |

### 4.2 Invariants

- Model is created or replaced on every execution (`CREATE OR REPLACE MODEL`) no incremental training
- Training excludes `week_start` from the feature set
- `hasOutput: false` no output table is materialized; the model artifact is the only output

### 4.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Model creation fails (e.g., empty training data, invalid schema) | Operational | All downstream `ML.PREDICT`, `ML.EVALUATE`, `ML.WEIGHTS` calls fail |
| Model trains but produces zero or near-zero feature weights | Functional | Predictions degrade to constant baseline; not detected by pipeline |

## 5. predictions_evaluation

Model predictions evaluation on holdout set joined with actuals for comparison.

### 5.1 Grain

One row per (`week_start`, `traffic_source`, `product_category`) verified by `GROUP BY week_start, traffic_source, product_category` and `nonNull` assertions on all three columns plus prediction and actual columns.

### 5.2 Invariants

- `week_start`, `traffic_source`, `product_category`, `prediction_next_week_revenue`, `actual_next_week_revenue` are non-null (assertions)
- Predictions and actuals are aggregated by `SUM` after `ML.PREDICT` aligns with the per-campaign revenue metric
- `ORDER BY week_start` output is chronologically sorted
- Explicit dependency on `revenue_forecast_model` enforces execution after model training

### 5.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | Table build fails; downstream consumers cannot compare predictions to actuals |
| `revenue_forecast_model` not found | Operational | `ML.PREDICT` fails; table not created |
| `ml_holdout_data` is empty | Functional | Table contains zero rows; evaluation is skipped |
