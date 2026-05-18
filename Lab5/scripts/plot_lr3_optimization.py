from pathlib import Path
import csv
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[1]
report_dir = root / "report"
charts_dir = root / "charts"
charts_dir.mkdir(exist_ok=True)

summary_path = report_dir / "lr3_optimization_summary.csv"
comparison_path = report_dir / "lr3_optimization_comparison.csv"
detail_path = report_dir / "lr3_optimization_measurements_detail.csv"

summary = []
with summary_path.open("r", encoding="utf-8") as f:
    summary = list(csv.DictReader(f))

comparison = []
with comparison_path.open("r", encoding="utf-8") as f:
    comparison = list(csv.DictReader(f))

detail = []
with detail_path.open("r", encoding="utf-8") as f:
    detail = list(csv.DictReader(f))

# 1. Сравнение ключевых финальных сценариев
labels = [
    "Q1\nисходный",
    "Q1\nиндекс",
    "Q2\nEXTRACT",
    "Q2\nrewrite+index",
    "Q3\nNOT EXISTS",
    "Q3\nGROUP BY",
    "Q3\nGROUP BY+indexes",
]

stage_map = {
    ("Q1", "baseline_original"): "Q1\nисходный",
    ("Q1", "optimized_index"): "Q1\nиндекс",
    ("Q2", "baseline_extract"): "Q2\nEXTRACT",
    ("Q2", "logical_rewrite_plus_index"): "Q2\nrewrite+index",
    ("Q3", "baseline_double_not_exists"): "Q3\nNOT EXISTS",
    ("Q3", "logical_rewrite_group_by_having"): "Q3\nGROUP BY",
    ("Q3", "logical_rewrite_plus_indexes"): "Q3\nGROUP BY+indexes",
}

values = {stage_map[(r["query_name"], r["stage"])]: float(r["avg_execution_ms"])
          for r in summary
          if (r["query_name"], r["stage"]) in stage_map}

plt.figure(figsize=(11, 5))
plt.bar(labels, [values[l] for l in labels])
plt.ylabel("Среднее время выполнения, мс")
plt.xlabel("Сценарий")
plt.title("Среднее время выполнения запросов ЛР3 до и после оптимизации")
plt.tight_layout()
plt.savefig(charts_dir / "lr3_optimization_avg_execution_time.png", dpi=200)
plt.close()

# 2. Ускорение
comp_labels = []
speedups = []
for r in comparison:
    label = f"{r['query_name']}\n{r['to_stage']}"
    comp_labels.append(label)
    speedups.append(float(r["speedup_ratio"]))

plt.figure(figsize=(11, 5))
plt.bar(comp_labels, speedups)
plt.ylabel("Коэффициент ускорения")
plt.xlabel("Сравнение")
plt.title("Коэффициент ускорения после оптимизации запросов из ЛР3")
plt.xticks(rotation=15, ha="right")
plt.tight_layout()
plt.savefig(charts_dir / "lr3_optimization_speedup_ratio.png", dpi=200)
plt.close()

# 3. Процент улучшения
improvements = [float(r["improvement_percent"]) for r in comparison]

plt.figure(figsize=(11, 5))
plt.bar(comp_labels, improvements)
plt.ylabel("Снижение времени выполнения, %")
plt.xlabel("Сравнение")
plt.title("Процентное снижение времени выполнения")
plt.xticks(rotation=15, ha="right")
plt.tight_layout()
plt.savefig(charts_dir / "lr3_optimization_improvement_percent.png", dpi=200)
plt.close()

# 4. Стабильность прогонов по каждому запросу
groups = {
    "Q1": ["baseline_original", "optimized_index"],
    "Q2": ["baseline_extract", "logical_rewrite_ranges", "logical_rewrite_plus_index"],
    "Q3": ["baseline_double_not_exists", "logical_rewrite_group_by_having", "logical_rewrite_plus_indexes"],
}

stage_titles = {
    "baseline_original": "Исходный",
    "optimized_index": "Индекс",
    "baseline_extract": "EXTRACT",
    "logical_rewrite_ranges": "Диапазоны дат",
    "logical_rewrite_plus_index": "Диапазоны + индекс",
    "baseline_double_not_exists": "Двойной NOT EXISTS",
    "logical_rewrite_group_by_having": "GROUP BY/HAVING",
    "logical_rewrite_plus_indexes": "GROUP BY/HAVING + индексы",
}

for query_name, stages in groups.items():
    plt.figure(figsize=(10, 5))
    for stage in stages:
        rows = [
            r for r in detail
            if r["query_name"] == query_name and r["stage"] == stage
        ]
        rows.sort(key=lambda r: int(r["run_number"]))
        runs = [int(r["run_number"]) for r in rows]
        times = [float(r["execution_ms"]) for r in rows]
        plt.plot(runs, times, marker="o", label=stage_titles[stage])

    plt.xticks([1, 2, 3, 4, 5])
    plt.ylabel("Время выполнения, мс")
    plt.xlabel("Номер запуска")
    plt.title(f"Стабильность измерений {query_name}")
    plt.legend()
    plt.tight_layout()
    plt.savefig(charts_dir / f"lr3_optimization_{query_name.lower()}_runs.png", dpi=200)
    plt.close()

print("Графики сохранены:")
for path in sorted(charts_dir.glob("lr3_optimization_*.png")):
    print(path)
