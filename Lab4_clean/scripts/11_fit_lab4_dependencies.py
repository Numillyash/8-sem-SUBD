#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Авто-подбор эмпирических зависимостей для результатов ЛР-4 по СУБД.

Скрипт читает CSV-файлы из report/, подбирает несколько простых моделей
для каждой группы измерений и сохраняет:
  - report/11_dependency_fits.csv
  - report/11_dependency_formulas.txt
  - charts/11_fit_*.png

Запускать из корня Lab4_clean:
  python3 scripts/11_fit_lab4_dependencies.py

Или явно указать путь:
  python3 scripts/11_fit_lab4_dependencies.py --base /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
"""

from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.ticker import FuncFormatter


@dataclass
class FitResult:
    operation_name: str
    index_type: str
    metric: str
    model_name: str
    formula: str
    n_points: int
    r2: float
    adj_r2: float
    rmse: float
    mape_percent: float
    aicc: float
    coefficients: str


def fmt_big_number(x: float, _pos=None) -> str:
    try:
        if abs(x) >= 1000:
            return f"{int(x):,}".replace(",", " ")
        return f"{x:g}"
    except Exception:
        return str(x)


def safe_name(value: str) -> str:
    value = str(value).strip().lower()
    value = re.sub(r"[^a-zа-я0-9_\-]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value or "value"


def finite_xy(df: pd.DataFrame, x_col: str, y_col: str) -> tuple[np.ndarray, np.ndarray]:
    tmp = df[[x_col, y_col]].copy()
    tmp[x_col] = pd.to_numeric(tmp[x_col], errors="coerce")
    tmp[y_col] = pd.to_numeric(tmp[y_col], errors="coerce")
    tmp = tmp.replace([np.inf, -np.inf], np.nan).dropna()
    tmp = tmp[tmp[x_col] > 0]
    return tmp[x_col].to_numpy(dtype=float), tmp[y_col].to_numpy(dtype=float)


def linear_fit(features: np.ndarray, y: np.ndarray) -> np.ndarray:
    beta, *_ = np.linalg.lstsq(features, y, rcond=None)
    return beta


def score_model(y: np.ndarray, y_hat: np.ndarray, p: int) -> tuple[float, float, float, float, float]:
    n = len(y)
    resid = y - y_hat
    rss = float(np.sum(resid * resid))
    tss = float(np.sum((y - np.mean(y)) ** 2))

    r2 = 1.0 - rss / tss if tss > 0 else 1.0
    adj_r2 = 1.0 - (1.0 - r2) * (n - 1) / (n - p - 1) if n > p + 1 else float("nan")
    rmse = math.sqrt(rss / n) if n else float("nan")

    nonzero = np.abs(y) > 1e-12
    if np.any(nonzero):
        mape = float(np.mean(np.abs((y[nonzero] - y_hat[nonzero]) / y[nonzero])) * 100.0)
    else:
        mape = float("nan")

    rss_for_aic = max(rss, 1e-24)
    aic = n * math.log(rss_for_aic / n) + 2 * p
    if n > p + 1:
        aicc = aic + (2 * p * (p + 1)) / (n - p - 1)
    else:
        aicc = float("inf")

    return r2, adj_r2, rmse, mape, aicc


def coef(value: float, digits: int = 6) -> str:
    if abs(value) >= 1000 or (0 < abs(value) < 0.001):
        return f"{value:.{digits}e}"
    return f"{value:.{digits}f}".rstrip("0").rstrip(".")


def make_candidates(x: np.ndarray, y: np.ndarray) -> list[dict]:
    """Возвращает список моделей. N — количество строк, M = N / 1_000_000."""
    n_rows = x
    m = x / 1_000_000.0
    ln_n = np.log(n_rows)
    sqrt_m = np.sqrt(m)
    nlogn_scaled = m * ln_n

    candidates: list[dict] = []

    def add_linear_model(name: str, features: np.ndarray, formula_builder: Callable[[np.ndarray], str], predictor_builder: Callable[[np.ndarray], Callable[[np.ndarray], np.ndarray]]):
        beta = linear_fit(features, y)
        predictor = predictor_builder(beta)
        y_hat = predictor(x)
        candidates.append({
            "name": name,
            "p": len(beta),
            "beta": beta,
            "predict": predictor,
            "y_hat": y_hat,
            "formula": formula_builder(beta),
        })

    add_linear_model(
        "constant",
        np.ones((len(x), 1)),
        lambda b: f"y = {coef(b[0])}",
        lambda b: lambda xx: np.full_like(xx, b[0], dtype=float),
    )

    add_linear_model(
        "logarithmic",
        np.column_stack([np.ones_like(x), ln_n]),
        lambda b: f"y = {coef(b[0])} + {coef(b[1])}·ln(N)",
        lambda b: lambda xx: b[0] + b[1] * np.log(xx),
    )

    add_linear_model(
        "sqrt",
        np.column_stack([np.ones_like(x), sqrt_m]),
        lambda b: f"y = {coef(b[0])} + {coef(b[1])}·sqrt(N/1e6)",
        lambda b: lambda xx: b[0] + b[1] * np.sqrt(xx / 1_000_000.0),
    )

    add_linear_model(
        "linear",
        np.column_stack([np.ones_like(x), m]),
        lambda b: f"y = {coef(b[0])} + {coef(b[1])}·(N/1e6)",
        lambda b: lambda xx: b[0] + b[1] * (xx / 1_000_000.0),
    )

    add_linear_model(
        "n_log_n",
        np.column_stack([np.ones_like(x), nlogn_scaled]),
        lambda b: f"y = {coef(b[0])} + {coef(b[1])}·(N/1e6)·ln(N)",
        lambda b: lambda xx: b[0] + b[1] * (xx / 1_000_000.0) * np.log(xx),
    )

    add_linear_model(
        "log_plus_linear",
        np.column_stack([np.ones_like(x), ln_n, m]),
        lambda b: f"y = {coef(b[0])} + {coef(b[1])}·ln(N) + {coef(b[2])}·(N/1e6)",
        lambda b: lambda xx: b[0] + b[1] * np.log(xx) + b[2] * (xx / 1_000_000.0),
    )

    add_linear_model(
        "quadratic",
        np.column_stack([np.ones_like(x), m, m * m]),
        lambda b: f"y = {coef(b[0])} + {coef(b[1])}·(N/1e6) + {coef(b[2])}·(N/1e6)^2",
        lambda b: lambda xx: b[0] + b[1] * (xx / 1_000_000.0) + b[2] * (xx / 1_000_000.0) ** 2,
    )

    # Степенная модель y = a*N^b. Подбирается в логарифмах, затем оценивается в исходной шкале.
    if np.all(y > 0):
        log_y = np.log(y)
        features = np.column_stack([np.ones_like(x), ln_n])
        beta = linear_fit(features, log_y)
        a = math.exp(beta[0])
        b = beta[1]

        def predict_power(xx: np.ndarray) -> np.ndarray:
            return a * np.power(xx, b)

        candidates.append({
            "name": "power",
            "p": 2,
            "beta": np.array([a, b], dtype=float),
            "predict": predict_power,
            "y_hat": predict_power(x),
            "formula": f"y = {coef(a)}·N^{coef(b)}",
        })

    return candidates


def best_fit(operation_name: str, index_type: str, metric: str, x: np.ndarray, y: np.ndarray) -> tuple[FitResult, Callable[[np.ndarray], np.ndarray]] | None:
    if len(x) < 3 or len(np.unique(x)) < 3:
        return None

    best = None
    best_score = float("inf")

    for cand in make_candidates(x, y):
        y_hat = cand["y_hat"]
        if not np.all(np.isfinite(y_hat)):
            continue
        r2, adj_r2, rmse, mape, aicc = score_model(y, y_hat, cand["p"])
        # Главный критерий — AICc, чтобы не выбирать слишком сложную модель по одному R^2.
        # При равенстве выигрывает модель с большим adj_R2.
        tie_breaker = -adj_r2 if np.isfinite(adj_r2) else 0.0
        score = (aicc, tie_breaker, cand["p"])
        if score < (best_score, 0, 999):
            best_score = aicc
            coeffs = "; ".join(coef(v) for v in cand["beta"])
            result = FitResult(
                operation_name=operation_name,
                index_type=index_type,
                metric=metric,
                model_name=cand["name"],
                formula=cand["formula"],
                n_points=len(x),
                r2=r2,
                adj_r2=adj_r2,
                rmse=rmse,
                mape_percent=mape,
                aicc=aicc,
                coefficients=coeffs,
            )
            best = (result, cand["predict"])

    return best


def prepare_performance_data(report_dir: Path) -> pd.DataFrame:
    extended = report_dir / "10_extended_all_sizes_aggregated.csv"
    if extended.exists():
        df = pd.read_csv(extended)
        return df

    frames = []
    select_file = report_dir / "03_select_index_measurements.csv"
    if select_file.exists():
        df = pd.read_csv(select_file)
        df = df.rename(columns={"index_state": "index_type", "rows_before": "rows_base"})
        df["operation_name"] = "select"
        if "avg_elapsed_ms" in df.columns:
            df["avg_elapsed_ms_per_operation"] = df["avg_elapsed_ms"]
            df["avg_total_elapsed_ms"] = df["avg_elapsed_ms"] * df.get("probes_min", 1)
        frames.append(df)

    insert_file = report_dir / "04_insert_indexes_measurements.csv"
    if insert_file.exists():
        df = pd.read_csv(insert_file)
        df["operation_name"] = "insert"
        if "avg_total_elapsed_ms" not in df.columns and "avg_elapsed_ms" in df.columns:
            df["avg_total_elapsed_ms"] = df["avg_elapsed_ms"]
        if "avg_elapsed_ms_per_operation" not in df.columns and "avg_elapsed_ms_per_row" in df.columns:
            df["avg_elapsed_ms_per_operation"] = df["avg_elapsed_ms_per_row"]
        frames.append(df)

    update_file = report_dir / "05_update_indexes_measurements.csv"
    if update_file.exists():
        df = pd.read_csv(update_file)
        df["operation_name"] = "update"
        if "avg_total_elapsed_ms" not in df.columns and "avg_elapsed_ms" in df.columns:
            df["avg_total_elapsed_ms"] = df["avg_elapsed_ms"]
        if "avg_elapsed_ms_per_operation" not in df.columns and "avg_elapsed_ms_per_row" in df.columns:
            df["avg_elapsed_ms_per_operation"] = df["avg_elapsed_ms_per_row"]
        frames.append(df)

    if not frames:
        raise FileNotFoundError("Не найден ни 10_extended_all_sizes_aggregated.csv, ни базовые CSV с измерениями.")

    return pd.concat(frames, ignore_index=True)


def plot_fit_chart(
    df: pd.DataFrame,
    fits: dict[tuple[str, str, str], Callable[[np.ndarray], np.ndarray]],
    operation_name: str,
    metric: str,
    y_label: str,
    out_path: Path,
    title: str,
    log_x: bool = False,
) -> None:
    sub = df[(df["operation_name"] == operation_name) & df[metric].notna()].copy()
    if sub.empty:
        return

    fig, ax = plt.subplots(figsize=(13, 6.5))

    for index_type, g in sub.groupby("index_type"):
        g = g.sort_values("rows_base")
        x = g["rows_base"].to_numpy(dtype=float)
        y = g[metric].to_numpy(dtype=float)
        ax.scatter(x, y, s=28, label=f"{index_type}: факт")

        key = (operation_name, index_type, metric)
        predictor = fits.get(key)
        if predictor is not None:
            x_min = max(float(np.min(x)), 1.0)
            x_max = float(np.max(x))
            if log_x:
                x_line = np.geomspace(x_min, x_max, 300)
            else:
                x_line = np.linspace(x_min, x_max, 300)
            y_line = predictor(x_line)
            ax.plot(x_line, y_line, linewidth=1.8, label=f"{index_type}: модель")

    ax.set_title(title)
    ax.set_xlabel("Количество строк в таблице, N")
    ax.set_ylabel(y_label)
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_big_number))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_big_number))
    if log_x:
        ax.set_xscale("log")
    ax.grid(True, alpha=0.25)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(out_path, dpi=200)
    plt.close(fig)


def plot_size_fits(report_dir: Path, charts_dir: Path, all_results: list[FitResult], all_predictors: dict[tuple[str, str, str], Callable[[np.ndarray], np.ndarray]]) -> None:
    sizes_file = report_dir / "10_extended_all_sizes_sizes.csv"
    if not sizes_file.exists():
        return

    df = pd.read_csv(sizes_file)
    metrics = [
        ("relation_bytes", "Размер таблицы, байт"),
        ("indexes_bytes", "Размер индексов, байт"),
        ("total_bytes", "Общий размер, байт"),
    ]

    for metric, _label in metrics:
        if metric not in df.columns:
            continue
        for (operation_name, index_type), g in df.groupby(["operation_name", "index_type"]):
            x, y = finite_xy(g, "rows_base", metric)
            fit = best_fit(f"size_{operation_name}", index_type, metric, x, y)
            if fit is None:
                continue
            result, predictor = fit
            all_results.append(result)
            all_predictors[(f"size_{operation_name}", index_type, metric)] = predictor

    for operation_name in sorted(df["operation_name"].dropna().unique()):
        for metric, label in metrics:
            if metric not in df.columns:
                continue
            temp = df.copy()
            temp["operation_name"] = "size_" + temp["operation_name"].astype(str)
            plot_fit_chart(
                temp,
                all_predictors,
                f"size_{operation_name}",
                metric,
                label,
                charts_dir / f"11_fit_size_{safe_name(operation_name)}_{safe_name(metric)}.png",
                f"Авто-подбор зависимости размера: {operation_name}, {metric}",
                log_x=False,
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Авто-подбор формул для результатов ЛР-4")
    parser.add_argument("--base", type=Path, default=Path.cwd(), help="Корень Lab4_clean")
    parser.add_argument("--no-size-fits", action="store_true", help="Не подбирать зависимости для размеров таблиц/индексов")
    args = parser.parse_args()

    base = args.base.resolve()
    report_dir = base / "report"
    charts_dir = base / "charts"
    report_dir.mkdir(parents=True, exist_ok=True)
    charts_dir.mkdir(parents=True, exist_ok=True)

    perf = prepare_performance_data(report_dir)

    required = {"operation_name", "index_type", "rows_base"}
    missing = required - set(perf.columns)
    if missing:
        raise ValueError(f"В CSV нет обязательных колонок: {sorted(missing)}")

    metric_specs = []
    if "avg_total_elapsed_ms" in perf.columns:
        metric_specs.append(("avg_total_elapsed_ms", "Среднее время серии/пакета, мс"))
    if "avg_elapsed_ms_per_operation" in perf.columns:
        metric_specs.append(("avg_elapsed_ms_per_operation", "Среднее время одной операции, мс"))

    if not metric_specs:
        raise ValueError("Не найдены метрики avg_total_elapsed_ms или avg_elapsed_ms_per_operation")

    results: list[FitResult] = []
    predictors: dict[tuple[str, str, str], Callable[[np.ndarray], np.ndarray]] = {}

    for metric, _label in metric_specs:
        for (operation_name, index_type), g in perf.groupby(["operation_name", "index_type"]):
            if metric not in g.columns:
                continue
            x, y = finite_xy(g, "rows_base", metric)
            fit = best_fit(operation_name, index_type, metric, x, y)
            if fit is None:
                continue
            result, predictor = fit
            results.append(result)
            predictors[(operation_name, index_type, metric)] = predictor

    for operation_name in sorted(perf["operation_name"].dropna().unique()):
        for metric, label in metric_specs:
            plot_fit_chart(
                perf,
                predictors,
                operation_name,
                metric,
                label,
                charts_dir / f"11_fit_{safe_name(operation_name)}_{safe_name(metric)}.png",
                f"Авто-подбор зависимости: {operation_name}, {metric}",
                log_x=False,
            )
            plot_fit_chart(
                perf,
                predictors,
                operation_name,
                metric,
                label,
                charts_dir / f"11_fit_{safe_name(operation_name)}_{safe_name(metric)}_logx.png",
                f"Авто-подбор зависимости, логарифмическая ось X: {operation_name}, {metric}",
                log_x=True,
            )

    if not args.no_size_fits:
        plot_size_fits(report_dir, charts_dir, results, predictors)

    out_csv = report_dir / "11_dependency_fits.csv"
    out_txt = report_dir / "11_dependency_formulas.txt"

    result_df = pd.DataFrame([r.__dict__ for r in results])
    result_df = result_df.sort_values(["operation_name", "metric", "index_type", "aicc"])
    result_df.to_csv(out_csv, index=False)

    lines = []
    lines.append("Автоматически подобранные эмпирические зависимости")
    lines.append("N — количество строк в таблице. Значения являются аппроксимациями по экспериментальным точкам, а не теоретическим доказательством сложности.")
    lines.append("")

    for operation_name, g1 in result_df.groupby("operation_name"):
        lines.append(f"[{operation_name}]")
        for metric, g2 in g1.groupby("metric"):
            lines.append(f"  Метрика: {metric}")
            for _, row in g2.iterrows():
                lines.append(
                    f"    {row['index_type']}: {row['formula']}; "
                    f"модель={row['model_name']}; R^2={row['r2']:.5f}; "
                    f"RMSE={row['rmse']:.6g}; MAPE={row['mape_percent']:.3f}%"
                )
            lines.append("")
        lines.append("")

    out_txt.write_text("\n".join(lines), encoding="utf-8")

    print("saved:")
    print(f"  {out_csv}")
    print(f"  {out_txt}")
    print(f"  charts/11_fit_*.png")
    print()
    print("Лучшие зависимости по AICc:")
    preview_cols = ["operation_name", "index_type", "metric", "model_name", "formula", "r2", "rmse", "mape_percent"]
    with pd.option_context("display.max_rows", 200, "display.max_colwidth", 120, "display.width", 220):
        print(result_df[preview_cols].to_string(index=False))


if __name__ == "__main__":
    main()
