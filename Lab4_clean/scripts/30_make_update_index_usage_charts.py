#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


BASE = Path(__file__).resolve().parents[1]
REPORT = BASE / "report"
CHARTS = BASE / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)

INPUT = REPORT / "30_update_index_usage_aggregated.csv"


def fmt_number(x, _):
    try:
        if abs(x) >= 1000:
            return f"{int(x):,}".replace(",", " ")
        return f"{x:g}"
    except Exception:
        return str(x)


def apply_format(ax):
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, alpha=0.3)


def save_line(df, value_col, title, ylabel, filename, label_col="label"):
    if df.empty:
        print(f"skip empty: {filename}")
        return

    fig, ax = plt.subplots(figsize=(14, 7))

    for label, g in df.groupby(label_col):
        g = g.sort_values("rows_base")
        ax.plot(
            g["rows_base"].to_numpy(),
            g[value_col].to_numpy(),
            marker="o",
            linewidth=2,
            label=str(label),
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    apply_format(ax)
    ax.legend()
    fig.tight_layout()

    out = CHARTS / filename
    fig.savefig(out, dpi=180)
    plt.close(fig)
    print(f"saved: {out}")


def main():
    if not INPUT.exists():
        raise FileNotFoundError(f"Не найден файл: {INPUT}")

    df = pd.read_csv(INPUT)

    for col in ["rows_base", "avg_total_elapsed_ms", "avg_elapsed_ms_per_row"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["rows_base", "avg_total_elapsed_ms", "avg_elapsed_ms_per_row"])

    # 1. Поиск строк для UPDATE: no_index против индексов в режиме lookup_only.
    search_df = df[
        ((df["index_type"] == "no_index") & (df["mode"] == "no_index"))
        | ((df["index_type"] != "no_index") & (df["mode"] == "lookup_only"))
    ].copy()

    search_df["label"] = search_df["index_type"]

    save_line(
        search_df,
        "avg_total_elapsed_ms",
        "UPDATE: поиск строк без индекса и через исследуемые индексы",
        "Среднее время серии UPDATE, мс",
        "30_update_index_search_total_linear.png",
    )

    save_line(
        search_df,
        "avg_elapsed_ms_per_row",
        "UPDATE: поиск строк без индекса и через исследуемые индексы, на одну строку",
        "Среднее время одной обновленной строки, мс",
        "30_update_index_search_per_row_linear.png",
    )

    # 2. Все индексные варианты: lookup_only против lookup_and_update.
    indexed_df = df[df["index_type"] != "no_index"].copy()
    indexed_df["label"] = indexed_df["index_type"] + " / " + indexed_df["mode"]

    save_line(
        indexed_df,
        "avg_total_elapsed_ms",
        "UPDATE: индекс только ищет строки vs индекс ищет и обновляется",
        "Среднее время серии UPDATE, мс",
        "30_update_lookup_vs_maintenance_total_linear.png",
    )

    save_line(
        indexed_df,
        "avg_elapsed_ms_per_row",
        "UPDATE: индекс только ищет строки vs индекс ищет и обновляется, на одну строку",
        "Среднее время одной обновленной строки, мс",
        "30_update_lookup_vs_maintenance_per_row_linear.png",
    )

    # 3. Отдельные графики по каждому индексу.
    for index_type in sorted(indexed_df["index_type"].unique()):
        part = indexed_df[indexed_df["index_type"] == index_type].copy()
        part["label"] = part["mode"]

        safe = index_type.replace("/", "_").replace(" ", "_")

        save_line(
            part,
            "avg_total_elapsed_ms",
            f"UPDATE: {index_type}, lookup_only и lookup_and_update",
            "Среднее время серии UPDATE, мс",
            f"30_update_{safe}_lookup_vs_maintenance_total_linear.png",
        )

        save_line(
            part,
            "avg_elapsed_ms_per_row",
            f"UPDATE: {index_type}, lookup_only и lookup_and_update, на одну строку",
            "Среднее время одной обновленной строки, мс",
            f"30_update_{safe}_lookup_vs_maintenance_per_row_linear.png",
        )

    # 4. Накладные расходы обслуживания индекса.
    pivot_total = indexed_df.pivot_table(
        index=["index_type", "rows_base"],
        columns="mode",
        values="avg_total_elapsed_ms",
        aggfunc="mean",
    ).reset_index()

    pivot_per_row = indexed_df.pivot_table(
        index=["index_type", "rows_base"],
        columns="mode",
        values="avg_elapsed_ms_per_row",
        aggfunc="mean",
    ).reset_index()

    overhead_total = pivot_total.dropna(subset=["lookup_only", "lookup_and_update"]).copy()
    overhead_total["maintenance_overhead_ms"] = (
        overhead_total["lookup_and_update"] - overhead_total["lookup_only"]
    )
    overhead_total["label"] = overhead_total["index_type"]

    overhead_per_row = pivot_per_row.dropna(subset=["lookup_only", "lookup_and_update"]).copy()
    overhead_per_row["maintenance_overhead_ms_per_row"] = (
        overhead_per_row["lookup_and_update"] - overhead_per_row["lookup_only"]
    )
    overhead_per_row["label"] = overhead_per_row["index_type"]

    save_line(
        overhead_total,
        "maintenance_overhead_ms",
        "UPDATE: дополнительные расходы обслуживания индексируемого поля",
        "lookup_and_update - lookup_only, мс",
        "30_update_maintenance_overhead_total_linear.png",
    )

    save_line(
        overhead_per_row,
        "maintenance_overhead_ms_per_row",
        "UPDATE: дополнительные расходы обслуживания индексируемого поля на одну строку",
        "lookup_and_update - lookup_only, мс/строка",
        "30_update_maintenance_overhead_per_row_linear.png",
    )

    print("DONE: update index usage charts saved")


if __name__ == "__main__":
    main()
