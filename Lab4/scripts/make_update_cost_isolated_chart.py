from pathlib import Path
import pandas as pd
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4")
REPORT = BASE / "report"
CHARTS = BASE / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)


def fmt_int(x, _):
    try:
        return f"{int(x):,}".replace(",", " ")
    except Exception:
        return str(x)


def fmt_float(x, _):
    if abs(x) >= 1000:
        return f"{int(x):,}".replace(",", " ")
    return f"{x:g}"


df = pd.read_csv(REPORT / "update_cost_isolated_measurements.csv")

order = {
    "lookup_only": 1,
    "simple_btree": 2,
    "unique_btree": 3,
    "expression_index": 4,
    "function_index": 5,
}

df["sort_key"] = df["index_type"].map(order).fillna(99)
df = df.sort_values(["sort_key", "rows_before"])

fig, ax = plt.subplots(figsize=(11, 6))

for index_type, part in df.groupby("index_type", sort=False):
    part = part.sort_values("rows_before")
    ax.plot(
        part["rows_before"].to_numpy(),
        part["avg_elapsed_ms"].to_numpy(),
        marker="o",
        label=index_type,
    )

ax.set_title("UPDATE 1000 записей при росте таблицы")
ax.set_xlabel("Количество строк в таблице")
ax.set_ylabel("Среднее время, мс")
ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
ax.legend()

fig.tight_layout()
fig.savefig(CHARTS / "11_update_series.png", dpi=200)
plt.close(fig)

print("Saved:", CHARTS / "11_update_series.png")
