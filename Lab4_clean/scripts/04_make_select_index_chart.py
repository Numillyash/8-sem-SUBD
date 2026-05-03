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


def fmt_int(x, _):
    return f"{int(x):,}".replace(",", " ")


def fmt_float(x, _):
    if abs(x) >= 1000:
        return f"{int(x):,}".replace(",", " ")
    return f"{x:g}"


df = pd.read_csv(REPORT / "03_select_index_measurements.csv")

order = {
    "without_index": 1,
    "btree_index": 2,
}

df["sort_key"] = df["index_state"].map(order)
df = df.sort_values(["sort_key", "rows_before"])

# Основной график: обе линии на одной линейной шкале
fig, ax = plt.subplots(figsize=(11, 6))

for index_state, part in df.groupby("index_state", sort=False):
    part = part.sort_values("rows_before")
    ax.plot(
        part["rows_before"].to_numpy(),
        part["avg_elapsed_ms"].to_numpy(),
        marker="o",
        label=index_state,
    )

ax.set_title("SELECT одной записи без индекса и с B-tree индексом")
ax.set_xlabel("Количество строк в таблице")
ax.set_ylabel("Среднее время одной выборки, мс")
ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
ax.legend()

fig.tight_layout()
fig.savefig(CHARTS / "03_select_index.png", dpi=200)
plt.close(fig)

# Дополнительный zoom-график только для B-tree
btree = df[df["index_state"] == "btree_index"].copy().sort_values("rows_before")

fig, ax = plt.subplots(figsize=(11, 6))

ax.plot(
    btree["rows_before"].to_numpy(),
    btree["avg_elapsed_ms"].to_numpy(),
    marker="o",
    label="btree_index",
)

ax.set_title("SELECT одной записи с B-tree индексом: увеличенный масштаб")
ax.set_xlabel("Количество строк в таблице")
ax.set_ylabel("Среднее время одной выборки, мс")
ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
ax.legend()

fig.tight_layout()
fig.savefig(CHARTS / "03_select_index_btree_zoom.png", dpi=200)
plt.close(fig)

print("saved:", CHARTS / "03_select_index.png")
print("saved:", CHARTS / "03_select_index_btree_zoom.png")
