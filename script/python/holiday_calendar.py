# =============================================================================
# SYNTHETIC HOLIDAY CALENDAR GENERATOR
# =============================================================================

import pandas as pd
from pathlib import Path
import holidays
from datetime import date, timedelta

OUTPUT_DIR = Path(__file__).resolve().parents[2] / "data"
START = date(2019, 1, 1)
END = date(2026, 12, 31)

us_holidays = holidays.US()

records = []
current = START

while current <= END:
    is_federal = current in us_holidays
    is_season = (current.month == 11 and current.day >= 15) or (current.month == 12)
    records.append(
        {
            "date": current.isoformat(),
            "is_holiday_season": is_federal or is_season,
            "is_peak_date": is_season or is_federal,
        }
    )
    current += timedelta(days=1)

df = pd.DataFrame(records)

output = OUTPUT_DIR / "holiday_calendar.csv"
df.to_csv(output, index=False)

print(f"Holiday calendar saved to {output} ({len(df)} rows)")
