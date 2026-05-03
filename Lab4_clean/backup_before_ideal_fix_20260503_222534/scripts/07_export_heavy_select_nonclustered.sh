#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -v ON_ERROR_STOP=1 -P pager=off)

"${PSQL[@]}" -c "\copy (
  SELECT
    index_state,
    rows_before,
    count(*) AS runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    min(found_rows) AS found_rows_min,
    max(found_rows) AS found_rows_max,
    round(avg(total_elapsed_ms), 3) AS avg_total_elapsed_ms,
    round(avg(total_elapsed_seconds), 3) AS avg_total_elapsed_seconds,
    round(min(total_elapsed_seconds), 3) AS min_total_elapsed_seconds,
    round(max(total_elapsed_seconds), 3) AS max_total_elapsed_seconds,
    round(stddev_samp(total_elapsed_seconds), 3) AS stddev_total_elapsed_seconds,
    round(avg(avg_elapsed_ms), 6) AS avg_elapsed_ms_per_select
  FROM lab4.heavy_select_measurements
  GROUP BY index_state, rows_before
  ORDER BY rows_before, index_state
) TO 'report/08_heavy_select_nonclustered_measurements.csv' WITH (FORMAT csv, HEADER true)"

"${PSQL[@]}" -c "\copy (
  SELECT
    c.relname AS table_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_indexes_size(c.oid) AS indexes_bytes,
    pg_total_relation_size(c.oid) AS total_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'lab4'
    AND c.relname IN ('heavy_select_no_index', 'heavy_select_btree')
  ORDER BY c.relname
) TO 'report/08_heavy_select_nonclustered_sizes.csv' WITH (FORMAT csv, HEADER true)"

echo "exported:"
echo "  report/08_heavy_select_nonclustered_measurements.csv"
echo "  report/08_heavy_select_nonclustered_sizes.csv"
