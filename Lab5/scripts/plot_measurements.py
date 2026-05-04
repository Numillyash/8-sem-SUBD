from pathlib import Path
import csv
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[1]
report_dir = root / "report"
charts_dir = root / "charts"
charts_dir.mkdir(exist_ok=True)

summary_path = report_dir / "lab5_measurements_summary.csv"
detail_path = report_dir / "lab5_measurements_detail.csv"

summary = []
with summary_path.open("r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        summary.append(row)

queries = [row["query_name"] for row in summary]
baseline = [float(row["baseline_avg_ms"]) for row in summary]
optimized = [float(row["optimized_avg_ms"]) for row in summary]
speedup = [float(row["speedup_ratio"]) for row in summary]
improvement = [float(row["improvement_percent"]) for row in summary]

x = range(len(queries))
width = 0.35

plt.figure(figsize=(9, 5))
plt.bar([i - width / 2 for i in x], baseline, width, label="До оптимизации")
plt.bar([i + width / 2 for i in x], optimized, width, label="После оптимизации")
plt.xticks(list(x), queries)
plt.ylabel("Среднее время выполнения, мс")
plt.xlabel("Запрос")
plt.title("Сравнение среднего времени выполнения запросов")
plt.legend()
plt.tight_layout()
plt.savefig(charts_dir / "lab5_avg_execution_time.png", dpi=200)
plt.close()

plt.figure(figsize=(9, 5))
plt.bar(queries, speedup)
plt.ylabel("Коэффициент ускорения")
plt.xlabel("Запрос")
plt.title("Ускорение запросов после добавления индексов")
plt.tight_layout()
plt.savefig(charts_dir / "lab5_speedup_ratio.png", dpi=200)
plt.close()

plt.figure(figsize=(9, 5))
plt.bar(queries, improvement)
plt.ylabel("Улучшение, %")
plt.xlabel("Запрос")
plt.title("Процентное снижение времени выполнения")
plt.tight_layout()
plt.savefig(charts_dir / "lab5_improvement_percent.png", dpi=200)
plt.close()

detail = []
with detail_path.open("r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        detail.append(row)

for query in queries:
    rows = [row for row in detail if row["query_name"] == query]
    baseline_rows = sorted(
        [row for row in rows if row["stage"] == "baseline"],
        key=lambda r: int(r["run_number"]),
    )
    optimized_rows = sorted(
        [row for row in rows if row["stage"] == "optimized"],
        key=lambda r: int(r["run_number"]),
    )

    runs = [int(row["run_number"]) for row in baseline_rows]
    baseline_times = [float(row["execution_ms"]) for row in baseline_rows]
    optimized_times = [float(row["execution_ms"]) for row in optimized_rows]

    plt.figure(figsize=(9, 5))
    plt.plot(runs, baseline_times, marker="o", label="До оптимизации")
    plt.plot(runs, optimized_times, marker="o", label="После оптимизации")
    plt.xticks(runs)
    plt.ylabel("Время выполнения, мс")
    plt.xlabel("Номер запуска")
    plt.title(f"Стабильность времени выполнения {query}")
    plt.legend()
    plt.tight_layout()
    plt.savefig(charts_dir / f"lab5_{query.lower()}_runs.png", dpi=200)
    plt.close()

print("Графики сохранены в:", charts_dir)
for path in sorted(charts_dir.glob("lab5_*.png")):
    print(path)
