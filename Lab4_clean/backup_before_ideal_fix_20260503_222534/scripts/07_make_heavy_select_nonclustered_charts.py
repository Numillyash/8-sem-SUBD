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


df = pd.read_csv(REPORT / "08_heavy_select_nonclustered_measurements.csv")

order = {
    "without_index_nonclustered": 1,
    "btree_index_nonclustered": 2,
}

df["sort_key"] = df["index_state"].map(order)
df = df.sort_values(["sort_key", "rows_before"])


def make_line(y_col, ylabel, title, filename):
    fig, ax = plt.subplots(figsize=(11, 6))

    for index_state, part in df.groupby("index_state", sort=False):
        part = part.sort_values("rows_before")
        ax.plot(
            part["rows_before"].to_numpy(),
            part[y_col].to_numpy(),
            marker="o",
            label=index_state,
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
    ax.legend()

    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


make_line(
    "avg_total_elapsed_seconds",
    "Среднее время серии SELECT, с",
    "Тяжелая выборка не кластеризованных данных: общее время серии",
    "08_heavy_select_total_seconds.png",
)

make_line(
    "avg_elapsed_ms_per_select",
    "Среднее время одной выборки, мс",
    "Тяжелая выборка не кластеризованных данных: среднее время одного SELECT",
    "08_heavy_select_avg_ms.png",
)

print("saved:", CHARTS / "08_heavy_select_total_seconds.png")
print("saved:", CHARTS / "08_heavy_select_avg_ms.png")
