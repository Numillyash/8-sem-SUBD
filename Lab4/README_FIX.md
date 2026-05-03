# Исправления для ЛР-4

Скопировать каталоги `scripts/` и `sql/` в рабочую папку:

`C:\Users\Georgul\Documents\8_sem\SUBD\Lab4`

Из WSL выполнить:

```bash
cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4
chmod +x run_fix_after_sql.sh scripts/export_results.sh scripts/09_export_methodical_results.sh
./run_fix_after_sql.sh
```

Что исправлено:

1. В `scripts/make_charts.py` и `scripts/make_methodical_charts.py` убрана логарифмическая шкала X. Все графики строятся в линной шкале.
2. В `sql/08_methodical_completion.sql` в таблицу `lab4.method_series_measurements` добавлено поле `affected_rows`, а в серии UPDATE добавлен `GET DIAGNOSTICS v_affected = ROW_COUNT`.
3. В `sql/09_update_correctness_control.sql` добавлена проверка, что каждый UPDATE для графика обновления затронул ровно одну строку.
4. В `scripts/09_export_methodical_results.sh` в CSV `method_series_measurements.csv` выгружаются `affected_rows_min` и `affected_rows_max`, чтобы было видно, что UPDATE реально срабатывал.
