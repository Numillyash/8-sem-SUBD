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


def save_bar(df, x, y, title, xlabel, ylabel, filename):
    fig, ax = plt.subplots(figsize=(11, 6))
    ax.bar(df[x].astype(str), df[y].to_numpy())
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_int))
    plt.xticks(rotation=35, ha="right")
    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


insert_sizes = pd.read_csv(REPORT / "04_insert_indexes_sizes.csv")
update_sizes = pd.read_csv(REPORT / "05_update_indexes_sizes.csv")
heavy_sizes = pd.read_csv(REPORT / "08_heavy_select_nonclustered_sizes.csv")

save_bar(
    insert_sizes,
    "table_name",
    "indexes_bytes",
    "Размер индексных структур после эксперимента INSERT",
    "Таблица",
    "Размер индексов, байт",
    "06_insert_index_sizes.png",
)

save_bar(
    update_sizes,
    "table_name",
    "indexes_bytes",
    "Размер индексных структур после эксперимента UPDATE",
    "Таблица",
    "Размер индексов, байт",
    "07_update_index_sizes.png",
)

save_bar(
    heavy_sizes,
    "table_name",
    "total_bytes",
    "Размер тяжелых таблиц SELECT после 50 000 000 строк",
    "Таблица",
    "Общий размер, байт",
    "09_heavy_select_table_sizes.png",
)

print("saved summary size charts")
