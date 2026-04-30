#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15434 -U lab4user -d subd_lab4 -v ON_ERROR_STOP=1 -P pager=off)

echo "=== Export method_page_growth_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT rows_in_table, relation_bytes, relation_pages, total_relation_bytes, avg_relation_bytes_per_row FROM lab4.method_page_growth_measurements ORDER BY rows_in_table) TO 'report/method_page_growth_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export method_partition_strict_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT test_name, table_name, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.method_partition_strict_measurements GROUP BY test_name, table_name ORDER BY test_name, table_name) TO 'report/method_partition_strict_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export method_series_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT operation_name, index_type, rows_before, count(*) AS runs, min(affected_rows) AS affected_rows_min, max(affected_rows) AS affected_rows_max, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.method_series_measurements GROUP BY operation_name, index_type, rows_before ORDER BY operation_name, rows_before, index_type) TO 'report/method_series_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export method_final_table_sizes.csv ==="
"${PSQL[@]}" -c "\copy (SELECT relname AS table_name, pg_relation_size(('lab4.' || relname)::regclass) AS relation_bytes, pg_indexes_size(('lab4.' || relname)::regclass) AS indexes_bytes, pg_total_relation_size(('lab4.' || relname)::regclass) AS total_bytes FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'lab4' AND relname IN ('method_select_no_index', 'method_select_id_index', 'method_mod_no_index', 'method_mod_simple_index', 'method_mod_unique_index', 'method_mod_expr_index', 'method_mod_func_index', 'method_page_growth_test') ORDER BY relname) TO 'report/method_final_table_sizes.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Methodical export done ==="
