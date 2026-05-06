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


def fmt_number(x, _):
    try:
        if abs(x) >= 1000:
            return f"{int(x):,}".replace(",", " ")
        return f"{x:g}"
    except Exception:
        return str(x)


dense = pd.read_csv(REPORT / "12_dense_under_1m_aggregated.csv")
control = pd.read_csv(REPORT / "16_update_no_lookup_index_control.csv")

update_dense = dense[dense["operation_name"] == "update"].copy()

control_norm = pd.DataFrame({
    "index_type": "no_lookup_index",
    "rows_base": control["rows_base"],
    "avg_total_elapsed_ms": control["avg_total_elapsed_ms"],
    "avg_elapsed_ms_per_operation": control["avg_elapsed_ms_per_row"],
})

plot_df = pd.concat([
    update_dense[[
        "index_type",
        "rows_base",
        "avg_total_elapsed_ms",
        "avg_elapsed_ms_per_operation",
    ]],
    control_norm,
], ignore_index=True)

preferred_order = [
    "no_lookup_index",
    "no_extra_index",
    "simple_btree",
    "unique_btree",
    "expression_index",
    "function_index",
]


def save_chart(metric: str, ylabel: str, title: str, filename: str, logx: bool = False):
    fig, ax = plt.subplots(figsize=(13, 7))

    for index_type in preferred_order:
        group = plot_df[plot_df["index_type"] == index_type].sort_values("rows_base")
        if group.empty:
            continue

        ax.plot(
            group["rows_base"].to_numpy(),
            group[metric].to_numpy(),
            marker="o",
            label=index_type,
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, alpha=0.25)
    ax.legend()

    if logx:
        ax.set_xscale("log")
        ax.set_xlabel("Количество строк в таблице, логарифмическая шкала")

    fig.tight_layout()
    out = CHARTS / filename
    fig.savefig(out, dpi=180)
    plt.close(fig)
    print("saved:", out)


save_chart(
    "avg_total_elapsed_ms",
    "Среднее время обновления пакета, мс",
    "UPDATE: сравнение поиска без индекса и индексного поиска",
    "16_update_no_lookup_index_total_ms.png",
    logx=False,
)

save_chart(
    "avg_total_elapsed_ms",
    "Среднее время обновления пакета, мс",
    "UPDATE: сравнение поиска без индекса и индексного поиска, logX",
    "16_update_no_lookup_index_total_ms_logx.png",
    logx=True,
)

save_chart(
    "avg_elapsed_ms_per_operation",
    "Среднее время обновления одной строки, мс",
    "UPDATE: среднее время одной строки без индекса поиска и с индексами",
    "16_update_no_lookup_index_per_row_ms.png",
    logx=False,
)

save_chart(
    "avg_elapsed_ms_per_operation",
    "Среднее время обновления одной строки, мс",
    "UPDATE: среднее время одной строки без индекса поиска и с индексами, logX",
    "16_update_no_lookup_index_per_row_ms_logx.png",
    logx=True,
)
