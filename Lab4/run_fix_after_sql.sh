#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4

export PGPASSWORD=lab4pass
PSQL=(psql -h 127.0.0.1 -p 15434 -U lab4user -d subd_lab4 -v ON_ERROR_STOP=1 -P pager=off)

mkdir -p logs report charts

# 1. Пересобрать методические эксперименты, включая контроль affected_rows для UPDATE.
"${PSQL[@]}" -f sql/08_methodical_completion.sql | tee logs/08_methodical_completion.log

# 2. Отдельная проверка: каждый UPDATE должен затрагивать ровно одну строку.
"${PSQL[@]}" -f sql/09_update_correctness_control.sql | tee logs/09_update_correctness_control.log

# 3. Выгрузить CSV из БД.
bash scripts/export_results.sh | tee logs/06_export_results.log
bash scripts/09_export_methodical_results.sh | tee logs/09_export_methodical_results.log

# 4. Пересобрать все графики в линейных шкалах.
python3 scripts/make_charts.py
python3 scripts/make_methodical_charts.py
