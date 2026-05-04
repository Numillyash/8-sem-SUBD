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

OUT_ALL_CSV = REPORT / "13_teacher_expected_fits_all_models.csv"
OUT_SELECTED_CSV = REPORT / "13_teacher_expected_fits_selected.csv"
OUT_TXT = REPORT / "13_teacher_expected_formulas.txt"

MIN_ROWS_FOR_FIT = 50

MODELS = [
    "constant",
    "logarithmic",
    "linear",
    "exponential",
]

TIME_METRICS = [
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


def coef_fmt(v: float) -> str:
    if abs(v) >= 10_000 or (0 < abs(v) < 0.001):
        return f"{v:.6e}"
    return f"{v:.6g}"


def aicc(y: np.ndarray, y_hat: np.ndarray, k: int) -> float:
    n = len(y)
    rss = float(np.sum((y - y_hat) ** 2))
    if rss <= 0:
        rss = 1e-30
    if n <= k + 1:
        return float("inf")
    aic = n * math.log(rss / n) + 2 * k
    return aic + (2 * k * (k + 1)) / (n - k - 1)


def fit_quality(y: np.ndarray, y_hat: np.ndarray) -> tuple[float, float, float]:
    ss_res = float(np.sum((y - y_hat) ** 2))
    ss_tot = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
    rmse = math.sqrt(ss_res / len(y))

    nonzero = np.abs(y) > 1e-12
    if np.any(nonzero):
        mape = float(np.mean(np.abs((y[nonzero] - y_hat[nonzero]) / y[nonzero])) * 100.0)
    else:
        mape = float("nan")

    return r2, rmse, mape


def design_matrix(model_name: str, n_rows: np.ndarray) -> np.ndarray:
    x = n_rows / 1_000_000.0

    if model_name == "constant":
        return np.column_stack([np.ones_like(n_rows)])

    if model_name == "logarithmic":
        return np.column_stack([np.ones_like(n_rows), np.log(n_rows)])

    if model_name == "linear":
        return np.column_stack([np.ones_like(n_rows), x])

    if model_name == "exponential":
        return np.column_stack([np.ones_like(n_rows), x])

    raise ValueError(f"Unknown model: {model_name}")


def formula_from_coef(model_name: str, coef: np.ndarray) -> str:
    if model_name == "constant":
        return f"y = {coef_fmt(coef[0])}"

    if model_name == "logarithmic":
        return f"y = {coef_fmt(coef[0])} + {coef_fmt(coef[1])}·ln(N)"

    if model_name == "linear":
        return f"y = {coef_fmt(coef[0])} + {coef_fmt(coef[1])}·(N/1e6)"

    if model_name == "exponential":
        a = math.exp(coef[0])
        b = coef[1]
        return f"y = {coef_fmt(a)}·exp({coef_fmt(b)}·(N/1e6))"

    raise ValueError(model_name)


def fit_model(model_name: str, n_rows: np.ndarray, y: np.ndarray) -> dict | None:
    if model_name == "exponential":
        if np.any(y <= 0):
            return None

        x = design_matrix(model_name, n_rows)
        coef, *_ = np.linalg.lstsq(x, np.log(y), rcond=None)
        y_hat = np.exp(x @ coef)
    else:
        x = design_matrix(model_name, n_rows)
        coef, *_ = np.linalg.lstsq(x, y, rcond=None)
        y_hat = x @ coef

    r2, rmse, mape = fit_quality(y, y_hat)

    return {
        "model_name": model_name,
        "formula": formula_from_coef(model_name, coef),
        "coef_0": float(coef[0]) if len(coef) > 0 else float("nan"),
        "coef_1": float(coef[1]) if len(coef) > 1 else float("nan"),
        "r2": r2,
        "rmse": rmse,
        "mape_percent": mape,
        "aicc": aicc(y, y_hat, len(coef)),
    }


def expected_priority(operation_name: str, index_type: str, metric_name: str) -> list[str]:
    idx = str(index_type).lower()
    op = str(operation_name).lower()

    if op.startswith("size_"):
        if metric_name == "indexes_bytes" and (
            idx in {"no_index", "no_extra_index"}
            or "without_index" in idx
        ):
            return ["constant", "linear", "logarithmic", "exponential"]
        return ["linear", "logarithmic", "constant", "exponential"]

    if op == "select":
        if "without_index" in idx:
            return ["linear", "logarithmic", "constant", "exponential"]
        if "btree" in idx:
            return ["logarithmic", "constant", "linear", "exponential"]
        return ["linear", "logarithmic", "constant", "exponential"]

    if op == "insert":
        if idx == "no_index":
            return ["constant", "logarithmic", "linear", "exponential"]
        return ["logarithmic", "linear", "constant", "exponential"]

    if op == "update":
        if idx == "no_extra_index":
            return ["constant", "logarithmic", "linear", "exponential"]
        return ["logarithmic", "linear", "constant", "exponential"]

    return ["linear", "logarithmic", "constant", "exponential"]


def prepare_fit_arrays(df: pd.DataFrame, metric_name: str) -> tuple[np.ndarray, np.ndarray]:
    fit_df = df[df["rows_base"] >= MIN_ROWS_FOR_FIT].sort_values("rows_base").copy()

    x = pd.to_numeric(fit_df["rows_base"], errors="coerce").to_numpy(dtype=float)
    y = pd.to_numeric(fit_df[metric_name], errors="coerce").to_numpy(dtype=float)

    mask = np.isfinite(x) & np.isfinite(y)
    return x[mask], y[mask]


def fit_group(
    df: pd.DataFrame,
    operation_name: str,
    index_type: str,
    metric_name: str,
) -> tuple[list[dict], dict]:
    x, y = prepare_fit_arrays(df, metric_name)

    if len(x) < 4:
        raise ValueError(
            f"Too few points for {operation_name}/{index_type}/{metric_name}: {len(x)}"
        )

    rows: list[dict] = []

    priority = expected_priority(operation_name, index_type, metric_name)

    for model_name in MODELS:
        fitted = fit_model(model_name, x, y)
        if fitted is None:
            continue

        priority_rank = priority.index(model_name) + 1 if model_name in priority else 999

        row = {
            "operation_name": operation_name,
            "index_type": index_type,
            "metric": metric_name,
            "min_rows_for_fit": MIN_ROWS_FOR_FIT,
            "points_used_for_fit": len(x),
            "model_name": model_name,
            "priority_rank": priority_rank,
            **fitted,
        }
        rows.append(row)

    if not rows:
        raise ValueError(f"No fitted models for {operation_name}/{index_type}/{metric_name}")

    statistical = min(rows, key=lambda r: r["aicc"])

    # Преподавательская модель: первая теоретически ожидаемая модель,
    # которую удалось корректно подогнать.
    teacher = None
    for model_name in priority:
        for row in rows:
            if row["model_name"] == model_name:
                teacher = row
                break
        if teacher is not None:
            break

    assert teacher is not None

    selected = {
        "operation_name": operation_name,
        "index_type": index_type,
        "metric": metric_name,
        "min_rows_for_fit": MIN_ROWS_FOR_FIT,
        "points_used_for_fit": len(x),

        "teacher_model_name": teacher["model_name"],
        "teacher_formula": teacher["formula"],
        "teacher_r2": teacher["r2"],
        "teacher_rmse": teacher["rmse"],
        "teacher_mape_percent": teacher["mape_percent"],
        "teacher_aicc": teacher["aicc"],

        "statistical_model_name": statistical["model_name"],
        "statistical_formula": statistical["formula"],
        "statistical_r2": statistical["r2"],
        "statistical_rmse": statistical["rmse"],
        "statistical_mape_percent": statistical["mape_percent"],
        "statistical_aicc": statistical["aicc"],

        "models_match": "YES" if teacher["model_name"] == statistical["model_name"] else "NO",
        "expected_priority": " > ".join(priority),
    }

    return rows, selected


def predict_model(model_name: str, coef_0: float, coef_1: float, n_rows: np.ndarray) -> np.ndarray:
    if model_name == "constant":
        return np.full_like(n_rows, coef_0, dtype=float)

    if model_name == "logarithmic":
        return coef_0 + coef_1 * np.log(n_rows)

    if model_name == "linear":
        return coef_0 + coef_1 * (n_rows / 1_000_000.0)

    if model_name == "exponential":
        return np.exp(coef_0 + coef_1 * (n_rows / 1_000_000.0))

    raise ValueError(model_name)


def get_teacher_fit_row(
    all_rows: pd.DataFrame,
    operation_name: str,
    index_type: str,
    metric_name: str,
    selected_rows: pd.DataFrame,
) -> pd.Series:
    sel = selected_rows[
        (selected_rows["operation_name"] == operation_name)
        & (selected_rows["index_type"] == index_type)
        & (selected_rows["metric"] == metric_name)
    ].iloc[0]

    model = sel["teacher_model_name"]

    fit_row = all_rows[
        (all_rows["operation_name"] == operation_name)
        & (all_rows["index_type"] == index_type)
        & (all_rows["metric"] == metric_name)
        & (all_rows["model_name"] == model)
    ].iloc[0]

    return fit_row


def save_teacher_plot(
    source_df: pd.DataFrame,
    all_rows_df: pd.DataFrame,
    selected_df: pd.DataFrame,
    operation_name: str,
    metric_name: str,
    filename: str,
    logx: bool = False,
) -> None:
    df = source_df[source_df["operation_name"] == operation_name].copy()
    if df.empty:
        return

    fig, ax = plt.subplots(figsize=(13, 6))

    excluded_label_used = False

    for index_type in sorted(df["index_type"].dropna().unique()):
        part = df[df["index_type"] == index_type].sort_values("rows_base").copy()

        x_all = pd.to_numeric(part["rows_base"], errors="coerce").to_numpy(dtype=float)
        y_all = pd.to_numeric(part[metric_name], errors="coerce").to_numpy(dtype=float)

        mask = np.isfinite(x_all) & np.isfinite(y_all)
        x_all = x_all[mask]
        y_all = y_all[mask]

        fit_mask = x_all >= MIN_ROWS_FOR_FIT
        excluded_mask = x_all < MIN_ROWS_FOR_FIT

        ax.scatter(
            x_all[fit_mask],
            y_all[fit_mask],
            s=28,
            label=f"{index_type}: точки fit",
        )

        if np.any(excluded_mask):
            ax.scatter(
                x_all[excluded_mask],
                y_all[excluded_mask],
                marker="x",
                s=60,
                label=f"исключено < {MIN_ROWS_FOR_FIT}" if not excluded_label_used else None,
            )
            excluded_label_used = True

        fit_row = get_teacher_fit_row(
            all_rows_df,
            operation_name,
            index_type,
            metric_name,
            selected_df,
        )

        x_line = np.linspace(MIN_ROWS_FOR_FIT, float(np.max(x_all)), 300)
        y_line = predict_model(
            str(fit_row["model_name"]),
            float(fit_row["coef_0"]),
            float(fit_row["coef_1"]) if not pd.isna(fit_row["coef_1"]) else 0.0,
            x_line,
        )

        ax.plot(
            x_line,
            y_line,
            linewidth=2,
            label=f"{index_type}: {fit_row['model_name']}",
        )

    if logx:
        ax.set_xscale("log")

    ax.set_title(
        f"{operation_name.upper()}: ожидаемая модель для {metric_name}, fit N >= {MIN_ROWS_FOR_FIT}"
    )
    ax.set_xlabel("Количество строк в таблице")
    ax.set_ylabel(metric_name)
    ax.xaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_number))
    ax.grid(True, which="both" if logx else "major", alpha=0.25)
    ax.legend(fontsize=8)

    fig.tight_layout()
    out = CHARTS / filename
    fig.savefig(out, dpi=200)
    plt.close(fig)
    print("saved:", out)


def main() -> None:
    agg = pd.read_csv(AGG_PATH)
    sizes = pd.read_csv(SIZES_PATH)

    if "avg_total_elapsed_seconds" not in agg.columns and "avg_total_elapsed_ms" in agg.columns:
        agg["avg_total_elapsed_seconds"] = agg["avg_total_elapsed_ms"] / 1000.0

    all_fit_rows: list[dict] = []
    selected_rows: list[dict] = []

    for operation_name in ["select", "insert", "update"]:
        op_df = agg[agg["operation_name"] == operation_name].copy()
        if op_df.empty:
            continue

        for index_type in sorted(op_df["index_type"].dropna().unique()):
            group = op_df[op_df["index_type"] == index_type].copy()

            for metric_name in TIME_METRICS:
                if metric_name not in group.columns:
                    continue

                rows, selected = fit_group(
                    group,
                    operation_name,
                    index_type,
                    metric_name,
                )

                all_fit_rows.extend(rows)
                selected_rows.append(selected)

    for source_operation in ["select", "insert", "update"]:
        op_df = sizes[sizes["operation_name"] == source_operation].copy()
        if op_df.empty:
            continue

        operation_name = f"size_{source_operation}"
        op_df["operation_name"] = operation_name

        for index_type in sorted(op_df["index_type"].dropna().unique()):
            group = op_df[op_df["index_type"] == index_type].copy()

            for metric_name in SIZE_METRICS:
                if metric_name not in group.columns:
                    continue

                rows, selected = fit_group(
                    group,
                    operation_name,
                    index_type,
                    metric_name,
                )

                all_fit_rows.extend(rows)
                selected_rows.append(selected)

    all_df = pd.DataFrame(all_fit_rows).sort_values(
        ["operation_name", "metric", "index_type", "priority_rank", "model_name"]
    )

    selected_df = pd.DataFrame(selected_rows).sort_values(
        ["operation_name", "metric", "index_type"]
    )

    all_df.to_csv(OUT_ALL_CSV, index=False)
    selected_df.to_csv(OUT_SELECTED_CSV, index=False)

    with OUT_TXT.open("w", encoding="utf-8") as f:
        f.write("Подбор ожидаемых зависимостей для отчета ЛР-4\n")
        f.write(f"Точки с rows_base < {MIN_ROWS_FOR_FIT} исключены из fit.\n")
        f.write("Проверяемые модели: constant, logarithmic, linear, exponential.\n")
        f.write("teacher_model выбирается по теоретическому приоритету для операции.\n")
        f.write("statistical_model выбирается по AICc среди этих моделей.\n\n")

        for _, row in selected_df.iterrows():
            f.write(
                f"[{row['operation_name']} | {row['index_type']} | {row['metric']}]\n"
                f"expected priority: {row['expected_priority']}\n"
                f"teacher model: {row['teacher_model_name']}\n"
                f"teacher formula: {row['teacher_formula']}\n"
                f"teacher R2: {row['teacher_r2']:.6f}, "
                f"RMSE: {row['teacher_rmse']:.6f}, "
                f"MAPE: {row['teacher_mape_percent']:.3f}%\n"
                f"statistical model: {row['statistical_model_name']}\n"
                f"statistical formula: {row['statistical_formula']}\n"
                f"statistical R2: {row['statistical_r2']:.6f}, "
                f"RMSE: {row['statistical_rmse']:.6f}, "
                f"MAPE: {row['statistical_mape_percent']:.3f}%\n"
                f"models match: {row['models_match']}\n\n"
            )

    # Графики по времени.
    for operation_name in ["select", "insert", "update"]:
        for metric_name in TIME_METRICS:
            if metric_name in agg.columns:
                save_teacher_plot(
                    agg,
                    all_df,
                    selected_df,
                    operation_name,
                    metric_name,
                    f"13_teacher_{operation_name}_{metric_name}.png",
                    logx=False,
                )
                save_teacher_plot(
                    agg,
                    all_df,
                    selected_df,
                    operation_name,
                    metric_name,
                    f"13_teacher_{operation_name}_{metric_name}_logx.png",
                    logx=True,
                )

    print("saved:")
    print(" ", OUT_ALL_CSV)
    print(" ", OUT_SELECTED_CSV)
    print(" ", OUT_TXT)
    print("  charts/13_teacher_*.png")

    print("\nВыбранные teacher-модели:")
    print(
        selected_df[
            [
                "operation_name",
                "index_type",
                "metric",
                "teacher_model_name",
                "teacher_formula",
                "teacher_r2",
                "teacher_mape_percent",
                "statistical_model_name",
                "models_match",
            ]
        ].to_string(index=False)
    )


if __name__ == "__main__":
    main()
