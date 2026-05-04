from pathlib import Path
import pandas as pd

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")
REPORT = BASE / "report"

IN = REPORT / "13_teacher_expected_fits_selected.csv"
OUT_CSV = REPORT / "14_report_dependency_summary.csv"
OUT_TXT = REPORT / "14_report_dependency_summary.txt"

df = pd.read_csv(IN)

rows = []

def add(row, recommendation, use_in_report, comment):
    r = row.to_dict()
    r["recommended_model"] = recommendation
    r["use_in_report"] = use_in_report
    r["report_comment"] = comment
    rows.append(r)

for _, row in df.iterrows():
    op = str(row["operation_name"])
    idx = str(row["index_type"])
    metric = str(row["metric"])

    # Размеры: почти всегда используем линейную интерпретацию.
    if op.startswith("size_"):
        if metric == "indexes_bytes" and (
            idx in {"no_index"} or "without_index" in idx
        ):
            add(
                row,
                "constant",
                "YES",
                "Размер индексов равен нулю, так как индекс отсутствует.",
            )
        else:
            add(
                row,
                "linear",
                "YES",
                "Размер отношения/индексов растет практически линейно от числа строк.",
            )
        continue

    # SELECT.
    if op == "select":
        if "without_index" in idx:
            add(
                row,
                "linear",
                "YES",
                "SELECT без индекса физически соответствует последовательному просмотру таблицы; основная интерпретация — линейный рост.",
            )
        elif "btree" in idx:
            add(
                row,
                "logarithmic / near-constant",
                "YES",
                "SELECT с B-tree индексом теоретически близок к логарифмическому доступу, но на данном диапазоне выглядит почти постоянным из-за малых абсолютных времен.",
            )
        else:
            add(
                row,
                row["teacher_model_name"],
                "YES",
                "SELECT интерпретируется по ожидаемой модели доступа.",
            )
        continue

    # INSERT.
    if op == "insert":
        if metric == "avg_elapsed_ms_per_operation":
            add(
                row,
                "not used",
                "NO",
                "Метрика одной строки слишком шумная для формулы: постоянные накладные расходы сравнимы с измеряемым временем.",
            )
        elif idx == "no_index":
            add(
                row,
                "constant / weak logarithmic",
                "YES",
                "Вставка без индекса близка к постоянной стоимости на строку; суммарное время серии меняется слабо и шумно.",
            )
        else:
            add(
                row,
                "logarithmic or linear",
                "YES",
                "При INSERT с индексами добавляется стоимость поддержки индексных структур; допустима логарифмическая/линейная эмпирическая интерпретация.",
            )
        continue

    # UPDATE.
    if op == "update":
        if metric == "avg_elapsed_ms_per_operation":
            add(
                row,
                "near-constant / not used",
                "NO",
                "Среднее время одной обновляемой строки на малых временах шумное; лучше использовать суммарное время пакета.",
            )
        elif idx == "no_extra_index":
            add(
                row,
                "constant / weak logarithmic",
                "YES",
                "UPDATE с техническим lookup-индексом и без дополнительного исследуемого индекса показывает в основном постоянные накладные расходы на пакет.",
            )
        else:
            add(
                row,
                "logarithmic or linear",
                "YES",
                "UPDATE с дополнительными индексами включает стоимость поиска, записи новой версии строки и обслуживания индексов.",
            )
        continue

    add(row, row["teacher_model_name"], "NO", "Не классифицировано автоматически.")

out = pd.DataFrame(rows)
out.to_csv(OUT_CSV, index=False)

with OUT_TXT.open("w", encoding="utf-8") as f:
    f.write("Рекомендуемые зависимости для вставки в отчет ЛР-4\n")
    f.write("Основано на report/13_teacher_expected_fits_selected.csv\n\n")

    for _, row in out.iterrows():
        if row["use_in_report"] != "YES":
            continue

        f.write(f"[{row['operation_name']} | {row['index_type']} | {row['metric']}]\n")
        f.write(f"Рекомендуемая интерпретация: {row['recommended_model']}\n")
        f.write(f"Teacher formula: {row['teacher_formula']}\n")
        f.write(f"Teacher R2: {row['teacher_r2']:.6f}; MAPE: {row['teacher_mape_percent']:.3f}%\n")
        f.write(f"Statistical model: {row['statistical_model_name']}\n")
        f.write(f"Комментарий: {row['report_comment']}\n\n")

print("saved:")
print(" ", OUT_CSV)
print(" ", OUT_TXT)

print("\nКратко по формулам, которые можно использовать в отчете:")
show = out[out["use_in_report"] == "YES"][
    [
        "operation_name",
        "index_type",
        "metric",
        "recommended_model",
        "teacher_model_name",
        "teacher_r2",
        "statistical_model_name",
    ]
]
print(show.to_string(index=False))
