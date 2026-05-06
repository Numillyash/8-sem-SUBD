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

df = pd.read_csv(REPORT / "17_update_microbatch10_control.csv")

order = [
    "no_lookup_index",
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


def save_line(metric, ylabel, title, filename, logx=False):
    fig, ax = plt.subplots(figsize=(13, 7))

    for index_type in order:
        g = df[df["index_type"] == index_type].sort_values("rows_base")
        if g.empty:
            continue

        ax.plot(
            g["rows_base"].to_numpy(),
            g[metric].to_numpy(),
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


save_line(
    "avg_total_elapsed_ms",
    "Среднее время серии UPDATE, мс",
    "UPDATE micro-batch: 100 UPDATE по 10 строк",
    "18_update_microbatch10_total_ms.png",
    logx=False,
)

save_line(
    "avg_total_elapsed_ms",
    "Среднее время серии UPDATE, мс",
    "UPDATE micro-batch: 100 UPDATE по 10 строк, logX",
    "18_update_microbatch10_total_ms_logx.png",
    logx=True,
)

save_line(
    "avg_elapsed_ms_per_row",
    "Среднее время одной обновленной строки, мс",
    "UPDATE micro-batch: среднее время одной строки",
    "18_update_microbatch10_per_row_ms.png",
    logx=False,
)

save_line(
    "avg_elapsed_ms_per_row",
    "Среднее время одной обновленной строки, мс",
    "UPDATE micro-batch: среднее время одной строки, logX",
    "18_update_microbatch10_per_row_ms_logx.png",
    logx=True,
)
