#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -v ON_ERROR_STOP=1 -P pager=off)

"${PSQL[@]}" -c "\copy (
  SELECT
    test_name,
    table_name,
    sql_text,
    count(*) AS runs,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms,
    min(result_value) AS result_check_min,
    max(result_value) AS result_check_max
  FROM lab4.partition_measurements
  GROUP BY test_name, table_name, sql_text
  ORDER BY test_name, table_name
) TO 'report/02_partitioning_measurements.csv' WITH (FORMAT csv, HEADER true)"

"${PSQL[@]}" -c "\copy (
  SELECT
    c.relname AS object_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_total_relation_size(c.oid) AS total_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'lab4'
    AND c.relname IN (
      'orders_plain',
      'orders_partitioned',
      'orders_partitioned_2024_q1',
      'orders_partitioned_2024_q2',
      'orders_partitioned_2024_q3',
      'orders_partitioned_2024_q4'
    )
  ORDER BY c.relname
) TO 'report/02_partitioning_sizes.csv' WITH (FORMAT csv, HEADER true)"

echo "exported:"
echo "  report/02_partitioning_measurements.csv"
echo "  report/02_partitioning_sizes.csv"
