from __future__ import annotations

from pathlib import Path
import math
import re
import numpy as np
import pandas as pd
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")
REPORT = BASE / "report"
CHARTS = BASE / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)

AGG_PATH = REPORT / "12_dense_under_1m_aggregated.csv"
SIZES_PATH = REPORT / "12_dense_under_1m_sizes.csv"

OUT_CSV = REPORT / "12_dense_dependency_fits_filtered_from_50.csv"
OUT_TXT = REPORT / "12_dense_dependency_formulas_filtered_from_50.txt"

MIN_ROWS_FOR_FIT = 50

METRICS = [
    "avg_total_elapsed_ms",
    "avg_elapsed_ms_per_operation",
]

SIZE_METRICS = [
    "relation_bytes",
    "indexes_bytes",
    "total_bytes",
]


def safe_name(s: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_]+", "_", s).strip("_").lower()


def fmt_number(x, _):
    try:
        if abs(x) >= 1000:
            return f"{int(x):,}".replace(",", " ")
        return f"{x:g}"
    except Exception:
        return str(x)


def aicc(y: np.ndarray, y_hat: np.ndarray, k: int) -> float:
    n = len(y)
    rss = float(np.sum((y - y_hat) ** 2))
    if rss <= 0:
        rss = 1e-30
    if n <= k + 1:
        return float("inf")
    aic = n * math.log(rss / n) + 2 * k
    return aic + (2 * k * (k + 1)) / (n - k - 1)


def metrics(y: np.ndarray, y_hat: np.ndarray) -> tuple[float, float, float]:
    ss_res = float(np.sum((y - y_hat) ** 2))
    ss_tot = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
    rmse = math.sqrt(ss_res / len(y))
    nonzero = np.abs(y) > 1e-12
    if np.any(nonzero):
        mape = float(np.mean(np.abs((y[nonzero] - y_hat[nonzero]) / y[nonzero])) * 100)
    else:
        mape = float("nan")
    return r2, rmse, mape


def design_matrix(model: str, x: np.ndarray) -> np.ndarray:
    xm = x / 1_000_000.0
    ln = np.log(x)

    if model == "constant":
        return np.column_stack([np.ones_like(x)])

    if model == "logarithmic":
        return np.column_stack([np.ones_like(x), ln])

    if model == "sqrt":
        return np.column_stack([np.ones_like(x), np.sqrt(xm)])

    if model == "linear":
        return np.column_stack([np.ones_like(x), xm])

    if model == "n_log_n":
        return np.column_stack([np.ones_like(x), xm * ln])

    if model == "quadratic":
        return np.column_stack([np.ones_like(x), xm, xm ** 2])

    if model == "log_plus_linear":
        return np.column_stack([np.ones_like(x), ln, xm])

    if model == "power":
        return np.column_stack([np.ones_like(x), ln])

    raise ValueError(model)


def formula_text(model: str, coef: np.ndarray, power_model: bool = False) -> str:
    def c(v):
        if abs(v) >= 10_000 or (0 < abs(v) < 0.001):
            return f"{v:.6e}"
        return f"{v:.6g}"

    if model == "constant":
        return f"y = {c(coef[0])}"

    if model == "logarithmic":
        return f"y = {c(coef[0])} + {c(coef[1])}·ln(N)"

    if model == "sqrt":
        return f"y = {c(coef[0])} + {c(coef[1])}·sqrt(N/1e6)"

    if model == "linear":
        return f"y = {c(coef[0])} + {c(coef[1])}·(N/1e6)"

    if model == "n_log_n":
        return f"y = {c(coef[0])} + {c(coef[1])}·(N/1e6)·ln(N)"

    if model == "quadratic":
        return f"y = {c(coef[0])} + {c(coef[1])}·(N/1e6) + {c(coef[2])}·(N/1e6)^2"

    if model == "log_plus_linear":
        return f"y = {c(coef[0])} + {c(coef[1])}·ln(N) + {c(coef[2])}·(N/1e6)"

    if model == "power":
        a = math.exp(coef[0])
        b = coef[1]
        return f"y = {c(a)}·N^{c(b)}"

    return "unknown"


def fit_one(df: pd.DataFrame, operation_name: str, index_type: str, metric_name: str) -> dict:
    fit_df = df[df["rows_base"] >= MIN_ROWS_FOR_FIT].copy()
    fit_df = fit_df.sort_values("rows_base")

    x = pd.to_numeric(fit_df["rows_base"], errors="coerce").to_numpy(dtype=float)
    y = pd.to_numeric(fit_df[metric_name], errors="coerce").to_numpy(dtype=float)

    mask = np.isfinite(x) & np.isfinite(y)
    x = x[mask]
    y = y[mask]

    candidates = [
        "constant",
        "logarithmic",
        "sqrt",
        "linear",
        "n_log_n",
        "quadratic",
        "log_plus_linear",
    ]

    if np.all(y > 0):
        candidates.append("power")

    best = None

    for model in candidates:
        if model == "power":
            X = design_matrix(model, x)
            yy = np.log(y)
            coef, *_ = np.linalg.lstsq(X, yy, rcond=None)
            y_hat = np.exp(X @ coef)
            k = len(coef)
        else:
            X = design_matrix(model, x)
            coef, *_ = np.linalg.lstsq(X, y, rcond=None)
            y_hat = X @ coef
            k = len(coef)

        model_aicc = aicc(y, y_hat, k)
        r2, rmse, mape = metrics(y, y_hat)

        row = {
            "operation_name": operation_name,
            "index_type": index_type,
            "metric": metric_name,
            "min_rows_for_fit": MIN_ROWS_FOR_FIT,
            "points_used_for_fit": len(x),
            "model_name": model,
            "formula": formula_text(model, coef),
            "aicc": model_aicc,
            "r2": r2,
            "rmse": rmse,
            "mape_percent": mape,
        }

        if best is None or row["aicc"] < best["aicc"]:
            best = row

    assert best is not None
    return best


def predict(model: str, formula: str, x: np.ndarray, source_df: pd.DataFrame, metric_name: str) -> np.ndarray:
    # Для графиков проще заново подогнать выбранную модель по тем же filtered-точкам.
    fit_df = source_df[source_df["rows_base"] >= MIN_ROWS_FOR_FIT].sort_values("rows_base")
    x_fit = pd.to_numeric(fit_df["rows_base"], errors="coerce").to_numpy(dtype=float)
    y_fit = pd.to_numeric(fit_df[metric_name], errors="coerce").to_numpy(dtype=float)
    mask = np.isfinite(x_fit) & np.isfinite(y_fit)
    x_fit = x_fit[mask]
    y_fit = y_fit[mask]

    if model == "power":
        X = design_matrix(model, x_fit)
        coef, *_ = np.linalg.lstsq(X, np.log(y_fit), rcond=None)
        return np.exp(design_matrix(model, x) @ coef)

    X = design_matrix(model, x_fit)
    coef, *_ = np.linalg.lstsq(X, y_fit, rcond=None)
    return design_matrix(model, x) @ coef


def save_plot(df: pd.DataFrame, best_rows: list[dict], operation_name: str, metric_name: str, filename: str, logx: bool = False) -> None:
    op_df = df[df["operation_name"] == operation_name].copy()
    if op_df.empty:
        return

    fig, ax = plt.subplots(figsize=(13, 6))

    for index_type, part in op_df.groupby("index_type"):
        part = part.sort_values("rows_base")
        x_all = pd.to_numeric(part["rows_base"], errors="coerce").to_numpy(dtype=float)
        y_all = pd.to_numeric(part[metric_name], errors="coerce").to_numpy(dtype=float)

        small = x_all < MIN_ROWS_FOR_FIT
        used = x_all >= MIN_ROWS_FOR_FIT

        ax.scatter(x_all[used], y_all[used], label=f"{index_type}: fit points", s=28)
        if np.any(small):
            ax.scatter(x_all[small], y_all[small], marker="x", s=55, label=f"{index_type}: excluded < {MIN_ROWS_FOR_FIT}")

        best = next(
            r for r in best_rows
            if r["operation_name"] == operation_name
            and r["index_type"] == index_type
            and r["metric"] == metric_name
        )

        x_line = np.linspace(MIN_ROWS_FOR_FIT, max(x_all), 300)
        y_line = predict(best["model_name"], best["formula"], x_line, part, metric_name)
        ax.plot(x_line, y_line, linewidth=2)

    if logx:
        ax.set_xscale("log")

    ax.set_title(f"{operation_name.upper()}: подбор зависимости для {metric_name}, fit N >= {MIN_ROWS_FOR_FIT}")
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(metric_name)
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, which="both" if logx else "major", alpha=0.25)
    ax.legend(fontsize=8)

    fig.tight_layout()
    fig.savefig(CHARTS / filename, dpi=200)
    plt.close(fig)


def main() -> None:
    agg = pd.read_csv(AGG_PATH)
    sizes = pd.read_csv(SIZES_PATH)

    all_rows: list[dict] = []

    for operation_name in ["select", "insert", "update"]:
        op_df = agg[agg["operation_name"] == operation_name].copy()
        if op_df.empty:
            continue

        for index_type in sorted(op_df["index_type"].dropna().unique()):
            group = op_df[op_df["index_type"] == index_type].copy()
            for metric_name in METRICS:
                if metric_name in group.columns:
                    all_rows.append(fit_one(group, operation_name, index_type, metric_name))

    for operation_name in ["size_select", "size_insert", "size_update"]:
        source_op = operation_name.replace("size_", "")
        op_df = sizes[sizes["operation_name"] == source_op].copy()
        if op_df.empty:
            continue

        op_df["operation_name"] = operation_name

        for index_type in sorted(op_df["index_type"].dropna().unique()):
            group = op_df[op_df["index_type"] == index_type].copy()
            for metric_name in SIZE_METRICS:
                if metric_name in group.columns:
                    all_rows.append(fit_one(group, operation_name, index_type, metric_name))

    out = pd.DataFrame(all_rows).sort_values(["operation_name", "metric", "index_type"])
    out.to_csv(OUT_CSV, index=False)

    with OUT_TXT.open("w", encoding="utf-8") as f:
        f.write("Подбор эмпирических зависимостей по dense under 1M данным\n")
        f.write(f"Точки с rows_base < {MIN_ROWS_FOR_FIT} исключены из подбора формул.\n")
        f.write("Исключенные точки остаются экспериментальными измерениями, но не используются в регрессии.\n\n")

        for _, row in out.iterrows():
            f.write(
                f"[{row['operation_name']} | {row['index_type']} | {row['metric']}]\n"
                f"model: {row['model_name']}\n"
                f"formula: {row['formula']}\n"
                f"R2: {row['r2']:.6f}, RMSE: {row['rmse']:.6f}, MAPE: {row['mape_percent']:.3f}%\n"
                f"points used: {row['points_used_for_fit']}, min rows for fit: {row['min_rows_for_fit']}\n\n"
            )

    for operation_name in ["select", "insert", "update"]:
        for metric_name in METRICS:
            if metric_name in agg.columns:
                save_plot(
                    agg,
                    all_rows,
                    operation_name,
                    metric_name,
                    f"12_fit_filtered_{operation_name}_{metric_name}.png",
                    logx=False,
                )
                save_plot(
                    agg,
                    all_rows,
                    operation_name,
                    metric_name,
                    f"12_fit_filtered_{operation_name}_{metric_name}_logx.png",
                    logx=True,
                )

    print("saved:")
    print(" ", OUT_CSV)
    print(" ", OUT_TXT)
    print("  charts/12_fit_filtered_*.png")

    print("\nЛучшие зависимости по AICc, fit N >= 50:")
    print(out[["operation_name", "index_type", "metric", "model_name", "formula", "r2", "rmse", "mape_percent"]].to_string(index=False))


if __name__ == "__main__":
    main()
