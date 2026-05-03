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

AGG = pd.read_csv(REPORT / "10_extended_all_sizes_aggregated.csv")
SIZES = pd.read_csv(REPORT / "10_extended_all_sizes_sizes.csv")


def fmt_number(x, _):
    try:
        if abs(x) >= 1000:
            return f"{int(x):,}".replace(",", " ")
        return f"{x:g}"
    except Exception:
        return str(x)


def pick_col(df, candidates):
    for c in candidates:
        if c in df.columns:
            return c
    raise KeyError(
        f"None of columns found: {candidates}. Existing columns: {list(df.columns)}"
    )


def ensure_derived_columns(df):
    df = df.copy()

    if "avg_total_elapsed_seconds" not in df.columns:
        if "avg_total_elapsed_ms" in df.columns:
            df["avg_total_elapsed_seconds"] = df["avg_total_elapsed_ms"] / 1000.0

    if "avg_elapsed_ms_per_operation" not in df.columns:
        def calc_per_op(row):
            total_ms = row["avg_total_elapsed_ms"]
            if row["operation_name"] == "select":
                probes = row.get("probes_min", 1)
                return total_ms / max(probes, 1)
            batch = row.get("batch_size_min", 1)
            return total_ms / max(batch, 1)

        df["avg_elapsed_ms_per_operation"] = df.apply(calc_per_op, axis=1)

    return df


AGG = ensure_derived_columns(AGG)

ALL_ROWS = sorted(AGG["rows_base"].dropna().unique().tolist())
ZOOM_ROWS = [x for x in ALL_ROWS if 10 <= x <= 1_000_000]

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


def sort_index_types(values):
    order_map = {name: i for i, name in enumerate(INDEX_ORDER)}
    return sorted(values, key=lambda x: (order_map.get(x, 999), x))


def apply_common(ax, title, ylabel, logx=False, xticks=None):
    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)

    if logx:
        ax.set_xscale("log")

    if xticks is not None and len(xticks) > 0:
        ax.set_xticks(xticks)
        ax.set_xticklabels(
            [f"{int(x):,}".replace(",", " ") for x in xticks],
            rotation=30,
            ha="right",
        )

    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, which="both" if logx else "major", alpha=0.25)
    ax.legend()


def save_line_triplet(operation_name, y_col, title_base, y_label, file_prefix):
    part = AGG[AGG["operation_name"] == operation_name].copy()
    if part.empty:
        print(f"skip: no data for operation {operation_name}")
        return

    variants = [
        {
            "suffix": "_full",
            "title": f"{title_base}: полный диапазон",
            "logx": False,
            "filter_rows": None,
            "xticks": ALL_ROWS,
            "legacy_alias": True,
        },
        {
            "suffix": "_10_to_1m",
            "title": f"{title_base}: диапазон 10 – 1 000 000 строк",
            "logx": False,
            "filter_rows": lambda df: df[df["rows_base"].between(10, 1_000_000)],
            "xticks": ZOOM_ROWS,
            "legacy_alias": False,
        },
        {
            "suffix": "_logx",
            "title": f"{title_base}: логарифмическая шкала по X",
            "logx": True,
            "filter_rows": None,
            "xticks": ALL_ROWS,
            "legacy_alias": False,
        },
    ]

    for variant in variants:
        df = part.copy()
        if variant["filter_rows"] is not None:
            df = variant["filter_rows"](df)

        if df.empty:
            print(f"skip empty variant: {file_prefix}{variant['suffix']}.png")
            continue

        fig, ax = plt.subplots(figsize=(12, 6))

        index_types = sort_index_types(df["index_type"].dropna().unique().tolist())
        for index_type in index_types:
            series = df[df["index_type"] == index_type].sort_values("rows_base")
            x_values = pd.to_numeric(series["rows_base"], errors="coerce").to_numpy()
            y_values = pd.to_numeric(series[y_col], errors="coerce").to_numpy()

            ax.plot(
                x_values,
                y_values,
                marker="o",
                label=index_type,
            )

        apply_common(
            ax=ax,
            title=variant["title"],
            ylabel=y_label,
            logx=variant["logx"],
            xticks=variant["xticks"],
        )

        fig.tight_layout()

        out_path = CHARTS / f"{file_prefix}{variant['suffix']}.png"
        fig.savefig(out_path, dpi=200)
        print("saved:", out_path)

        if variant["legacy_alias"]:
            alias_path = CHARTS / f"{file_prefix}.png"
            fig.savefig(alias_path, dpi=200)
            print("saved legacy alias:", alias_path)

        plt.close(fig)


def build_size_labels(df):
    if "operation_name" in df.columns and "index_type" in df.columns:
        return [
            f"{op}\n{idx}"
            for op, idx in zip(
                df["operation_name"].astype(str),
                df["index_type"].astype(str),
            )
        ]
    if "table_name" in df.columns:
        return df["table_name"].astype(str).tolist()
    return [str(i) for i in range(len(df))]


def save_bar_sizes():
    df = SIZES.copy()
    if df.empty:
        print("skip: SIZES dataframe is empty")
        return

    df = df.sort_values(
        by=[
            "operation_name" if "operation_name" in df.columns else df.columns[0],
            "index_type" if "index_type" in df.columns else df.columns[0],
        ]
    )

    labels = build_size_labels(df)

    total_col = pick_col(df, ["total_bytes", "total_size_bytes"])
    index_col = pick_col(df, ["indexes_bytes", "index_bytes"])

    # total sizes
    fig, ax = plt.subplots(figsize=(14, 7))
    ax.bar(labels, pd.to_numeric(df[total_col], errors="coerce").to_numpy())
    ax.set_title("Размеры рабочих таблиц и индексов после максимального размера")
    ax.set_xlabel("Операция и тип индекса")
    ax.set_ylabel("Общий размер, байт")
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, axis="y", alpha=0.25)
    plt.xticks(rotation=45, ha="right")
    fig.tight_layout()
    out_total = CHARTS / "10_ext_final_total_sizes.png"
    fig.savefig(out_total, dpi=200)
    print("saved:", out_total)
    plt.close(fig)

    # index sizes
    fig, ax = plt.subplots(figsize=(14, 7))
    ax.bar(labels, pd.to_numeric(df[index_col], errors="coerce").to_numpy())
    ax.set_title("Размер индексовых структур после максимального размера")
    ax.set_xlabel("Операция и тип индекса")
    ax.set_ylabel("Размер индексов, байт")
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, axis="y", alpha=0.25)
    plt.xticks(rotation=45, ha="right")
    fig.tight_layout()
    out_index = CHARTS / "10_ext_final_index_sizes.png"
    fig.savefig(out_index, dpi=200)
    print("saved:", out_index)
    plt.close(fig)


# SELECT
save_line_triplet(
    operation_name="select",
    y_col="avg_elapsed_ms_per_operation",
    title_base="SELECT на случайных не кластеризованных данных: среднее время одной выборки",
    y_label="Среднее время одного SELECT, мс",
    file_prefix="10_ext_select_avg_ms",
)

save_line_triplet(
    operation_name="select",
    y_col="avg_total_elapsed_seconds",
    title_base="SELECT на случайных не кластеризованных данных: среднее время серии",
    y_label="Среднее время серии SELECT, с",
    file_prefix="10_ext_select_total_seconds",
)

# INSERT
save_line_triplet(
    operation_name="insert",
    y_col="avg_total_elapsed_ms",
    title_base="INSERT: среднее время вставки пакета строк",
    y_label="Среднее время вставки пакета, мс",
    file_prefix="10_ext_insert_total_ms",
)

save_line_triplet(
    operation_name="insert",
    y_col="avg_elapsed_ms_per_operation",
    title_base="INSERT: среднее время одной вставляемой строки",
    y_label="Среднее время одной вставляемой строки, мс",
    file_prefix="10_ext_insert_per_row_ms",
)

# UPDATE
save_line_triplet(
    operation_name="update",
    y_col="avg_total_elapsed_ms",
    title_base="UPDATE: среднее время обновления пакета строк",
    y_label="Среднее время обновления пакета, мс",
    file_prefix="10_ext_update_total_ms",
)

save_line_triplet(
    operation_name="update",
    y_col="avg_elapsed_ms_per_operation",
    title_base="UPDATE: среднее время обновления одной строки",
    y_label="Среднее время обновления одной строки, мс",
    file_prefix="10_ext_update_per_row_ms",
)

# BAR CHARTS
save_bar_sizes()

print("Extended charts saved to:", CHARTS)