from pathlib import Path
import pandas as pd
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")
REPORT = BASE / "report"
CHARTS = BASE / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)


def fmt_float(x, _):
    if abs(x) >= 1000:
        return f"{int(x):,}".replace(",", " ")
    return f"{x:g}"


df = pd.read_csv(REPORT / "02_partitioning_measurements.csv")

test_order = {
    "first_section": 1,
    "second_section": 2,
    "first_and_second_sections": 3,
}

table_order = {
    "orders_plain": 1,
    "orders_partitioned": 2,
}

df["test_order"] = df["test_name"].map(test_order)
df["table_order"] = df["table_name"].map(table_order)
df = df.sort_values(["test_order", "table_order"])

labels = (df["test_name"] + "\n" + df["table_name"]).to_numpy()
values = df["avg_elapsed_ms"].to_numpy()

fig, ax = plt.subplots(figsize=(11, 6))
ax.bar(labels, values)

ax.set_title("Влияние секционирования на время выборки")
ax.set_xlabel("Запрос и таблица")
ax.set_ylabel("Среднее время, мс")
ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))

for label in ax.get_xticklabels():
    label.set_rotation(35)
    label.set_horizontalalignment("right")

fig.tight_layout()
fig.savefig(CHARTS / "02_partitioning.png", dpi=200)
plt.close(fig)

print("saved:", CHARTS / "02_partitioning.png")
