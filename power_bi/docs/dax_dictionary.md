# DAX Data Dictionary: Revenue Forecast Insights

### <ins>Display Folder - pred_evaluation</ins>
*Evaluation-period aggregates pairing model predictions against realized revenue. Foundational inputs for the Model Confidence page — residual and error logic depend on these.*

- Measure Name: **`actual_next_week`**
- Description: *Sum of realized next-week revenue across the evaluation set; the ground truth used to score prediction accuracy.*
    ```dax
    SUM(predictions_evaluation[actual_next_week_revenue])
    ```

<br>

- Measure Name: **`pred_next_week`**
- Description: *Sum of next-week revenue the model predicted for the evaluation period; paired against `actual_next_week` to derive residuals.*
    ```dax
    SUM(predictions_evaluation[prediction_next_week_revenue])
    ```

<br>

- Measure Name: **`model_residuals`**
- Description: *Aggregate prediction error (actual − predicted) across evaluation rows. Sign is preserved so over- and under-prediction remain distinguishable.*
    ```dax
    SUM(predictions_evaluation[residuals])
    ```

<br>

---

<br>

### <ins>Display Folder - tooltip_model_confidence</ins>
*Context measures powering the Model Confidence hover surfaces. They translate the selected evaluation week and residual bin into readable diagnostics.*

- Measure Name: **`eval_prediction_error`**
- Description: *Prediction error normalized by actual revenue. Expresses aggregate misprediction as a fraction of truth, enabling cross-week comparison independent of revenue scale.*
    ```dax
    DIVIDE([model_residuals], [actual_next_week], BLANK())
    ```

<br>

- Measure Name: **`selected_date`**
- Description: *Formatted week-start date for the currently selected evaluation week; used as the tooltip header to anchor diagnostics in time.*
    ```dax
    FORMAT(SELECTEDVALUE(calendar_date[Week Start Date]), "MMMM - DD")
    ```

<br>

- Measure Name: **`selected_bin_size`**
- Description: *Currently selected residual-bin label; identifies which histogram bucket the user is inspecting.*
    ```dax
    SELECTEDVALUE(predictions_evaluation[residuals (bins)])
    ```

<br>

- Measure Name: **`residual_bin_count`**
- Description: *Count of evaluation rows falling into the currently selected residual bin; the frequency behind each histogram bar.*
    ```dax
    COUNT(predictions_evaluation[residuals])
    ```

<br>

---

<br>

### <ins>Display Folder - revenue_drivers</ins>
*Feature-contribution logic for the Revenue Drivers page. Standardized coefficients drive ranking; raw coefficients isolate numeric and categorical drivers for explainability.*

- Measure Name: **`abs_std_weight`**
- Description: *Sum of absolute standardized coefficients (β) for features in scope. This is the magnitude basis used to rank drivers on a scale-free footing.*
    ```dax
    SUMX(
        KEEPFILTERS(features_weights),
        ABS(features_weights[standard_weight])
    )
    ```

<br>

- Measure Name: **`numeric_weights`**
- Description: *Sum of raw (unit) coefficients restricted to numeric-category features. This is the pool of per-unit dollar impacts available for numeric drivers.*
    ```dax
    CALCULATE(
        SUMX(features_weights, (features_weights[raw_weight])),
        features_weights[category] = "numeric"
    )
    ```

<br>

- Measure Name: **`feature_rank`**
- Description: *Dense rank of the in-scope feature by absolute standardized weight. Returns blank outside feature granularity so the rank only renders at the feature level.*
    ```dax
    IF(
        ISINSCOPE(features_weights[feature]),
        RANKX(
            ALLSELECTED(features_weights[feature]),
            [abs_std_weight],
            ,
            DESC,
            Dense
        ),
        BLANK()
    )
    ```

<br>

- Measure Name: **`traffic_source_numeric_weight`**
- Description: *Raw coefficient sum filtered to the `traffic_source` feature; isolates that categorical driver's contribution to next-week revenue.*
    ```dax
    CALCULATE(
        SUMX(
            features_weights,
            (features_weights[raw_weight])
        ),
        features_weights[feature] = "traffic_source"
    )
    ```

<br>

- Measure Name: **`product_category_numeric_weight`**
- Description: *Raw coefficient sum filtered to the `product_category` feature; isolates that categorical driver's contribution to next-week revenue.*
    ```dax
    CALCULATE(
        SUMX(
            features_weights,
            (features_weights[raw_weight])
        ),
        features_weights[feature] = "product_category"
    )
    ```

<br>

---

<br>

### <ins>Display Folder - tooltip_numeric_weights</ins>
*Unit-impact sensitivity system for numeric features. The measures below act as a coordinated set: `delta` and `delta_label` hardcode the per-feature unit scale, `raw_weight` supplies the dollar coefficient, and `context_effect` multiplies them to yield the dollar impact of one unit change.*

- Measure Name: **`impact_direction`**
- Description: *Direction label derived from the sign of the selected feature's raw weight. Drives the "increases by $" / "decreases by $" phrasing in the tooltip.*
    ```dax
    IF(SELECTEDVALUE(features_weights[raw_weight]) >= 0, "increases by $", "decreases by $")
    ```

<br>

- Measure Name: **`delta`**
- Description: *Numeric unit scale paired to each feature. Hardcoded per feature: `0.01` for rate features, `0.1` for momentum ratios, `1` for counts and dollar margins. Multiplied by `raw_weight` to produce `context_effect`.*
    ```dax
    SWITCH(
        SELECTEDVALUE(features_weights[feature]),
        "return_rate_prev_wk",     0.01,
        "revenue_momentum",        0.1,
        "spend_momentum",          0.1,
        "avg_fulfillment_days",    1,
        "avg_items_per_order",     1,
        "avg_margin_per_item",     1,
        "revenue_per_campaign",    1,
        "total_campaign",          1,
        "total_orders",            1,
        "total_orders_prev_wk",    1,
        "total_returned",          1,
        1
    )
    ```

<br>

- Measure Name: **`delta_label`**
- Description: *Human-readable unit-scale description for the selected feature. Pairs with `delta` so the tooltip surfaces a plain-language unit ("1 additional fulfillment day") alongside the dollar impact.*
    ```dax
    SWITCH(
        SELECTEDVALUE(features_weights[feature]),
        "return_rate_prev_wk",     "1 percentage point increase in return rate (0.01)",
        "revenue_momentum",        "10% revenue momentum increase (ratio +0.1)",
        "spend_momentum",          "10% spend momentum increase (ratio +0.1)",
        "avg_fulfillment_days",    "1 additional fulfillment day",
        "avg_items_per_order",     "1 additional item per order",
        "avg_margin_per_item",     "$1 additional margin per item",
        "revenue_per_campaign",    "$1 additional revenue per campaign",
        "total_campaign",          "1 additional campaign",
        "total_orders",            "1 additional order",
        "total_orders_prev_wk",    "1 additional order last week",
        "total_returned",          "1 additional return",
        "1 unit"
    )
    ```

<br>

- Measure Name: **`context_effect`**
- Description: *Dollar impact of one unit change in the selected feature, computed as `raw_weight × delta`. Converts the coefficient into a business-readable sensitivity.*
    ```dax
    SELECTEDVALUE(features_weights[raw_weight]) * [delta]
    ```

<br>

- Measure Name: **`raw_weight`**
- Description: *Selected feature's raw (unit) coefficient; the per-unit dollar contribution. Drives the direction label and the impact magnitude in the tooltip.*
    ```dax
    SELECTEDVALUE(features_weights[raw_weight])
    ```

<br>

- Measure Name: **`standardized_weight`**
- Description: *Selected feature's standardized coefficient (β); the scale-free contribution used for cross-feature ranking on the Revenue Drivers page.*
    ```dax
    SELECTEDVALUE(features_weights[standard_weight])
    ```

<br>

---

<br>

### <ins>Display Folder - tooltip_categorical_weights</ins>
*Label measures surfacing the active categorical level under hover for the two categorical drivers.*

- Measure Name: **`traffic_source_label`**
- Description: *Category label for the traffic_source feature under hover; surfaces the active categorical level (e.g., "Search").*
    ```dax
    SELECTEDVALUE(features_weights[category])
    ```

<br>

- Measure Name: **`product_category_label`**
- Description: *Category label for the product_category feature under hover; surfaces the active categorical level (e.g., "Electronics").*
    ```dax
    SELECTEDVALUE(features_weights[category])
    ```

<br>

---

<br>

### <ins>Display Folder - live_prediction</ins>
*Forecast output for the Live Prediction page. The point estimate is bracketed by a prediction interval so the reader sees both the expected revenue and its uncertainty band.*

- Measure Name: **`pred_nextweek`**
- Description: *Sum of next-week revenue predicted by the model for the live forecast horizon; the headline forecast value.*
    ```dax
    SUM(predictions_nextweek[predicted_next_week_revenue])
    ```

<br>

- Measure Name: **`pred_nextweek_lowerbound`**
- Description: *Sum of the prediction interval lower bound; the pessimistic revenue scenario for next week.*
    ```dax
    SUM(predictions_nextweek[expected_lower_bound])
    ```

<br>

- Measure Name: **`pred_nextweek_upperbound`**
- Description: *Sum of the prediction interval upper bound; the optimistic revenue scenario for next week.*
    ```dax
    SUM(predictions_nextweek[expected_upper_bound])
    ```

<br>

---

<br>

### <ins>Display Folder - visualizations</ins>
*Cross-page UX helpers. Signed contribution strings, the β label, the data-loss headroom gauge, and the source-freshness timestamp.*

- Measure Name: **`viz_data_loss`**
- Description: *Computed margin against a 10% data-loss ceiling (`0.1 − data_loss_percentage`). Visualizes the headroom remaining before the pipeline breaches its integrity threshold.*
    ```dax
    0.1 - VALUES(pipeline_health[data_loss_percentage])
    ```

<br>

- Measure Name: **`viz_traffic_source`**
- Description: *Signed display string for the traffic_source contribution; prefixes "+" when positive for at-a-glance direction reading.*
    ```dax
    IF(
        [traffic_source_numeric_weight] > 0,
        CONCATENATE("+", ROUND([traffic_source_numeric_weight], 2)),
        [traffic_source_numeric_weight]
    )
    ```

<br>

- Measure Name: **`viz_product_category`**
- Description: *Signed display string for the product_category contribution; prefixes "+" when positive for at-a-glance direction reading.*
    ```dax
    IF(
        [product_category_numeric_weight] > 0,
        CONCATENATE("+", ROUND([product_category_numeric_weight], 2)),
        [product_category_numeric_weight]
    )
    ```

<br>

- Measure Name: **`feature_weights_beta_weight`**
- Description: *Concatenated "β = …" string for the in-scope feature's standardized coefficient; a tooltip-ready coefficient label for readers comparing relative driver strength.*
    ```dax
    CONCATENATE("β = ",
        ROUND(
            SUMX(features_weights, (features_weights[standard_weight])),
            2
        )
    )
    ```

<br>

- Measure Name: **`source_freshness_datetime`**
- Description: *Formatted last-modified timestamp of the upstream model output tables; signals data currency so the reader can confirm the forecast is not stale before acting on it.*
    ```dax
    FORMAT(SELECTEDVALUE(model_output_freshness[last_modified_time]), "YYYY/MM/DD HH:MM:SS AM/PM")
    ```
