#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15434 -U lab4user -d subd_lab4 -v ON_ERROR_STOP=1 -P pager=off)

echo "=== Export storage_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT rows_in_table, database_bytes, relation_bytes, total_relation_bytes, indexes_bytes, toast_bytes, avg_relation_bytes_per_row, avg_total_bytes_per_row FROM lab4.storage_measurements ORDER BY rows_in_table) TO 'report/storage_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export partition_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT test_name, table_name, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.partition_measurements GROUP BY test_name, table_name ORDER BY test_name, table_name) TO 'report/partition_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export index_select_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT test_name, index_state, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.index_select_measurements GROUP BY test_name, index_state ORDER BY index_state) TO 'report/index_select_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export insert_update_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT operation_name, index_type, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.insert_update_measurements GROUP BY operation_name, index_type ORDER BY operation_name, index_type) TO 'report/insert_update_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export clean_update_measurements.csv ==="
"${PSQL[@]}" -c "\copy (SELECT test_name, index_type, round(avg(elapsed_ms), 3) AS avg_elapsed_ms, round(min(elapsed_ms), 3) AS min_elapsed_ms, round(max(elapsed_ms), 3) AS max_elapsed_ms, round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms FROM lab4.clean_update_measurements GROUP BY test_name, index_type ORDER BY test_name, index_type) TO 'report/clean_update_measurements.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export table_sizes.csv ==="
"${PSQL[@]}" -c "\copy (SELECT relname AS table_name, pg_relation_size(('lab4.' || relname)::regclass) AS relation_bytes, pg_indexes_size(('lab4.' || relname)::regclass) AS indexes_bytes, pg_total_relation_size(('lab4.' || relname)::regclass) AS total_bytes FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'lab4' AND relname IN ('mod_no_index', 'mod_simple_index', 'mod_unique_index', 'mod_expr_index', 'mod_func_index', 'clean_no_index', 'clean_customer_index', 'clean_code_index', 'clean_payload_func_index') ORDER BY relname) TO 'report/table_sizes.csv' WITH (FORMAT csv, HEADER true)"

echo "=== Export done ==="
