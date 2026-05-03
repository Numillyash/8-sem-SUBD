#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -v ON_ERROR_STOP=1 -P pager=off)

"${PSQL[@]}" -c "\copy (
  SELECT
    index_type,
    rows_base,
    count(*) AS runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    round(avg(total_elapsed_ms), 3) AS avg_total_elapsed_ms,
    round(min(total_elapsed_ms), 3) AS min_total_elapsed_ms,
    round(max(total_elapsed_ms), 3) AS max_total_elapsed_ms,
    round(stddev_samp(total_elapsed_ms), 3) AS stddev_total_elapsed_ms,
    round(avg(avg_elapsed_ms_per_row), 6) AS avg_elapsed_ms_per_row
  FROM lab4.update_measurements
  GROUP BY index_type, rows_base
  ORDER BY rows_base, index_type
) TO 'report/05_update_indexes_measurements.csv' WITH (FORMAT csv, HEADER true)"

"${PSQL[@]}" -c "\copy (
  SELECT
    index_type,
    count(DISTINCT rows_base) AS tested_table_sizes,
    count(*) AS total_runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    CASE
      WHEN min(affected_rows) = min(batch_size)
       AND max(affected_rows) = max(batch_size)
       AND min(trigger_rows) = min(batch_size)
       AND max(trigger_rows) = max(batch_size)
      THEN 'OK: every UPDATE changed expected rows and trigger fired for every row'
      ELSE 'FAIL'
    END AS check_result
  FROM lab4.update_measurements
  GROUP BY index_type
  ORDER BY index_type
) TO 'report/05_update_trigger_control.csv' WITH (FORMAT csv, HEADER true)"

"${PSQL[@]}" -c "\copy (
  SELECT
    c.relname AS table_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_indexes_size(c.oid) AS indexes_bytes,
    pg_total_relation_size(c.oid) AS total_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'lab4'
    AND c.relname IN (
      'update_no_extra_index',
      'update_simple_btree',
      'update_unique_btree',
      'update_expression_index',
      'update_function_index'
    )
  ORDER BY c.relname
) TO 'report/05_update_indexes_sizes.csv' WITH (FORMAT csv, HEADER true)"

echo "exported:"
echo "  report/05_update_indexes_measurements.csv"
echo "  report/05_update_trigger_control.csv"
echo "  report/05_update_indexes_sizes.csv"
