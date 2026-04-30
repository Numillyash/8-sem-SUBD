from pathlib import Path
import pandas as pd
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4")
REPORT = BASE / "report"
CHARTS = BASE / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)


def save_line(df, x, y, group, title, xlabel, ylabel, filename, logx=False):
    plt.figure(figsize=(11, 6))

    if group is None:
        plt.plot(df[x].to_numpy(), df[y].to_numpy(), marker="o")
    else:
        for name, part in df.groupby(group):
            part = part.sort_values(x)
            plt.plot(part[x].to_numpy(), part[y].to_numpy(), marker="o", label=str(name))
        plt.legend()

    plt.title(title)
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)

    if logx:
        plt.xscale("log")

    plt.tight_layout()
    plt.savefig(CHARTS / filename, dpi=200)
    plt.close()


def save_bar(df, x, y, title, xlabel, ylabel, filename, rotation=35):
    plt.figure(figsize=(11, 6))
    plt.bar(df[x].astype(str).to_numpy(), df[y].to_numpy())
    plt.title(title)
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.xticks(rotation=rotation, ha="right")
    plt.tight_layout()
    plt.savefig(CHARTS / filename, dpi=200)
    plt.close()


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
    logx=False,
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
    logx=True,
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
    logx=True,
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
    logx=True,
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
