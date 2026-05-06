from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")
REPORT = BASE / "report"
CHARTS = BASE / "charts"

INPUT_CSV = REPORT / "17_update_microbatch10_control.csv"

CHARTS.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(INPUT_CSV)

df = df[df["index_type"] != "no_lookup_index"].copy()

order = [
    "no_extra_index",
    "simple_btree",
    "unique_btree",
    "expression_index",
    "function_index",
]

df["index_type"] = pd.Categorical(df["index_type"], categories=order, ordered=True)
df = df.sort_values(["index_type", "rows_base"])


def format_thousands(x, pos):
    try:
        return f"{int(x):,}".replace(",", " ")
    except Exception:
        return str(x)


def save_chart(metric, ylabel, title, output_name, logx=False):
    fig, ax = plt.subplots(figsize=(16, 8))

    for index_type, part in df.groupby("index_type", observed=True):
        part = part.sort_values("rows_base")
        ax.plot(
            part["rows_base"].to_numpy(),
            part[metric].to_numpy(),
            marker="o",
            linewidth=2,
            label=index_type,
        )

    if logx:
        ax.set_xscale("log")
        title = title + ", logX"
        output_name = output_name.replace(".png", "_logx.png")

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице" + (", логарифмическая шкала" if logx else ""))
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.3)
    ax.legend()
    ax.xaxis.set_major_formatter(FuncFormatter(format_thousands))

    fig.tight_layout()
    path = CHARTS / output_name
    fig.savefig(path, dpi=200)
    plt.close(fig)
    print(f"saved: {path}")


save_chart(
    metric="avg_total_elapsed_ms",
    ylabel="Среднее время серии UPDATE, мс",
    title="UPDATE micro-batch: 100 UPDATE по 10 строк, только индексные варианты",
    output_name="19_update_microbatch10_index_only_total_ms.png",
    logx=False,
)

save_chart(
    metric="avg_total_elapsed_ms",
    ylabel="Среднее время серии UPDATE, мс",
    title="UPDATE micro-batch: 100 UPDATE по 10 строк, только индексные варианты",
    output_name="19_update_microbatch10_index_only_total_ms.png",
    logx=True,
)

save_chart(
    metric="avg_elapsed_ms_per_row",
    ylabel="Среднее время одной обновленной строки, мс",
    title="UPDATE micro-batch: среднее время одной строки, только индексные варианты",
    output_name="19_update_microbatch10_index_only_per_row_ms.png",
    logx=False,
)

save_chart(
    metric="avg_elapsed_ms_per_row",
    ylabel="Среднее время одной обновленной строки, мс",
    title="UPDATE micro-batch: среднее время одной строки, только индексные варианты",
    output_name="19_update_microbatch10_index_only_per_row_ms.png",
    logx=True,
)
