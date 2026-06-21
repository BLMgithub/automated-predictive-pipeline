# Source Layer

**Purpose:** Raw data ingestion pass-through views from `core_ecom_dataset` and external table declarations for marketing CSVs.

## 1. DAG Position

(External BigQuery tables, GCS-backed external tables) → `source/` → contract/

## 2. Node Inventory

| Node | Type | Schema | Description | Tags |
| :--- | :--- | :--- | :--- | :--- |
| `ext_campaign_registry` | declaration | `marketing_dataset` | External table backed by campaign registry CSV in GCS | `build_pipeline` |
| `ext_marketing_spend_daily` | declaration | `marketing_dataset` | External table backed by daily marketing spend CSV in GCS | `build_pipeline` |
| `raw_order_items` | view | `source_dataset` | Pass-through view of `core_ecom_dataset.order_items` | `build_pipeline` |
| `raw_orders` | view | `source_dataset` | Pass-through view of `core_ecom_dataset.orders` | `build_pipeline` |
| `raw_products` | view | `source_dataset` | Pass-through view of `core_ecom_dataset.products` | `build_pipeline` |
| `raw_users` | view | `source_dataset` | Pass-through view of `core_ecom_dataset.users` | `build_pipeline` |

## 3. Severity Model

- **Operational (Fatal):** Missing upstream BigQuery table or external GCS object breaks the node and all downstream refs.
- **Functional (Warning):** None defined at this layer all source nodes are pass-through or external references with no row-level filtering.

## 4. ext_campaign_registry

Declares an external table reference for `marketing_dataset.ext_campaign_registry`.

### 4.1 Grain

[Undetermined] external table, grain not defined within this project.

### 4.2 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| External table not found or GCS object missing | Operational | Breaks all downstream refs (`marketing_data`, `pipeline_health`) |

## 5. ext_marketing_spend_daily

Declares an external table reference for `marketing_dataset.ext_marketing_spend_daily`.

### 5.1 Grain

[Undetermined] external table, grain not defined within this project.

### 5.2 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| External table not found or GCS object missing | Operational | Breaks all downstream refs (`marketing_data`, `pipeline_health`) |

## 6. raw_order_items

Pass-through view of `core_ecom_dataset.order_items`. Exposes `order_id`, `product_id`, `created_at`, `shipped_at`, `sale_price`, `status`.

### 6.1 Grain

[Undetermined] pass-through view with no GROUP BY or assertions. Grain is defined by the upstream table.

### 6.2 Invariants

- No invariants defined no assertions, WHERE filters, or QUALIFY clauses.

### 6.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Upstream table `core_ecom_dataset.order_items` not found | Operational | Breaks `ml_core_dataset` and all downstream layers |

## 7. raw_orders

Pass-through view of `core_ecom_dataset.orders`. Exposes `order_id`, `user_id`, `num_of_item`.

### 7.1 Grain

[Undetermined] pass-through view with no GROUP BY or assertions.

### 7.2 Invariants

- No invariants defined.

### 7.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Upstream table `core_ecom_dataset.orders` not found | Operational | Breaks `ml_core_dataset` and all downstream layers |

## 8. raw_products

Pass-through view of `core_ecom_dataset.products`. Exposes `id`, `category`, `distribution_center_id`, `cost`.

### 8.1 Grain

[Undetermined] pass-through view with no GROUP BY or assertions.

### 8.2 Invariants

- No invariants defined.

### 8.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Upstream table `core_ecom_dataset.products` not found | Operational | Breaks `ml_core_dataset` and all downstream layers |

## 9. raw_users

Pass-through view of `core_ecom_dataset.users`. Exposes `id`, `traffic_source`.

### 9.1 Grain

[Undetermined] pass-through view with no GROUP BY or assertions.

### 9.2 Invariants

- No invariants defined.

### 9.3 Failure Severity

| Trigger | Severity | Impact |
| :--- | :--- | :--- |
| Upstream table `core_ecom_dataset.users` not found | Operational | Breaks `ml_core_dataset` and all downstream layers |
