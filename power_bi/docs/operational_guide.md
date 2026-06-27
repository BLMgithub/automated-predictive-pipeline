# Strategic & Operational Guide: Revenue Forecast Insights

## Strategic Intent
The **Revenue Forecast Insights** dashboard is a decision-support system built around a machine-learning revenue model. The page sequence is **Trust → Explain → Forecast**: verify model health, understand driver contributions, then consume the live forecast.

1.  **Trust (Model Confidence):** Establish that the model is currently usable. The reader verifies prediction performance against realized revenue and confirms the upstream data is intact and fresh. This page anchors trust before the reader moves forward; a forecast is not actionable if the model or its inputs are compromised.
2.  **Explain (Revenue Drivers):** Surface what drives the predicted target. Features are ranked by standardized contribution and broken down into numeric and categorical drivers. The reader uses this to narrow options — where to allocate resources, and what to deprioritize — based on each feature's specific contribution to next-week revenue.
3.  **Forecast (Live Prediction):** Deliver the next-week revenue number with a lower and upper bound, broken down by the same categorical features shown on the prior page. By this point the reader carries the "bias" built on the Drivers page — the categorical breakdown here is interpreted through what each driver contributes to the target, not as raw totals.

## KPI Interpretation Guide
Each page surfaces a distinct class of KPI. Interpret them as follows.

### Model Confidence Page
| KPI | How to Interpret |
| :--- | :--- |
| **R² (r2_score)** | Share of revenue variance explained by the model. Higher is better; a sharp drop relative to prior weeks signals the model is losing fit and should be retrained. |
| **RMSE (root_mean_squared_error)** | Average prediction error in dollars, penalizing large errors heavily. Compare against typical weekly revenue to gauge materiality. |
| **MAE (mean_absolute_error)** | Average absolute error in dollars. Less sensitive to outliers than RMSE; use it to read typical miss size. |
| **MedAE (median_absolute_error)** | Median absolute error. Robust to outlier weeks; a large gap between MAE and MedAE indicates a few extreme misses skewing the mean. |
| **Prediction Error (eval_prediction_error)** | Residuals as a fraction of actual revenue. A normalized misprediction rate — compare across weeks without revenue-scale distortion. |
| **Residual Bin Distribution** | Histogram of (actual − predicted) buckets. A centered, symmetric spread around zero indicates unbiased prediction; skew or heavy tails flag systematic over/under-prediction. |
| **Data Loss Headroom (viz_data_loss)** | Margin remaining against the 10% data-loss ceiling. A shrinking value means the pipeline is approaching the breach threshold; investigate upstream. |
| **Pipeline Assertions Status** | Pass/fail state of upstream data-quality assertions. Any non-pass status means the data feeding the model is suspect. |
| **Source Freshness (source_freshness_datetime)** | Last-modified time of the model output tables. If the timestamp is older than the expected refresh cadence, the forecast is stale and should not drive action. |

### Revenue Drivers Page
| KPI | How to Interpret |
| :--- | :--- |
| **Feature Rank (feature_rank)** | Position of a feature by absolute standardized weight. Rank 1 is the strongest driver; read the page top-down for priority. |
| **Standardized Weight (β)** | Scale-free coefficient comparing driver strength across features. Magnitude, not sign, determines rank; sign determines direction. |
| **Raw Weight (per-unit $)** | Dollar impact of one unit change in a numeric feature, or the categorical level's contribution. The business-readable sensitivity figure. |
| **Traffic Source Weight** | Contribution of the active traffic source level to next-week revenue. Positive/negative sign indicates whether that source lifts or drags the forecast. |
| **Product Category Weight** | Contribution of the active product category level to next-week revenue. Read the same way as traffic source weight. |

### Live Prediction Page
| KPI | How to Interpret |
| :--- | :--- |
| **Predicted Next-Week Revenue (pred_nextweek)** | The headline point forecast for next week. Read it through the driver lens from the prior page, not in isolation. |
| **Lower Bound (pred_nextweek_lowerbound)** | Pessimistic scenario. The floor the model does not expect revenue to fall below at the configured confidence level. |
| **Upper Bound (pred_nextweek_upperbound)** | Optimistic scenario. The ceiling the model does not expect revenue to exceed at the configured confidence level. |
| **Band Width (upper − lower)** | Uncertainty range. A wide band means lower forecast confidence; narrow the analysis scope or revisit model fit before committing resources to the number. |

## Reading the Driver Tooltip
The Revenue Drivers tooltips translate coefficients into plain-language business impact. The values update to whichever data point the cursor rests on.

**Numeric feature weights** — one unit of the feature, expressed in its native scale, moves next-week revenue by the raw-weight amount:
```
For every <feature unit/scale, e.g. 1 additional campaign>, predicted next-week revenue <increases/decreases by $raw_weight, e.g. increases by $0.05>.
```

**Categorical feature weights** — activating a categorical level contributes its signed weight to the forecast:
```
When Active <categorical level, e.g. Search>, contributes $<+/- weight, e.g. + 677.13> to next-week predicted revenue.
```

The unit/scale string and the "increases/decreases" direction are dynamic and change with the hovered feature. The tooltip uses business terms. The underlying coefficient mechanics are documented in [`dax_dictionary.md`](./dax_dictionary.md) under the `tooltip_numeric_weights` and `tooltip_categorical_weights` folders.

## Operational Workflow
1.  **Verify Trust — Model Confidence:** Confirm performance metrics (R², RMSE/MAE/MedAE, prediction error) are within acceptable ranges, the residual distribution is centered, data-loss headroom is healthy, assertions pass, and source freshness is current. Do not proceed if any of these fail.
2.  **Understand Drivers — Revenue Drivers:** Review the ranked feature list. Use numeric weights for per-unit sensitivity and categorical weights to see which levels lift or drag the forecast. Decide where to allocate resources and what to deprioritize.
3.  **Consume Forecast — Live Prediction:** Read the next-week revenue point estimate and its lower/upper bounds. Interpret the categorical breakdown through the driver lens established in step 2. Treat a wide band as a signal to narrow scope or revisit fit before acting.
