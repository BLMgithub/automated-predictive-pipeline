# =============================================================================
# SYNTHETIC DATA GENERATOR
# =============================================================================

import pandas as pd
import numpy as np
from faker import Faker
from datetime import datetime, timedelta
from pathlib import Path

fake = Faker()
Faker.seed(42)
np.random.seed(42)

from datetime import datetime as dt
from zoneinfo import ZoneInfo

# ------------------------------------------------------------
# CHAOS CONSTANTS AND PARAMETERS
# ------------------------------------------------------------

START_DATE = datetime(2019, 1, 9)
END_DATE = datetime(2026, 5, 29)
OUTPUT_DIR = Path(__file__).resolve().parents[2] / "data"
NUM_CAMPAIGNS = 500
DAILY_ACTIVE_RANGE = (30, 50)

# Chaos Thresholds
UNPARSABLE_DATES = 0.05  # Nulls or bad formats
NEGATIVE_SPEND = 0.02
SOURCE_DRIFT = 0.10
CATEGORY_MISMATCH = 0.03
DUPLICATION = 0.03

# Peak Dates for 10x Spend Multiplier
PEAK_DATES = [
    "2019-12-13",
    "2020-10-15",
    "2021-03-22",
    "2022-11-21",
    "2023-11-10",
    "2024-12-17",
    "2025-12-02",
    "2026-05-25",
]

# Mapping Whitelists
SOURCE_MAP = {
    "Search": ["Google_SEM", "Bing_Ads", "Search_Direct"],
    "Facebook": ["FB_Ads", "Facebook_Feed"],
    "Email": ["Newsletter_V1", "Email_Blast", "Promo_Code"],
    "Display": ["GDN_Banner", "Display_Ad_Net"],
    "Organic": ["Unknown_Blog", "Ghost_Traffic"],
}

VALID_CATEGORIES = [
    "Accessories",
    "Active",
    "Blazers & Jackets",
    "Clothing Sets",
    "Dresses",
    "Fashion Hoodies & Sweatshirts",
    "Intimates",
    "Jeans",
    "Jumpsuits & Rompers",
    "Leggings",
    "Maternity",
    "Outerwear & Coats",
    "Pants",
    "Pants & Capris",
    "Plus",
    "Shorts",
    "Skirts",
    "Sleep & Lounge",
    "Socks",
    "Socks & Hosiery",
    "Suits",
    "Suits & Sport Coats",
    "Sweaters",
    "Swim",
    "Tops & Tees",
    "Underwear",
]


# ------------------------------------------------------------
# CAMPAIGN REGISTRY CHAOS LOGIC
# ------------------------------------------------------------


def generate_registry():

    campaigns = []

    for _ in range(NUM_CAMPAIGNS):
        campaign_id = f"CMP-{fake.unique.numerify('####')}-{fake.lexify('?')}"

        # Scenario: Source Drift
        if np.random.random() < SOURCE_DRIFT:
            utm_source = "Unknown_Ext" if np.random.random() < 0.5 else "Ghost_Traffic"
        else:
            target_group = np.random.choice(list(SOURCE_MAP.keys()))
            utm_source = np.random.choice(SOURCE_MAP[target_group])

        # Scenario: Category Mismatch
        if np.random.random() < CATEGORY_MISMATCH:
            target_category = (
                "Electronics" if np.random.random() < 0.5 else "Smartwatches"
            )
        else:
            target_category = np.random.choice(VALID_CATEGORIES)

        campaigns.append(
            {
                "campaign_id": campaign_id,
                "campaign_name": fake.catch_phrase().replace(" ", "_").lower(),
                "utm_source": utm_source,
                "target_category": target_category,
            }
        )

    return pd.DataFrame(campaigns)


# ------------------------------------------------------------
# MARKETING SPEND DAILY CHAOS LOGIC
# ------------------------------------------------------------


def generate_daily_spend(registry_df):

    records = []
    current_date = START_DATE
    all_campaigns = registry_df["campaign_id"].tolist()

    while current_date <= END_DATE:

        num_active = np.random.randint(*DAILY_ACTIVE_RANGE)
        active_camps = np.random.choice(all_campaigns, num_active, replace=False)

        date_str = current_date.strftime("%Y-%m-%d")
        is_peak = date_str in PEAK_DATES

        for camp_id in active_camps:

            # Spend Logic
            base_spend = np.random.uniform(400, 800)

            # Spending x10 for peak dates
            if is_peak:
                base_spend *= 10

            # Scenario: Negative/Zero Spend
            if np.random.random() < NEGATIVE_SPEND:
                spend = -50.0 if np.random.random() < 0.5 else 0.0
            else:
                spend = round(base_spend, 2)

            clicks = int(spend * np.random.uniform(0.1, 0.5)) if spend > 0 else 0

            # Scenario: Date Decay
            rand_val = np.random.random()
            if rand_val < UNPARSABLE_DATES:
                final_date = (
                    None if rand_val < 0.02 else current_date.strftime("%m/%d/%y")
                )
            else:
                final_date = date_str

            records.append(
                {
                    "campaign_id": camp_id,
                    "date": final_date,
                    "spend_usd": spend,
                    "clicks": clicks,
                }
            )

        # Increase date per iteration
        current_date += timedelta(days=1)

    df = pd.DataFrame(records)

    # Scenario: Duplication
    dup_size = int(len(df) * DUPLICATION)
    dupes = df.sample(dup_size)

    df = pd.concat([df, dupes], ignore_index=True)

    return df


def date_suffix(file_name: str, file_ext: str) -> str:

    pht_now = dt.now(ZoneInfo("Asia/Manila"))
    today = pht_now.strftime("%Y_%m_%d")
    return f"{file_name}_{today}.{file_ext}"


# ------------------------------------------------------------
# EXECUTOR
# ------------------------------------------------------------


def main():

    registry = generate_registry()
    spend = generate_daily_spend(registry)

    registry.to_csv(OUTPUT_DIR / date_suffix("campagin_registry", "csv"), index=False)
    spend.to_csv(OUTPUT_DIR / date_suffix("marketing_spend_daily", "csv"), index=False)

    print(f"Saving synthetic data in {OUTPUT_DIR}\n")
    print(f"Campaign Registry: {len(registry)} rows")
    print(f"Marketing Daily Spend: {len(spend)} rows")


if __name__ == "__main__":
    main()
