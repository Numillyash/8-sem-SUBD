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
    min(inserted_rows) AS inserted_rows_min,
    max(inserted_rows) AS inserted_rows_max,
    round(avg(total_elapsed_ms), 3) AS avg_total_elapsed_ms,
    round(min(total_elapsed_ms), 3) AS min_total_elapsed_ms,
    round(max(total_elapsed_ms), 3) AS max_total_elapsed_ms,
    round(stddev_samp(total_elapsed_ms), 3) AS stddev_total_elapsed_ms,
    round(avg(avg_elapsed_ms_per_row), 6) AS avg_elapsed_ms_per_row
  FROM lab4.insert_measurements
  GROUP BY index_type, rows_base
  ORDER BY rows_base, index_type
) TO 'report/04_insert_indexes_measurements.csv' WITH (FORMAT csv, HEADER true)"

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
      'insert_no_index',
      'insert_simple_btree',
      'insert_unique_btree',
      'insert_expression_index',
      'insert_function_index'
    )
  ORDER BY c.relname
) TO 'report/04_insert_indexes_sizes.csv' WITH (FORMAT csv, HEADER true)"

echo "exported:"
echo "  report/04_insert_indexes_measurements.csv"
echo "  report/04_insert_indexes_sizes.csv"
