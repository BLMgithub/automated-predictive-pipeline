# Technical Documentation: Revenue Forecast Insights

## Technical Architecture
*   **Data Source:** Google BigQuery (`automated-predictive-pipeline.published_dataset`).
*   **Consumed Tables:** `predictions_evaluation`, `predictions_nextweek`, `features_weights`, `evaluation_metrics` (exposed in the model as `model_metrics`), `pipeline_health`, `pipeline_assertions`, and the BigQuery `__TABLES__` metadata (exposed as `model_output_freshness`).
*   **Update Logic:** Data freshness is driven by BigQuery `__TABLES__` metadata. The `model_output_freshness` query reads `last_modified_time` for `evaluation_metrics` and `predictions_nextweek`. These timestamps are exposed through the `source_freshness_datetime` measure.
*   **Storage Mode:** Import Mode (Power BI).
*   **Time Grain:** Weekly aggregation on `week_start`. Evaluation spans historical weeks; live prediction covers the upcoming week.
*   **Calendar:** The `calendar_date` table is M-derived, spanning `MIN(predictions_evaluation[week_start])` to `MAX(predictions_nextweek[week_start])`, with Year, Month, Month Name, and Week Start Date columns.

## Core Logic & Calculations

### Residual Binning & Error Quantification
The `predictions_evaluation` table carries a computed column `'residuals (bins)'` that buckets each residual into $100-width intervals:
- Positive residuals round **down** to the nearest 100; negative residuals round **up**. This keeps zero-centered distribution visually centered and avoids a bucket straddling the axis.
- The `residual_bin_count` measure counts rows in the selected bucket, and `eval_prediction_error` normalizes aggregate residuals by actual revenue for cross-week comparison independent of revenue scale.

### Feature Ranking by Standardized Weight
Driver ranking uses absolute standardized coefficients (β) rather than raw weights so features on different scales stay comparable:
- `abs_std_weight` sums `ABS(standard_weight)` under `KEEPFILTERS` to respect the active filter context.
- `feature_rank` applies `RANKX(..., Dense)` over `ALLSELECTED(features_weights[feature])` and returns `BLANK()` outside feature granularity, so the rank renders only at the feature level.

### Unit-Impact Sensitivity System
The numeric-feature tooltip is a coordinated set of four measures that converts a coefficient into a business-readable sensitivity:
- `delta` and `delta_label` are per-feature hardcoded unit scales — `0.01` for rate features (return rate), `0.1` for momentum ratios, `1` for counts and dollar margins. They keep the unit anchored to the feature's native scale.
- `raw_weight` is the selected feature's per-unit dollar coefficient.
- `context_effect = raw_weight × delta` produces the dollar impact of one unit change.
- `impact_direction` supplies the "increases by $/decreases by $" phrasing from the sign of `raw_weight`.

### Numeric vs Categorical Feature Separation
The `features_weights` table marks each feature as `numeric` or categorical. Driver logic splits on this:
- `numeric_weights` filters `category = "numeric"` to pool per-unit coefficients.
- Categorical drivers (`traffic_source`, `product_category`) are isolated by feature name via dedicated `_numeric_weight` measures, then rendered with signed display strings (`viz_traffic_source`, `viz_product_category`) that prefix "+" when the contribution is positive.

### Data Integrity Monitoring
Pipeline integrity is tracked independently of model performance:
- `viz_data_loss` computes headroom against a 10% ceiling (`0.1 − data_loss_percentage`). It shows the margin remaining before the pipeline breaches its loss threshold.
- `pipeline_assertions` surfaces upstream data-quality pass/fail status and flagged row counts.
- `source_freshness_datetime` exposes the `__TABLES__`-derived last-modified time so stale output is detectable before it drives a decision.

## DAX Data Dictionary
*(See [`dax_dictionary.md`](./dax_dictionary.md) for full expressions)*

### Measures Group: pred_evaluation
| **Measure Name** | Description |
| --- | --- |
| **actual_next_week** | Sum of realized next-week revenue; ground truth for evaluation. |
| **pred_next_week** | Sum of predicted next-week revenue for the evaluation period. |
| **model_residuals** | Aggregate prediction error with sign preserved. |

### Measures Group: tooltip_model_confidence
| **Measure Name** | Description |
| --- | --- |
| **eval_prediction_error** | Residuals normalized by actual revenue; cross-week error rate. |
| **selected_date** | Formatted week-start date for the selected evaluation week. |
| **selected_bin_size** | Currently selected residual-bin label. |
| **residual_bin_count** | Count of evaluation rows in the selected residual bin. |

### Measures Group: revenue_drivers
| **Measure Name** | Description |
| --- | --- |
| **abs_std_weight** | Sum of absolute standardized coefficients; ranking basis. |
| **numeric_weights** | Sum of raw coefficients restricted to numeric features. |
| **feature_rank** | Dense rank by absolute standardized weight; feature-level only. |
| **traffic_source_numeric_weight** | Raw coefficient sum for the traffic_source feature. |
| **product_category_numeric_weight** | Raw coefficient sum for the product_category feature. |

### Measures Group: tooltip_numeric_weights
| **Measure Name** | Description |
| --- | --- |
| **impact_direction** | "increases/decreases by $" label from raw-weight sign. |
| **delta** | Per-feature numeric unit scale (0.01, 0.1, or 1). |
| **delta_label** | Plain-language unit-scale description per feature. |
| **context_effect** | Dollar impact of one unit change; `raw_weight × delta`. |
| **raw_weight** | Selected feature's per-unit dollar coefficient. |
| **standardized_weight** | Selected feature's standardized coefficient (β). |

### Measures Group: tooltip_categorical_weights
| **Measure Name** | Description |
| --- | --- |
| **traffic_source_label** | Active category label for the traffic_source feature. |
| **product_category_label** | Active category label for the product_category feature. |

### Measures Group: live_prediction
| **Measure Name** | Description |
| --- | --- |
| **pred_nextweek** | Sum of predicted next-week revenue for the live horizon. |
| **pred_nextweek_lowerbound** | Sum of the prediction interval lower bound. |
| **pred_nextweek_upperbound** | Sum of the prediction interval upper bound. |

### Measures Group: visualizations
| **Measure Name** | Description |
| --- | --- |
| **viz_data_loss** | Headroom against the 10% data-loss ceiling. |
| **viz_traffic_source** | Signed display string for traffic_source contribution. |
| **viz_product_category** | Signed display string for product_category contribution. |
| **feature_weights_beta_weight** | "β = …" coefficient label string. |
| **source_freshness_datetime** | Formatted last-modified timestamp of model output tables. |
