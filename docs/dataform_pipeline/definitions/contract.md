# Contract Layer

**Purpose:** Cleaned, deduplicated, and joined datasets that enforce structural guarantees before feature engineering and ML.

## 1. DAG Position

source/ → `contract/` → ml_data/

## 2. Node Inventory

| Node | Type | Schema | Description | Tags |
| :--- | :--- | :--- | :--- | :--- |
| `marketing_data` | table | `contracted_dataset` | Cleaned marketing spend joined with canonical campaign metadata at daily grain | `build_pipeline` |
| `ml_core_dataset` | table | `contracted_dataset` | Weekly feature-engineered dataset joining e-commerce, marketing, and holiday dimensions | `build_pipeline` |

## 3. Severity Model

- **Operational (Fatal):** Assertion violations (nonNull, rowConditions) block the node build. Missing upstream refs in `source/` break the node.
- **Functional (Warning):** Row-level WHERE filters exclude data without hard failure negative spend, unparseable dates, unmapped sources, and non-matching join keys all drop rows before the table materializes.

## 4. marketing_data

Cleaned marketing spend joined with canonical campaign metadata at daily grain.

### 4.1 Grain

One row per (`campaign_id`, `campaign_date`) verified by `QUALIFY ROW_NUMBER() PARTITION BY campaign_id` deduplication, `nonNull` assertions on both columns, and WHERE filters that reject NULL `campaign_date`.

### 4.2 Invariants

- `campaign_id`, `campaign_date`, `campaign_name`, `canonical_traffic_source`, `target_category`, `spend_usd` are non-null (assertions)
- `canonical_traffic_source` is one of `Search`, `Facebook`, `Email`, `Display`, `Organic` (rowCondition assertion)
- `spend_usd >= 0` (WHERE filter excludes negative spend rows)
- `campaign_date IS NOT NULL` excludes rows with unparseable dates from `normalize_date`
- `canonical_traffic_source IS NOT NULL` excludes rows with unmapped `utm_source` from `map_source`
- One registry row per `campaign_id` via `deduplicate` QUALIFY no duplicate campaign metadata

### 4.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | Node build fails; `ml_core_dataset` and all downstream nodes blocked |
| `canonical_traffic_source` rowCondition violation | Operational | Node build fails; unexpected source category detected |
| `spend_usd < 0` in source row | Functional | Row excluded from output; counted as `rejected_negative_spend` in `pipeline_health` |
| `normalize_date` returns NULL | Functional | Row excluded; counted as `rejected_unparseable_dates` in `pipeline_health` |
| `map_source` returns NULL | Functional | Row excluded; counted as `rejected_unmapped_source` in `pipeline_health` |

## 5. ml_core_dataset

Weekly feature-engineered dataset joining e-commerce, marketing, and holiday dimensions.

### 5.1 Grain

One row per (`week_start`, `traffic_source`, `product_category`) verified by `GROUP BY week_start, traffic_source, product_category` and `nonNull` assertions on `week_start`, `traffic_source`, `product_category`.

### 5.2 Invariants

- `week_start`, `traffic_source`, `product_category`, `total_revenue`, `total_spend` are non-null (assertions)
- `week_start` is a Monday via `DATE_TRUNC(event_date, WEEK(MONDAY))` consistent week boundary
- INNER JOIN on `event_date = campaign_date AND traffic_source = canonical_traffic_source AND product_category = target_category` only date-source-category combinations present in both e-commerce and marketing data survive
- Weighted averages (`avg_fulfillment_days`, `avg_items_per_order`, `avg_margin_per_item`) use `NULLIF(SUM(total_orders), 0)` to avoid division by zero
- `revenue_per_campaign` uses `SAFE_DIVIDE` with `SUM(total_campaign)` to avoid division by zero

### 5.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Any nonNull assertion violation | Operational | Node build fails; all downstream `ml_data/` views and ML operations blocked |
| No matching rows between e-commerce and marketing sides | Functional | Missing week-source-category combinations in output; downstream features may have gaps |
| Zero total_orders for a group | Functional | Weighted averages return NULL (division by zero protection) |
