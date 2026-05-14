from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FuncFormatter


BASE = Path(__file__).resolve().parents[1]
REPORT = BASE / "report"
CHARTS = BASE / "charts"

CHARTS.mkdir(parents=True, exist_ok=True)

CSV = REPORT / "21_update_trigger_compare_aggregated.csv"
df = pd.read_csv(CSV)

df["rows_base"] = df["rows_base"].astype(int)
df["avg_total_elapsed_ms"] = pd.to_numeric(df["avg_total_elapsed_ms"])
df["avg_elapsed_ms_per_row"] = pd.to_numeric(df["avg_elapsed_ms_per_row"])

LABELS = {
    "no_lookup_index": "true no index / Seq Scan",
    "no_extra_index": "lookup index only",
    "simple_btree": "simple B-tree",
    "unique_btree": "unique B-tree",
    "expression_index": "expression index",
    "function_index": "function index",
}

RU_LABELS = {
    "no_lookup_index": "без индекса поиска",
    "no_extra_index": "только индекс поиска",
    "simple_btree": "простой B-tree",
    "unique_btree": "уникальный B-tree",
    "expression_index": "индекс по выражению",
    "function_index": "функциональный индекс",
}

MODE_LABELS = {
    "without_trigger": "без триггера",
    "with_trigger": "с триггером",
}

ALL_FOR_TRUE_NO_INDEX = [
    "no_lookup_index",
    "no_extra_index",
    "simple_btree",
    "unique_btree",
    "expression_index",
    "function_index",
]

INDEXED_ONLY = [
    "simple_btree",
    "unique_btree",
    "expression_index",
    "function_index",
]


def format_int_with_spaces(x, _pos):
    try:
        return f"{int(x):,}".replace(",", " ")
    except Exception:
        return str(x)


def save_lines(
    data: pd.DataFrame,
    index_types: list[str],
    modes: list[str],
    y_col: str,
    title: str,
    ylabel: str,
    out_name: str,
    logx: bool = True,
    total_units: bool = False,
):
    fig, ax = plt.subplots(figsize=(14, 7))

    for index_type in index_types:
        for mode in modes:
            part = data[
                (data["index_type"] == index_type)
                & (data["trigger_mode"] == mode)
            ].sort_values("rows_base")

            if part.empty:
                continue

            if len(modes) == 1:
                label = RU_LABELS.get(index_type, index_type)
            else:
                label = f"{RU_LABELS.get(index_type, index_type)} — {MODE_LABELS.get(mode, mode)}"

            ax.plot(
                part["rows_base"].to_numpy(),
                part[y_col].to_numpy(),
                marker="o",
                linewidth=1.8,
                label=label,
            )

    if logx:
        ax.set_xscale("log")
        ax.set_xlabel("Количество строк в таблице, логарифмическая шкала")
    else:
        ax.set_xlabel("Количество строк в таблице")

    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.grid(True, alpha=0.3)
    ax.legend()
    ax.xaxis.set_major_formatter(FuncFormatter(format_int_with_spaces))

    if total_units:
        ax.yaxis.set_major_formatter(FuncFormatter(format_int_with_spaces))

    fig.tight_layout()
    fig.savefig(CHARTS / out_name, dpi=200)
    plt.close(fig)


# 1. Главный график: настоящий безиндексный поиск + остальные варианты.
base_without_trigger = df[df["trigger_mode"] == "without_trigger"].copy()

save_lines(
    base_without_trigger,
    ALL_FOR_TRUE_NO_INDEX,
    ["without_trigger"],
    "avg_elapsed_ms_per_row",
    "UPDATE: настоящий безиндексный поиск и остальные варианты, среднее время одной строки, logX",
    "Среднее время обновления одной строки, мс",
    "21_update_true_no_index_vs_all_per_row_logx.png",
    logx=True,
)

save_lines(
    base_without_trigger,
    ALL_FOR_TRUE_NO_INDEX,
    ["without_trigger"],
    "avg_total_elapsed_ms",
    "UPDATE: настоящий безиндексный поиск и остальные варианты, время серии, logX",
    "Среднее время серии UPDATE, мс",
    "21_update_true_no_index_vs_all_total_logx.png",
    logx=True,
    total_units=True,
)

# 2. По каждому виду индекса: без триггера / с триггером.
for index_type in INDEXED_ONLY:
    save_lines(
        df,
        [index_type],
        ["without_trigger", "with_trigger"],
        "avg_elapsed_ms_per_row",
        f"UPDATE: влияние триггера для {RU_LABELS[index_type]}, среднее время одной строки, logX",
        "Среднее время обновления одной строки, мс",
        f"22_trigger_{index_type}_per_row_logx.png",
        logx=True,
    )

    save_lines(
        df,
        [index_type],
        ["without_trigger", "with_trigger"],
        "avg_total_elapsed_ms",
        f"UPDATE: влияние триггера для {RU_LABELS[index_type]}, время серии, logX",
        "Среднее время серии UPDATE, мс",
        f"22_trigger_{index_type}_total_logx.png",
        logx=True,
        total_units=True,
    )

# 3. Общий график: все индексные варианты без no_lookup_index и no_extra_index.
save_lines(
    df,
    INDEXED_ONLY,
    ["without_trigger", "with_trigger"],
    "avg_elapsed_ms_per_row",
    "UPDATE: все индексные варианты с триггером и без триггера, среднее время одной строки, logX",
    "Среднее время обновления одной строки, мс",
    "22_trigger_all_indexed_per_row_logx.png",
    logx=True,
)

save_lines(
    df,
    INDEXED_ONLY,
    ["without_trigger", "with_trigger"],
    "avg_total_elapsed_ms",
    "UPDATE: все индексные варианты с триггером и без триггера, время серии, logX",
    "Среднее время серии UPDATE, мс",
    "22_trigger_all_indexed_total_logx.png",
    logx=True,
    total_units=True,
)

# 4. Сводные графики именно влияния триггера.
indexed = df[df["index_type"].isin(INDEXED_ONLY)].copy()

pivot_total = indexed.pivot_table(
    index=["index_type", "rows_base"],
    columns="trigger_mode",
    values="avg_total_elapsed_ms",
    aggfunc="mean",
).reset_index()

pivot_row = indexed.pivot_table(
    index=["index_type", "rows_base"],
    columns="trigger_mode",
    values="avg_elapsed_ms_per_row",
    aggfunc="mean",
).reset_index()

for pivot in (pivot_total, pivot_row):
    pivot["trigger_ratio"] = pivot["with_trigger"] / pivot["without_trigger"]
    pivot["trigger_overhead"] = pivot["with_trigger"] - pivot["without_trigger"]


def save_effect_chart(
    pivot: pd.DataFrame,
    y_col: str,
    title: str,
    ylabel: str,
    out_name: str,
):
    fig, ax = plt.subplots(figsize=(14, 7))

    for index_type in INDEXED_ONLY:
        part = pivot[pivot["index_type"] == index_type].sort_values("rows_base")
        if part.empty:
            continue

        ax.plot(
            part["rows_base"].to_numpy(),
            part[y_col].to_numpy(),
            marker="o",
            linewidth=1.8,
            label=RU_LABELS[index_type],
        )

    ax.set_xscale("log")
    ax.set_xlabel("Количество строк в таблице, логарифмическая шкала")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.grid(True, alpha=0.3)
    ax.legend()
    ax.xaxis.set_major_formatter(FuncFormatter(format_int_with_spaces))

    fig.tight_layout()
    fig.savefig(CHARTS / out_name, dpi=200)
    plt.close(fig)


save_effect_chart(
    pivot_total,
    "trigger_ratio",
    "UPDATE: коэффициент замедления от триггера по времени серии, logX",
    "T(с триггером) / T(без триггера)",
    "22_trigger_slowdown_ratio_total_logx.png",
)

save_effect_chart(
    pivot_total,
    "trigger_overhead",
    "UPDATE: добавочное время от триггера по времени серии, logX",
    "Дополнительное время серии UPDATE, мс",
    "22_trigger_overhead_total_ms_logx.png",
)

save_effect_chart(
    pivot_row,
    "trigger_ratio",
    "UPDATE: коэффициент замедления от триггера по времени одной строки, logX",
    "T(с триггером) / T(без триггера)",
    "22_trigger_slowdown_ratio_per_row_logx.png",
)

print("saved charts:")
for path in sorted(CHARTS.glob("21_update_*.png")) + sorted(CHARTS.glob("22_trigger_*.png")):
    print(f"  {path.relative_to(BASE)}")
