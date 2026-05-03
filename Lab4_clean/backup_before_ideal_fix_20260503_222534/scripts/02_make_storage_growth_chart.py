from pathlib import Path
import pandas as pd
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

BASE = Path("/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean")
REPORT = BASE / "report"
CHARTS = BASE / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)


def fmt_int(x, _):
    return f"{int(x):,}".replace(",", " ")


def fmt_float(x, _):
    if abs(x) >= 1000:
        return f"{int(x):,}".replace(",", " ")
    return f"{x:g}"


df = pd.read_csv(REPORT / "01_storage_growth.csv")

fig, ax = plt.subplots(figsize=(11, 6))
ax.plot(
    df["rows_actual"].to_numpy(),
    df["relation_bytes"].to_numpy(),
    marker="o",
)

ax.set_title("Рост размера relation при увеличении числа записей")
ax.set_xlabel("Количество строк")
ax.set_ylabel("Размер relation, байт")
ax.xaxis.set_major_formatter(FuncFormatter(fmt_int))
ax.yaxis.set_major_formatter(FuncFormatter(fmt_float))
fig.tight_layout()
fig.savefig(CHARTS / "01_storage_growth_relation.png", dpi=200)
plt.close(fig)

print("saved:", CHARTS / "01_storage_growth_relation.png")
