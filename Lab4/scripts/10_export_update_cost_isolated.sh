#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15434 -U lab4user -d subd_lab4 -v ON_ERROR_STOP=1 -P pager=off)

echo "=== Export update_cost_isolated_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT index_type, rows_before, batch_size, count(*) AS runs, min(affected_rows) AS affected_rows_min, max(affected_rows) AS affected_rows_max, min(trigger_rows) AS trigger_rows_min, max(trigger_rows) AS trigger_rows_max, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.update_cost_measurements GROUP BY index_type, rows_before, batch_size ORDER BY rows_before, index_type) TO 'report/update_cost_isolated_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export update_cost_trigger_control.csv ==="
"${PSQL[@]}" -c "\copy (SELECT index_type, count(DISTINCT rows_before) AS tested_table_sizes, count(*) AS total_runs, min(affected_rows) AS affected_rows_min, max(affected_rows) AS affected_rows_max, min(trigger_rows) AS trigger_rows_min, max(trigger_rows) AS trigger_rows_max, CASE WHEN min(affected_rows) = 1000 AND max(affected_rows) = 1000 AND min(trigger_rows) = 1000 AND max(trigger_rows) = 1000 THEN 'OK: every UPDATE affected 1000 rows and trigger fired 1000 times' ELSE 'CHECK FAILED' END AS check_result FROM lab4.update_cost_measurements GROUP BY index_type ORDER BY index_type) TO 'report/update_cost_trigger_control.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export done ==="
