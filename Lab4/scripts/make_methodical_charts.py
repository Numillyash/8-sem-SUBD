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


def save_line(df, x, y, group, title, xlabel, ylabel, filename):
    fig, ax = plt.subplots(figsize=(11, 6))

    if group is None:
        part = df.sort_values(x)
        ax.plot(part[x].to_numpy(), part[y].to_numpy(), marker="o")
    else:
        for name, part in df.groupby(group):
            part = part.sort_values(x)
            ax.plot(part[x].to_numpy(), part[y].to_numpy(), marker="o", label=str(name))
        ax.legend()

    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    apply_axis_format(ax)
    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


def save_bar(df, x, y, title, xlabel, ylabel, filename, rotation=35):
    fig, ax = plt.subplots(figsize=(11, 6))
    ax.bar(df[x].astype(str).to_numpy(), df[y].to_numpy())
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


page_growth = pd.read_csv(REPORT / "method_page_growth_measurements.csv")
partition_strict = pd.read_csv(REPORT / "method_partition_strict_measurements.csv")
series = pd.read_csv(REPORT / "method_series_measurements.csv")
final_sizes = pd.read_csv(REPORT / "method_final_table_sizes.csv")

save_line(
    page_growth,
    "rows_in_table",
    "relation_bytes",
    None,
    "Рост размера relation по страницам PostgreSQL",
    "Количество строк",
    "Размер relation, байт",
    "07_page_growth_relation.png",
)

partition_strict["label"] = partition_strict["test_name"] + "\n" + partition_strict["table_name"]
save_bar(
    partition_strict,
    "label",
    "avg_elapsed_ms",
    "Секционирование: первая секция, вторая секция, обе секции",
    "Тип запроса и таблица",
    "Среднее время, мс",
    "08_partition_strict.png",
    rotation=45,
)

select_series = series[series["operation_name"] == "select_one_random_row"].copy()
save_line(
    select_series,
    "rows_before",
    "avg_elapsed_ms",
    "index_type",
    "Выборка одной случайной записи при росте таблицы",
    "Количество строк в таблице",
    "Среднее время, мс",
    "09_select_series.png",
)

insert_series = series[series["operation_name"] == "insert_one_random_row"].copy()
save_line(
    insert_series,
    "rows_before",
    "avg_elapsed_ms",
    "index_type",
    "Вставка одной записи при росте таблицы",
    "Количество строк в таблице",
    "Среднее время, мс",
    "10_insert_series.png",
)

update_series = series[series["operation_name"] == "update_one_random_row"].copy()
save_line(
    update_series,
    "rows_before",
    "avg_elapsed_ms",
    "index_type",
    "Обновление одной записи при росте таблицы",
    "Количество строк в таблице",
    "Среднее время, мс",
    "11_update_series.png",
)

save_bar(
    final_sizes,
    "table_name",
    "indexes_bytes",
    "Размер индексных структур в финальных методических таблицах",
    "Таблица",
    "Размер индексов, байт",
    "12_method_index_sizes.png",
    rotation=45,
)

print("Methodical charts saved to:", CHARTS)
