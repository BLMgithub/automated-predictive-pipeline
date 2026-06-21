# ML Data Layer

**Purpose:** Temporally partitioned feature views that split the contract dataset into training, holdout, and live-prediction windows with lag/lead feature engineering.

## 1. DAG Position

contract/ → `ml_data/` → ml_model/

## 2. Node Inventory

| Node | Type | Schema | Description | Tags |
| :--- | :--- | :--- | :--- | :--- |
| `ml_training_data` | view | `published_dataset` | Training dataset (pre-2026) for model training | `build_pipeline` |
| `ml_holdout_data` | view | `published_dataset` | Holdout dataset (2026 weeks, excluding latest week) for model evaluation | `build_pipeline` |
| `ml_weekly_data` | view | `published_dataset` | Most recent 2026 week for live weekly prediction | `build_pipeline` |

## 3. Severity Model

- **Operational (Fatal):** Assertion violations block the view. Missing upstream `ml_core_dataset` blocks all three views.
- **Functional (Warning):** Temporal splits may produce empty views if the underlying contract data has no rows in a window downstream ML operations return empty results without hard failure.

## 4. ml_training_data

Training dataset (pre-2026) for model training.

### 4.1 Grain

One row per (`week_start`, `traffic_source`, `product_category`) inherited from `ml_core_dataset` grain. Window functions partition by `traffic_source, product_category` and order by `week_start`. The `nonNull` assertion on `traffic_source` and `product_category` reinforces the compound key.

### 4.2 Invariants

- `traffic_source`, `product_category`, `next_week_revenue_per_campaign` are non-null (assertions)
- Only pre-2026 data: `WHERE week_start < '2026-01-01'`
- `next_week_revenue_per_campaign` is the `LEAD(revenue_per_campaign, 1)` of the subsequent week within the same source-category partition
- Rows where the next week does not exist (last week per partition) are excluded via `WHERE next_week_revenue_per_campaign IS NOT NULL`
- `spend_momentum`, `revenue_momentum`, `return_rate_prev_wk`, `total_orders_prev_wk`, `fulfillment_prev_wk` are lag-1 values within each partition NULL for the first week in a partition

### 4.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | View query fails; `revenue_forecast_model` training blocked |
| No pre-2026 rows in `ml_core_dataset` | Functional | Empty training set; model training produces an empty model |

## 5. ml_holdout_data

Holdout dataset (2026 weeks, excluding latest week) for model evaluation.

### 5.1 Grain

One row per (`week_start`, `traffic_source`, `product_category`) same grain as `ml_training_data`, partitioned identically.

### 5.2 Invariants

- `traffic_source`, `product_category`, `next_week_revenue_per_campaign` are non-null (assertions)
- Only 2026 data: `WHERE week_start >= '2026-01-01'`
- The latest 2026 week is excluded because `LEAD(revenue_per_campaign, 1)` yields NULL for it, and the outer `WHERE next_week_revenue_per_campaign IS NOT NULL` filters it
- Same lag/lead feature engineering as `ml_training_data` momentum, return rate, fulfillment lags

### 5.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | View query fails; `predictions_evaluation` and `evaluation_metrics` blocked |
| No 2026 rows or only one 2026 week in `ml_core_dataset` | Functional | Empty holdout set; evaluation produces no rows |

## 6. ml_weekly_data

Most recent 2026 week for live weekly prediction.

### 6.1 Grain

One row per (`week_start`, `traffic_source`, `product_category`) filtered to the single most recent week in 2026.

### 6.2 Invariants

- `week_start`, `traffic_source`, `product_category` are non-null (assertions)
- Only the most recent 2026 week: `WHERE week_start = (SELECT MAX(week_start) FROM ml_core_dataset WHERE week_start >= '2026-01-01')`
- `next_week_revenue_per_campaign` is excluded from output (`SELECT * EXCEPT(next_week_revenue_per_campaign)`) unknown target for prediction
- Same lag-1 feature engineering as training and holdout

### 6.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | View query fails; `predictions_nextweek` blocked |
| No 2026 rows in `ml_core_dataset` | Functional | Empty view; `predictions_nextweek` produces no predictions |
