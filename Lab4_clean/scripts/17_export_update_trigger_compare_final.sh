#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-/mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean}"
cd "$BASE"

mkdir -p report

export PGPASSWORD="${PGPASSWORD:-lab4pass}"

PSQL=(
  psql
  -X
  -q
  -h 127.0.0.1
  -p 15435
  -U lab4user
  -d subd_lab4_clean
  -P pager=off
  -v ON_ERROR_STOP=1
)

"${PSQL[@]}" -c "
COPY (
    SELECT
        index_type,
        trigger_mode,
        rows_base,
        run_no,
        chunk_count,
        chunk_size,
        affected_rows,
        trigger_rows,
        total_elapsed_ms,
        avg_elapsed_ms_per_row,
        measured_at
    FROM lab4.update_trigger_compare_measurements
    ORDER BY
        rows_base,
        index_type,
        trigger_mode,
        run_no
) TO STDOUT WITH CSV HEADER
" > report/21_update_trigger_compare_raw.csv

"${PSQL[@]}" -c "
COPY (
    SELECT
        index_type,
        trigger_mode,
        rows_base,
        count(*) AS runs,
        min(chunk_count) AS chunk_count_min,
        max(chunk_count) AS chunk_count_max,
        min(chunk_size) AS chunk_size_min,
        max(chunk_size) AS chunk_size_max,
        min(affected_rows) AS affected_min,
        max(affected_rows) AS affected_max,
        min(trigger_rows) AS trigger_rows_min,
        max(trigger_rows) AS trigger_rows_max,
        avg(total_elapsed_ms) AS avg_total_elapsed_ms,
        min(total_elapsed_ms) AS min_total_elapsed_ms,
        max(total_elapsed_ms) AS max_total_elapsed_ms,
        stddev_samp(total_elapsed_ms) AS stddev_total_elapsed_ms,
        avg(avg_elapsed_ms_per_row) AS avg_elapsed_ms_per_row
    FROM lab4.update_trigger_compare_measurements
    GROUP BY
        index_type,
        trigger_mode,
        rows_base
    ORDER BY
        rows_base,
        index_type,
        trigger_mode
) TO STDOUT WITH CSV HEADER
" > report/21_update_trigger_compare_aggregated.csv

"${PSQL[@]}" -c "
COPY (
    SELECT
        index_type,
        trigger_mode,
        rows_base,
        min(affected_rows) AS affected_min,
        max(affected_rows) AS affected_max,
        min(trigger_rows) AS trigger_rows_min,
        max(trigger_rows) AS trigger_rows_max,
        CASE
            WHEN min(affected_rows) <> 1000 OR max(affected_rows) <> 1000
                THEN 'FAIL: affected_rows must be 1000'
            WHEN trigger_mode = 'with_trigger'
                 AND (min(trigger_rows) <> 1000 OR max(trigger_rows) <> 1000)
                THEN 'FAIL: trigger_rows must be 1000'
            WHEN trigger_mode = 'without_trigger'
                 AND (min(trigger_rows) <> 0 OR max(trigger_rows) <> 0)
                THEN 'FAIL: trigger_rows must be 0'
            ELSE 'OK'
        END AS check_result
    FROM lab4.update_trigger_compare_measurements
    GROUP BY
        index_type,
        trigger_mode,
        rows_base
    ORDER BY
        rows_base,
        index_type,
        trigger_mode
) TO STDOUT WITH CSV HEADER
" > report/21_update_trigger_compare_checks.csv

echo "saved:"
echo "  report/21_update_trigger_compare_raw.csv"
echo "  report/21_update_trigger_compare_aggregated.csv"
echo "  report/21_update_trigger_compare_checks.csv"
