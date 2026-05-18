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


def save_line(df, value_col, title, ylabel, filename):
    if df.empty:
        print(f"skip empty: {filename}")
        return

    fig, ax = plt.subplots(figsize=(14, 7))

    for label, g in df.groupby("index_type"):
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

    indexed = df[df["index_type"] != "no_index"].copy()

    # 1. Нормированное сравнение индексного поиска.
    # Для каждого размера таблицы N вычитаем самый быстрый indexed lookup_only.
    lookup = indexed[indexed["mode"] == "lookup_only"].copy()

    min_total = (
        lookup.groupby("rows_base")["avg_total_elapsed_ms"]
        .min()
        .rename("min_lookup_total_ms")
        .reset_index()
    )

    min_per_row = (
        lookup.groupby("rows_base")["avg_elapsed_ms_per_row"]
        .min()
        .rename("min_lookup_per_row_ms")
        .reset_index()
    )

    lookup = lookup.merge(min_total, on="rows_base", how="left")
    lookup = lookup.merge(min_per_row, on="rows_base", how="left")

    lookup["normalized_lookup_total_ms"] = (
        lookup["avg_total_elapsed_ms"] - lookup["min_lookup_total_ms"]
    )

    lookup["normalized_lookup_per_row_ms"] = (
        lookup["avg_elapsed_ms_per_row"] - lookup["min_lookup_per_row_ms"]
    )

    save_line(
        lookup,
        "normalized_lookup_total_ms",
        "UPDATE: относительная стоимость индексного поиска без общей базы",
        "Превышение над самым быстрым индексом при том же N, мс",
        "31_update_index_lookup_normalized_total_linear.png",
    )

    save_line(
        lookup,
        "normalized_lookup_per_row_ms",
        "UPDATE: относительная стоимость индексного поиска без общей базы, на одну строку",
        "Превышение над самым быстрым индексом при том же N, мс/строка",
        "31_update_index_lookup_normalized_per_row_linear.png",
    )

    # 2. Чистая добавочная стоимость обслуживания индекса.
    # lookup_and_update - lookup_only для каждого индекса и размера.
    pivot_total = indexed.pivot_table(
        index=["index_type", "rows_base"],
        columns="mode",
        values="avg_total_elapsed_ms",
        aggfunc="mean",
    ).reset_index()

    pivot_per_row = indexed.pivot_table(
        index=["index_type", "rows_base"],
        columns="mode",
        values="avg_elapsed_ms_per_row",
        aggfunc="mean",
    ).reset_index()

    overhead_total = pivot_total.dropna(subset=["lookup_only", "lookup_and_update"]).copy()
    overhead_total["maintenance_overhead_ms"] = (
        overhead_total["lookup_and_update"] - overhead_total["lookup_only"]
    )

    overhead_per_row = pivot_per_row.dropna(subset=["lookup_only", "lookup_and_update"]).copy()
    overhead_per_row["maintenance_overhead_ms_per_row"] = (
        overhead_per_row["lookup_and_update"] - overhead_per_row["lookup_only"]
    )

    save_line(
        overhead_total,
        "maintenance_overhead_ms",
        "UPDATE: чистая добавочная стоимость обслуживания индекса",
        "lookup_and_update - lookup_only, мс",
        "31_update_index_maintenance_overhead_total_linear.png",
    )

    save_line(
        overhead_per_row,
        "maintenance_overhead_ms_per_row",
        "UPDATE: чистая добавочная стоимость обслуживания индекса, на одну строку",
        "lookup_and_update - lookup_only, мс/строка",
        "31_update_index_maintenance_overhead_per_row_linear.png",
    )

    print("DONE")


if __name__ == "__main__":
    main()
