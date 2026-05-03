#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -At)

echo "=== Row counts after final UPDATE series ==="
"${PSQL[@]}" -c "
SELECT 'update_no_extra_index=' || count(*) FROM lab4.update_no_extra_index
UNION ALL
SELECT 'update_simple_btree=' || count(*) FROM lab4.update_simple_btree
UNION ALL
SELECT 'update_unique_btree=' || count(*) FROM lab4.update_unique_btree
UNION ALL
SELECT 'update_expression_index=' || count(*) FROM lab4.update_expression_index
UNION ALL
SELECT 'update_function_index=' || count(*) FROM lab4.update_function_index;
"

echo "=== Measurement groups ==="
"${PSQL[@]}" -c "
SELECT index_type || ' | rows_base=' || rows_base || ' | runs=' || count(*) ||
       ' | batch=' || min(batch_size) || '..' || max(batch_size) ||
       ' | affected=' || min(affected_rows) || '..' || max(affected_rows) ||
       ' | trigger=' || min(trigger_rows) || '..' || max(trigger_rows) ||
       ' | avg_total_ms=' || round(avg(total_elapsed_ms), 3) ||
       ' | avg_per_row_ms=' || round(avg(avg_elapsed_ms_per_row), 6)
FROM lab4.update_measurements
GROUP BY index_type, rows_base
ORDER BY rows_base, index_type;
"

echo "=== Correctness check ==="
"${PSQL[@]}" -c "
SELECT index_type || ' | sizes=' || count(DISTINCT rows_base) ||
       ' | total_runs=' || count(*) ||
       ' | batch=' || min(batch_size) || '..' || max(batch_size) ||
       ' | affected=' || min(affected_rows) || '..' || max(affected_rows) ||
       ' | trigger=' || min(trigger_rows) || '..' || max(trigger_rows) ||
       ' | ' ||
       CASE
         WHEN min(affected_rows) = min(batch_size)
          AND max(affected_rows) = max(batch_size)
          AND min(trigger_rows) = min(batch_size)
          AND max(trigger_rows) = max(batch_size)
         THEN 'OK'
         ELSE 'FAIL'
       END
FROM lab4.update_measurements
GROUP BY index_type
ORDER BY index_type;
"

echo "=== Expected files ==="
ls -lah \
  logs/05_update_indexes.log \
  logs/06_export_update_indexes.log \
  report/05_update_indexes_measurements.csv \
  report/05_update_trigger_control.csv \
  report/05_update_indexes_sizes.csv \
  charts/05_update_indexes.png \
  charts/05_update_indexes_per_row.png
