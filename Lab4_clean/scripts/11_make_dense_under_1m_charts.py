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

AGG = pd.read_csv(REPORT / "12_dense_under_1m_aggregated.csv")
SIZES = pd.read_csv(REPORT / "12_dense_under_1m_sizes.csv")

AGG["avg_total_elapsed_seconds"] = AGG["avg_total_elapsed_ms"] / 1000.0

INDEX_ORDER = [
    "without_index_nonclustered",
    "btree_index_nonclustered",
    "no_index",
    "no_extra_index",
    "simple_btree",
    "unique_btree",
    "expression_index",
    "function_index",
]


def fmt_number(x, _):
    try:
        if abs(x) >= 1000:
            return f"{int(x):,}".replace(",", " ")
        return f"{x:g}"
    except Exception:
        return str(x)


def sort_index_types(values):
    order_map = {name: i for i, name in enumerate(INDEX_ORDER)}
    return sorted(values, key=lambda x: (order_map.get(x, 999), x))


def apply_line_format(ax, logx=False):
    if logx:
        ax.set_xscale("log")

    xticks = sorted(AGG["rows_base"].dropna().unique().tolist())
    ax.set_xticks(xticks)
    ax.set_xticklabels(
        [f"{int(x):,}".replace(",", " ") for x in xticks],
        rotation=35,
        ha="right",
    )

    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, which="both" if logx else "major", alpha=0.25)
    ax.legend()


def save_line(operation_name, y_col, title, ylabel, filename, logx=False):
    df = AGG[AGG["operation_name"] == operation_name].copy()
    if df.empty:
        print("skip empty:", operation_name, filename)
        return

    fig, ax = plt.subplots(figsize=(13, 6))

    for index_type in sort_index_types(df["index_type"].dropna().unique().tolist()):
        part = df[df["index_type"] == index_type].sort_values("rows_base")
        ax.plot(
            pd.to_numeric(part["rows_base"], errors="coerce").to_numpy(),
            pd.to_numeric(part[y_col], errors="coerce").to_numpy(),
            marker="o",
            label=index_type,
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    apply_line_format(ax, logx=logx)

    fig.tight_layout()
    out = CHARTS / filename
    fig.savefig(out, dpi=200)
    plt.close(fig)
    print("saved:", out)


def save_size_line(metric_col, title, ylabel, filename, logx=False):
    df = SIZES.copy()
    if df.empty:
        print("skip empty sizes:", filename)
        return

    fig, ax = plt.subplots(figsize=(13, 6))

    for key, part in df.groupby(["operation_name", "index_type"]):
        op, idx = key
        part = part.sort_values("rows_base")
        ax.plot(
            pd.to_numeric(part["rows_base"], errors="coerce").to_numpy(),
            pd.to_numeric(part[metric_col], errors="coerce").to_numpy(),
            marker="o",
            label=f"{op}:{idx}",
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    apply_line_format(ax, logx=logx)

    fig.tight_layout()
    out = CHARTS / filename
    fig.savefig(out, dpi=200)
    plt.close(fig)
    print("saved:", out)


save_line(
    "select",
    "avg_elapsed_ms_per_operation",
    "Dense SELECT: среднее время одной выборки, линейная шкала",
    "Среднее время одного SELECT, мс",
    "12_dense_select_avg_ms.png",
    logx=False,
)

save_line(
    "select",
    "avg_elapsed_ms_per_operation",
    "Dense SELECT: среднее время одной выборки, log X",
    "Среднее время одного SELECT, мс",
    "12_dense_select_avg_ms_logx.png",
    logx=True,
)

save_line(
    "select",
    "avg_total_elapsed_seconds",
    "Dense SELECT: среднее время серии, линейная шкала",
    "Среднее время серии SELECT, с",
    "12_dense_select_total_seconds.png",
    logx=False,
)

save_line(
    "select",
    "avg_total_elapsed_seconds",
    "Dense SELECT: среднее время серии, log X",
    "Среднее время серии SELECT, с",
    "12_dense_select_total_seconds_logx.png",
    logx=True,
)

save_line(
    "insert",
    "avg_total_elapsed_ms",
    "Dense INSERT: среднее время вставки пакета строк, линейная шкала",
    "Среднее время вставки пакета, мс",
    "12_dense_insert_total_ms.png",
    logx=False,
)

save_line(
    "insert",
    "avg_total_elapsed_ms",
    "Dense INSERT: среднее время вставки пакета строк, log X",
    "Среднее время вставки пакета, мс",
    "12_dense_insert_total_ms_logx.png",
    logx=True,
)

save_line(
    "insert",
    "avg_elapsed_ms_per_operation",
    "Dense INSERT: среднее время одной вставляемой строки, линейная шкала",
    "Среднее время одной вставляемой строки, мс",
    "12_dense_insert_per_row_ms.png",
    logx=False,
)

save_line(
    "insert",
    "avg_elapsed_ms_per_operation",
    "Dense INSERT: среднее время одной вставляемой строки, log X",
    "Среднее время одной вставляемой строки, мс",
    "12_dense_insert_per_row_ms_logx.png",
    logx=True,
)

save_line(
    "update",
    "avg_total_elapsed_ms",
    "Dense UPDATE: среднее время обновления пакета строк, линейная шкала",
    "Среднее время обновления пакета, мс",
    "12_dense_update_total_ms.png",
    logx=False,
)

save_line(
    "update",
    "avg_total_elapsed_ms",
    "Dense UPDATE: среднее время обновления пакета строк, log X",
    "Среднее время обновления пакета, мс",
    "12_dense_update_total_ms_logx.png",
    logx=True,
)

save_line(
    "update",
    "avg_elapsed_ms_per_operation",
    "Dense UPDATE: среднее время обновления одной строки, линейная шкала",
    "Среднее время обновления одной строки, мс",
    "12_dense_update_per_row_ms.png",
    logx=False,
)

save_line(
    "update",
    "avg_elapsed_ms_per_operation",
    "Dense UPDATE: среднее время обновления одной строки, log X",
    "Среднее время обновления одной строки, мс",
    "12_dense_update_per_row_ms_logx.png",
    logx=True,
)

save_size_line(
    "relation_bytes",
    "Dense: размер heap-таблицы",
    "Размер heap-таблицы, байт",
    "12_dense_relation_bytes.png",
    logx=False,
)

save_size_line(
    "indexes_bytes",
    "Dense: размер индексов",
    "Размер индексов, байт",
    "12_dense_indexes_bytes.png",
    logx=False,
)

save_size_line(
    "total_bytes",
    "Dense: общий размер таблицы и индексов",
    "Общий размер, байт",
    "12_dense_total_bytes.png",
    logx=False,
)

print("Dense charts saved to:", CHARTS)
