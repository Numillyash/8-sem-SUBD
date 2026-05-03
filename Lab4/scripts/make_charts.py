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


def apply_axis_format(ax):
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
    ax.xaxis.get_offset_text().set_visible(False)
    ax.yaxis.get_offset_text().set_visible(False)


def save_bar(df, x, y, title, xlabel, ylabel, filename, rotation=25):
    labels = df[x].astype(str).to_numpy()
    values = df[y].to_numpy()

    fig, ax = plt.subplots(figsize=(11, 6))
    ax.bar(labels, values)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.tick_params(axis="x", rotation=rotation)
    for label in ax.get_xticklabels():
        label.set_horizontalalignment("right")
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


def save_line(df, x, y, title, xlabel, ylabel, filename):
    x_values = df[x].to_numpy()
    y_values = df[y].to_numpy()

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(x_values, y_values, marker="o")
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    apply_axis_format(ax)
    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


storage = pd.read_csv(REPORT / "storage_measurements.csv")
partition = pd.read_csv(REPORT / "partition_measurements.csv")
idx_select = pd.read_csv(REPORT / "index_select_measurements.csv")
insert_update = pd.read_csv(REPORT / "insert_update_measurements.csv")
clean_update = pd.read_csv(REPORT / "clean_update_measurements.csv")
sizes = pd.read_csv(REPORT / "table_sizes.csv")

save_line(
    storage,
    "rows_in_table",
    "total_relation_bytes",
    "Рост размера таблицы при увеличении числа строк",
    "Количество строк",
    "Размер таблицы, байт",
    "01_storage_growth.png",
)

partition["label"] = partition["test_name"] + "\n" + partition["table_name"]
save_bar(
    partition,
    "label",
    "avg_elapsed_ms",
    "Влияние секционирования на время выборки",
    "Тип запроса и таблица",
    "Среднее время, мс",
    "02_partitioning_select.png",
    rotation=45,
)

save_bar(
    idx_select,
    "index_state",
    "avg_elapsed_ms",
    "Выборка по customer_id без индекса и с B-tree индексом",
    "Состояние индекса",
    "Среднее время, мс",
    "03_index_select.png",
)

insert_only = insert_update[insert_update["operation_name"] == "insert_batch"].copy()
save_bar(
    insert_only,
    "index_type",
    "avg_elapsed_ms",
    "Влияние индексов на вставку 10 000 строк",
    "Тип индекса",
    "Среднее время, мс",
    "04_insert_cost.png",
)

clean_update["label"] = clean_update["test_name"] + "\n" + clean_update["index_type"]
save_bar(
    clean_update,
    "label",
    "avg_elapsed_ms",
    "Стоимость UPDATE при разных типах индексов",
    "Тест и тип индекса",
    "Среднее время, мс",
    "05_update_cost.png",
    rotation=45,
)

save_bar(
    sizes,
    "table_name",
    "indexes_bytes",
    "Объем индексных структур",
    "Таблица",
    "Размер индексов, байт",
    "06_index_sizes.png",
    rotation=45,
)

print("Charts saved to:", CHARTS)
