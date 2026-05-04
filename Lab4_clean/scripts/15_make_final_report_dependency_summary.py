from pathlib import Path
import pandas as pd

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")
REPORT = BASE / "report"

SRC = REPORT / "13_teacher_expected_fits_selected.csv"
ALL = REPORT / "13_teacher_expected_fits_all_models.csv"

OUT_CSV = REPORT / "15_final_report_dependency_summary.csv"
OUT_TXT = REPORT / "15_final_report_dependency_summary.txt"

selected = pd.read_csv(SRC)
all_models = pd.read_csv(ALL)

rows = []


def find_formula(row, model_name):
    part = all_models[
        (all_models["operation_name"] == row["operation_name"])
        & (all_models["index_type"] == row["index_type"])
        & (all_models["metric"] == row["metric"])
        & (all_models["model_name"] == model_name)
    ]

    if part.empty:
        return {
            "formula": row["teacher_formula"],
            "r2": row["teacher_r2"],
            "mape": row["teacher_mape_percent"],
            "aicc": row["teacher_aicc"],
        }

    p = part.iloc[0]
    return {
        "formula": p["formula"],
        "r2": p["r2"],
        "mape": p["mape_percent"],
        "aicc": p["aicc"],
    }


for _, row in selected.iterrows():
    op = str(row["operation_name"])
    idx = str(row["index_type"])
    metric = str(row["metric"])

    use = "YES"
    report_model = str(row["teacher_model_name"])
    comment = ""

    if op.startswith("size_"):
        if metric == "indexes_bytes" and (idx == "no_index" or "without_index" in idx):
            report_model = "constant"
            comment = "Размер индексов равен нулю, так как индекс отсутствует."
        else:
            report_model = "linear"
            comment = "Размер таблиц и индексных структур растет практически линейно от количества строк."

    elif op == "select":
        if "without_index" in idx:
            report_model = "linear"
            comment = "SELECT без индекса выполняется последовательным просмотром таблицы; основная интерпретация — линейный рост."
        elif "btree" in idx:
            report_model = "logarithmic"
            comment = "SELECT с B-tree индексом теоретически близок к логарифмическому доступу; на данном диапазоне выглядит почти постоянным из-за малых абсолютных времен."
        else:
            comment = "SELECT интерпретируется по ожидаемой модели доступа."

    elif op == "insert":
        if metric == "avg_elapsed_ms_per_operation":
            use = "NO"
            report_model = "not_used"
            comment = "Метрика одной вставляемой строки слишком шумная для основной формулы."
        elif idx == "no_index":
            report_model = "constant"
            comment = "INSERT без индекса имеет слабую зависимость от размера таблицы; основную роль играют постоянные накладные расходы."
        else:
            report_model = "logarithmic"
            comment = "INSERT с индексами требует обслуживания индексных структур; для B-tree допустима логарифмическая интерпретация."

    elif op == "update":
        if metric == "avg_elapsed_ms_per_operation":
            use = "NO"
            report_model = "not_used"
            comment = "Метрика одной обновляемой строки слишком шумная; для отчета используется суммарное время пакета."
        elif idx == "no_extra_index":
            report_model = "constant"
            comment = "UPDATE без дополнительного исследуемого индекса показывает в основном постоянные накладные расходы на пакет."
        else:
            report_model = "logarithmic"
            comment = "UPDATE с дополнительными индексами включает стоимость поиска, записи новой версии строки и обслуживания индексов."

    if report_model in {"constant", "logarithmic", "linear", "exponential"}:
        f = find_formula(row, report_model)
        report_formula = f["formula"]
        report_r2 = f["r2"]
        report_mape = f["mape"]
        report_aicc = f["aicc"]
    else:
        report_formula = ""
        report_r2 = float("nan")
        report_mape = float("nan")
        report_aicc = float("nan")

    out = row.to_dict()
    out["use_in_report"] = use
    out["report_model"] = report_model
    out["report_formula"] = report_formula
    out["report_r2"] = report_r2
    out["report_mape_percent"] = report_mape
    out["report_aicc"] = report_aicc
    out["report_comment"] = comment
    rows.append(out)

out = pd.DataFrame(rows)
out.to_csv(OUT_CSV, index=False)

with OUT_TXT.open("w", encoding="utf-8") as f:
    f.write("Финальные рекомендуемые зависимости для отчета ЛР-4\n")
    f.write("Модели ограничены методически ожидаемыми вариантами: constant, logarithmic, linear, exponential.\n")
    f.write("Точки 10 и 25 строк исключены из регрессионного подбора; на графиках они оставлены как фактические измерения.\n\n")

    for _, r in out.iterrows():
        if r["use_in_report"] != "YES":
            continue

        f.write(f"[{r['operation_name']} | {r['index_type']} | {r['metric']}]\n")
        f.write(f"Модель для отчета: {r['report_model']}\n")
        f.write(f"Формула для отчета: {r['report_formula']}\n")
        f.write(f"R2: {r['report_r2']:.6f}; MAPE: {r['report_mape_percent']:.3f}%\n")
        f.write(f"Комментарий: {r['report_comment']}\n\n")

print("saved:")
print(" ", OUT_CSV)
print(" ", OUT_TXT)

print("\nПроверка финальных моделей для отчета:")
show = out[out["use_in_report"] == "YES"][
    [
        "operation_name",
        "index_type",
        "metric",
        "report_model",
        "report_r2",
        "report_mape_percent",
        "statistical_model_name",
    ]
]
print(show.to_string(index=False))
