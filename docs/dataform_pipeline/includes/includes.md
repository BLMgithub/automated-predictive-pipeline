# Includes Registry

**Purpose:** Shared JavaScript utilities for Dataform nodes. Provides source classification, deduplication, date normalization, and source-validation functions used across the `contract` and `published` layers.

## 1. map_source

Generates a SQL `CASE` expression that maps raw UTM source strings to canonical traffic source categories (Search, Facebook, Email, Display, Organic). Returns NULL for unrecognized sources.

### Source Mappings

| Source Value | Canonical Category |
| :--- | :--- |
| `google_sem`, `bing_ads`, `search_direct` | Search |
| `fb_ads`, `facebook_feed` | Facebook |
| `newsletter_v1`, `email_blast`, `promo_code` | Email |
| `gdn_banner`, `display_ad_net` | Display |
| `unknown_blog`, `ghost_traffic` | Organic |
| *(anything else)* | `NULL` |

### Internal Helpers

- `search_list()` — returns `["google_sem", "bing_ads", "search_direct"]`
- `facebook_list()` — returns `["fb_ads", "facebook_feed"]`
- `email_list()` — returns `["newsletter_v1", "email_blast", "promo_code"]`
- `display_list()` — returns `["gdn_banner", "display_ad_net"]`
- `organic_list()` — returns `["unknown_blog", "ghost_traffic"]`
- `format_list(list)` — converts a JS array to a SQL-safe quoted, comma-separated string

### Usage

| Node | Layer | Purpose |
| :--- | :--- | :--- |
| `marketing_data` | contract | Maps `utm_source` to `canonical_traffic_source` in campaign registry CTE |

## 2. deduplicate

Generates a SQL `QUALIFY` clause using `ROW_NUMBER() OVER(PARTITION BY id_col ORDER BY order_col DESC) = 1` to deduplicate rows.

### Usage

| Node | Layer | Purpose |
| :--- | :--- | :--- |
| `marketing_data` | contract | Deduplicates campaign registry on `campaign_id` ordered by `target_category` |

## 3. normalize_date

Generates a SQL `COALESCE` expression that attempts to parse a date column through three formats in order: `%Y-%m-%d`, `%m/%d/%y`, `%m/%d/%Y`. Uses `SAFE.PARSE_DATE` so that unparseable values return NULL instead of throwing errors.

### Usage

| Node | Layer | Purpose |
| :--- | :--- | :--- |
| `marketing_data` | contract | Normalizes raw `date` column in marketing spend to proper DATE type |
| `pipeline_health` | published | Counts rows where date normalization produces NULL (rejected unparseable dates) |

## 4. known_sources

Returns the concatenated array of all source values from the five source-list helper functions (15 total values). Every source classified by `map_source` is included.

### Usage

Not called directly by any node. Used internally by `is_known_source`.

## 5. is_known_source

Generates a SQL boolean expression `LOWER(col) IN (...)` that returns true when the column value matches any of the 15 known source values. Used to identify rows with unmapped traffic sources.

### Usage

| Node | Layer | Purpose |
| :--- | :--- | :--- |
| `pipeline_health` | published | Counts spend rows whose campaign UTM source is not in the known catalog (rejected unmapped source) |
