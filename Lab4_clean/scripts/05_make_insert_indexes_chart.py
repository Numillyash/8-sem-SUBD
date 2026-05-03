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


df = pd.read_csv(REPORT / "04_insert_indexes_measurements.csv")

order = {
    "no_index": 1,
    "simple_btree": 2,
    "unique_btree": 3,
    "expression_index": 4,
    "function_index": 5,
}

df["sort_key"] = df["index_type"].map(order)
df = df.sort_values(["sort_key", "rows_base"])


def make_line(y_col, ylabel, title, filename):
    fig, ax = plt.subplots(figsize=(11, 6))

    for index_type, part in df.groupby("index_type", sort=False):
        part = part.sort_values("rows_base")
        ax.plot(
            part["rows_base"].to_numpy(),
            part[y_col].to_numpy(),
            marker="o",
            label=index_type,
        )

    ax.set_title(title)
    ax.set_xlabel("Начальное количество строк в таблице")
    ax.set_ylabel(ylabel)
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
    ax.legend()

    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


make_line(
    "avg_total_elapsed_ms",
    "Среднее время вставки пакета 1000 строк, мс",
    "INSERT 1000 строк при разных типах индексов",
    "04_insert_indexes.png",
)

make_line(
    "avg_elapsed_ms_per_row",
    "Среднее время одной вставки, мс",
    "INSERT: среднее время одной строки при разных типах индексов",
    "04_insert_indexes_per_row.png",
)

print("saved:", CHARTS / "04_insert_indexes.png")
print("saved:", CHARTS / "04_insert_indexes_per_row.png")
