#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -c "\
COPY (
    SELECT
        index_type,
        rows_base,
        count(*) AS runs,
        min(chunk_count) AS chunk_count_min,
        max(chunk_count) AS chunk_count_max,
        min(chunk_size) AS chunk_size_min,
        max(chunk_size) AS chunk_size_max,
        min(total_affected_rows) AS affected_min,
        max(total_affected_rows) AS affected_max,
        round(avg(elapsed_ms), 6) AS avg_total_elapsed_ms,
        round(min(elapsed_ms), 6) AS min_total_elapsed_ms,
        round(max(elapsed_ms), 6) AS max_total_elapsed_ms,
        round(stddev_samp(elapsed_ms), 6) AS stddev_total_elapsed_ms,
        round(avg(elapsed_ms / NULLIF(total_affected_rows, 0)), 9) AS avg_elapsed_ms_per_row
    FROM lab4.update_microbatch10_measurements
    GROUP BY index_type, rows_base
    ORDER BY rows_base, index_type
) TO STDOUT WITH CSV HEADER" > report/17_update_microbatch10_control.csv

psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -c "\
COPY (
    SELECT
        index_type,
        rows_base,
        min(total_affected_rows) AS affected_min,
        max(total_affected_rows) AS affected_max,
        CASE
            WHEN min(total_affected_rows) = 1000
             AND max(total_affected_rows) = 1000
            THEN 'OK'
            ELSE 'FAIL'
        END AS check_result
    FROM lab4.update_microbatch10_measurements
    GROUP BY index_type, rows_base
    ORDER BY rows_base, index_type
) TO STDOUT WITH CSV HEADER" > report/17_update_microbatch10_checks.csv

echo 'exported:'
echo '  report/17_update_microbatch10_control.csv'
echo '  report/17_update_microbatch10_checks.csv'
