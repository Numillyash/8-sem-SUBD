#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -c "\
COPY (
    SELECT
        rows_base,
        count(*) AS runs,
        min(batch_size) AS batch_size_min,
        max(batch_size) AS batch_size_max,
        min(affected_rows) AS affected_rows_min,
        max(affected_rows) AS affected_rows_max,
        round(avg(elapsed_ms), 6) AS avg_total_elapsed_ms,
        round(min(elapsed_ms), 6) AS min_total_elapsed_ms,
        round(max(elapsed_ms), 6) AS max_total_elapsed_ms,
        round(stddev_samp(elapsed_ms), 6) AS stddev_total_elapsed_ms,
        round(avg(elapsed_ms / NULLIF(affected_rows, 0)), 9) AS avg_elapsed_ms_per_row
    FROM lab4.update_no_lookup_index_measurements
    GROUP BY rows_base
    ORDER BY rows_base
) TO STDOUT WITH CSV HEADER" > report/16_update_no_lookup_index_control.csv

echo 'exported: report/16_update_no_lookup_index_control.csv'
