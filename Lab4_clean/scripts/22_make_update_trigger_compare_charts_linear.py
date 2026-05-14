#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
import re

import pandas as pd
import matplotlib.pyplot as plt


BASE = Path(__file__).resolve().parents[1]
REPORT = BASE / "report"
CHARTS = BASE / "charts"

INPUT_CSV = REPORT / "21_update_trigger_compare_aggregated.csv"

CHARTS.mkdir(parents=True, exist_ok=True)


def find_col(df: pd.DataFrame, candidates: list[str]) -> str:
    for col in candidates:
        if col in df.columns:
            return col
    raise KeyError(
        "Не найден ни один из ожидаемых столбцов: "
        + ", ".join(candidates)
        + f"\nФактические столбцы CSV: {list(df.columns)}"
    )


def normalize_trigger_value(value) -> str:
    s = str(value).strip().lower()

    if s in {"true", "t", "1", "yes", "y", "on", "with_trigger", "trigger", "trigger_on"}:
        return "with_trigger"

    if s in {"false", "f", "0", "no", "n", "off", "without_trigger", "no_trigger", "trigger_off"}:
        return "without_trigger"

    if "without" in s or "no_trigger" in s or "off" in s or "без" in s:
        return "without_trigger"

    if "with" in s or "trigger" in s or "on" in s or "с" in s:
        return "with_trigger"

    return s


def safe_name(value: str) -> str:
    value = str(value)
    value = re.sub(r"[^A-Za-z0-9А-Яа-яЁё_-]+", "_", value)
    value = re.sub(r"_+", "_", value)
    return value.strip("_")


def prepare_df() -> pd.DataFrame:
    if not INPUT_CSV.exists():
        raise FileNotFoundError(f"Не найден файл: {INPUT_CSV}")

    df = pd.read_csv(INPUT_CSV)

    rows_col = find_col(df, ["rows_base", "table_rows", "rows_before", "n_rows"])
    index_col = find_col(df, ["index_type", "index_name", "variant"])
    trigger_col = find_col(df, ["trigger_state", "trigger_enabled", "with_trigger", "trigger_mode"])
    total_col = find_col(
        df,
        [
            "avg_total_elapsed_ms",
            "avg_elapsed_ms",
            "total_elapsed_ms_avg",
            "avg_update_series_ms",
        ],
    )
    per_row_col = find_col(
        df,
        [
            "avg_elapsed_ms_per_row",
            "avg_elapsed_ms_per_operation",
            "per_row_ms",
            "avg_per_row_ms",
        ],
    )

    result = df.rename(
        columns={
            rows_col: "rows_base",
            index_col: "index_type",
            trigger_col: "trigger_state",
            total_col: "avg_total_elapsed_ms",
            per_row_col: "avg_elapsed_ms_per_row",
        }
    ).copy()

    result["trigger_state"] = result["trigger_state"].map(normalize_trigger_value)
    result["rows_base"] = pd.to_numeric(result["rows_base"], errors="coerce")
    result["avg_total_elapsed_ms"] = pd.to_numeric(result["avg_total_elapsed_ms"], errors="coerce")
    result["avg_elapsed_ms_per_row"] = pd.to_numeric(result["avg_elapsed_ms_per_row"], errors="coerce")

    result = result.dropna(
        subset=[
            "rows_base",
            "index_type",
            "trigger_state",
            "avg_total_elapsed_ms",
            "avg_elapsed_ms_per_row",
        ]
    )

    result = result.sort_values(["index_type", "trigger_state", "rows_base"])
    return result


def plot_lines(
    df: pd.DataFrame,
    value_col: str,
    title: str,
    ylabel: str,
    output_name: str,
    series_col: str = "index_type",
    trigger_state: str | None = None,
):
    plot_df = df.copy()

    if trigger_state is not None:
        plot_df = plot_df[plot_df["trigger_state"] == trigger_state].copy()

    if plot_df.empty:
        print(f"skip empty plot: {output_name}")
        return

    fig, ax = plt.subplots(figsize=(14, 7))

    for name, group in plot_df.groupby(series_col):
        group = group.sort_values("rows_base")
        ax.plot(
            group["rows_base"].to_numpy(),
            group[value_col].to_numpy(),
            marker="o",
            linewidth=2,
            label=str(name),
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()

    out = CHARTS / output_name
    fig.savefig(out, dpi=180)
    plt.close(fig)
    print(f"saved: {out}")


def plot_trigger_pair_for_index(
    df: pd.DataFrame,
    index_type: str,
    value_col: str,
    title: str,
    ylabel: str,
    output_name: str,
):
    plot_df = df[df["index_type"] == index_type].copy()

    if plot_df.empty:
        print(f"skip empty plot: {output_name}")
        return

    label_map = {
        "without_trigger": "без триггера",
        "with_trigger": "с триггером",
    }

    fig, ax = plt.subplots(figsize=(14, 7))

    for trigger_state, group in plot_df.groupby("trigger_state"):
        group = group.sort_values("rows_base")
        ax.plot(
            group["rows_base"].to_numpy(),
            group[value_col].to_numpy(),
            marker="o",
            linewidth=2,
            label=label_map.get(trigger_state, str(trigger_state)),
        )

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(ylabel)
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()

    out = CHARTS / output_name
    fig.savefig(out, dpi=180)
    plt.close(fig)
    print(f"saved: {out}")


def make_overhead_df(df: pd.DataFrame) -> pd.DataFrame:
    pivot = df.pivot_table(
        index=["index_type", "rows_base"],
        columns="trigger_state",
        values=["avg_total_elapsed_ms", "avg_elapsed_ms_per_row"],
        aggfunc="mean",
    )

    pivot.columns = [f"{metric}_{state}" for metric, state in pivot.columns]
    pivot = pivot.reset_index()

    need_cols = [
        "avg_total_elapsed_ms_with_trigger",
        "avg_total_elapsed_ms_without_trigger",
        "avg_elapsed_ms_per_row_with_trigger",
        "avg_elapsed_ms_per_row_without_trigger",
    ]

    for col in need_cols:
        if col not in pivot.columns:
            raise KeyError(
                f"Не хватает столбца после pivot: {col}. "
                f"Проверь, что в CSV есть варианты with_trigger и without_trigger."
            )

    pivot["trigger_overhead_total_ms"] = (
        pivot["avg_total_elapsed_ms_with_trigger"]
        - pivot["avg_total_elapsed_ms_without_trigger"]
    )

    pivot["trigger_overhead_per_row_ms"] = (
        pivot["avg_elapsed_ms_per_row_with_trigger"]
        - pivot["avg_elapsed_ms_per_row_without_trigger"]
    )

    pivot["trigger_slowdown_ratio_total"] = (
        pivot["avg_total_elapsed_ms_with_trigger"]
        / pivot["avg_total_elapsed_ms_without_trigger"].replace(0, pd.NA)
    )

    pivot["trigger_slowdown_ratio_per_row"] = (
        pivot["avg_elapsed_ms_per_row_with_trigger"]
        / pivot["avg_elapsed_ms_per_row_without_trigger"].replace(0, pd.NA)
    )

    return pivot


def main():
    df = prepare_df()

    # Вариант "настоящий no_index": поиск НЕ по primary key / без lookup-индекса.
    # Если в данных есть no_lookup_index, используем его как честный вариант без индекса поиска.
    true_no_index_candidates = ["no_lookup_index", "no_index", "without_index"]
    existing_index_types = set(df["index_type"].astype(str))

    true_no_index = None
    for candidate in true_no_index_candidates:
        if candidate in existing_index_types:
            true_no_index = candidate
            break

    if true_no_index is None:
        true_no_index = sorted(existing_index_types)[0]
        print(f"WARNING: честный no_index не найден, использую первый вариант: {true_no_index}")

    # График 1: честный вариант без индекса поиска + все остальные, С ТРИГГЕРОМ.
    # Старый no_extra_index / no_index по primary key исключаем, если это не выбранный true_no_index.
    excluded_primary_key_like = {"no_extra_index", "primary_key", "pk_lookup", "no_index_pk"}

    graph1_df = df[
        (~df["index_type"].isin(excluded_primary_key_like))
        | (df["index_type"] == true_no_index)
    ].copy()

    plot_lines(
        graph1_df,
        value_col="avg_total_elapsed_ms",
        title="UPDATE: честный поиск без индекса и индексные варианты, с триггером",
        ylabel="Среднее время серии UPDATE, мс",
        output_name="21_update_true_no_index_vs_all_total_linear.png",
        trigger_state="with_trigger",
    )

    plot_lines(
        graph1_df,
        value_col="avg_elapsed_ms_per_row",
        title="UPDATE: среднее время одной обновленной строки, с триггером",
        ylabel="Среднее время одной обновленной строки, мс",
        output_name="21_update_true_no_index_vs_all_per_row_linear.png",
        trigger_state="with_trigger",
    )

    # Из остальных графиков убираем no_index по primary key.
    indexed_df = df[~df["index_type"].isin(excluded_primary_key_like | {true_no_index})].copy()

    # Общий график сравнения всех индексных вариантов: с триггером и без.
    # Чтобы линии не сливались по названию, делаем отдельный series_label.
    indexed_df["series_label"] = indexed_df.apply(
        lambda row: f"{row['index_type']} / "
        + ("с триггером" if row["trigger_state"] == "with_trigger" else "без триггера"),
        axis=1,
    )

    plot_lines(
        indexed_df,
        value_col="avg_total_elapsed_ms",
        title="UPDATE: все индексные варианты, сравнение с триггером и без триггера",
        ylabel="Среднее время серии UPDATE, мс",
        output_name="22_trigger_all_indexed_total_linear.png",
        series_col="series_label",
    )

    plot_lines(
        indexed_df,
        value_col="avg_elapsed_ms_per_row",
        title="UPDATE: все индексные варианты, среднее время одной строки",
        ylabel="Среднее время одной обновленной строки, мс",
        output_name="22_trigger_all_indexed_per_row_linear.png",
        series_col="series_label",
    )

    # Графики по каждому виду индекса: срабатывание триггера и без него.
    for index_type in sorted(indexed_df["index_type"].unique()):
        name = safe_name(index_type)

        plot_trigger_pair_for_index(
            indexed_df,
            index_type=index_type,
            value_col="avg_total_elapsed_ms",
            title=f"UPDATE: {index_type}, сравнение с триггером и без триггера",
            ylabel="Среднее время серии UPDATE, мс",
            output_name=f"22_trigger_{name}_total_linear.png",
        )

        plot_trigger_pair_for_index(
            indexed_df,
            index_type=index_type,
            value_col="avg_elapsed_ms_per_row",
            title=f"UPDATE: {index_type}, среднее время одной строки",
            ylabel="Среднее время одной обновленной строки, мс",
            output_name=f"22_trigger_{name}_per_row_linear.png",
        )

    # Общие графики накладных расходов триггера.
    overhead_df = make_overhead_df(indexed_df)

    plot_lines(
        overhead_df,
        value_col="trigger_overhead_total_ms",
        title="UPDATE: абсолютные накладные расходы триггера",
        ylabel="Дополнительное время из-за триггера, мс",
        output_name="22_trigger_overhead_total_ms_linear.png",
        series_col="index_type",
    )

    plot_lines(
        overhead_df,
        value_col="trigger_overhead_per_row_ms",
        title="UPDATE: накладные расходы триггера на одну строку",
        ylabel="Дополнительное время на одну строку, мс",
        output_name="22_trigger_overhead_per_row_ms_linear.png",
        series_col="index_type",
    )

    plot_lines(
        overhead_df,
        value_col="trigger_slowdown_ratio_total",
        title="UPDATE: коэффициент замедления из-за триггера",
        ylabel="Во сколько раз медленнее с триггером",
        output_name="22_trigger_slowdown_ratio_total_linear.png",
        series_col="index_type",
    )

    plot_lines(
        overhead_df,
        value_col="trigger_slowdown_ratio_per_row",
        title="UPDATE: коэффициент замедления на одну строку",
        ylabel="Во сколько раз медленнее с триггером",
        output_name="22_trigger_slowdown_ratio_per_row_linear.png",
        series_col="index_type",
    )

    print("\nDONE")
    print("Созданы графики с линейной осью X:")
    print("  charts/21_update_true_no_index_vs_all_*_linear.png")
    print("  charts/22_trigger_*_linear.png")


if __name__ == "__main__":
    main()
