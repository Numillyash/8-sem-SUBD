#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report

export PGPASSWORD=lab4pass

PSQL=(
  psql
  -h 127.0.0.1
  -p 15435
  -U lab4user
  -d subd_lab4_clean
  -v ON_ERROR_STOP=1
  -q
  -P pager=off
)

"${PSQL[@]}" > report/12_dense_under_1m_raw.csv <<'SQL'
COPY (
    SELECT
        measurement_id,
        measured_at,
        operation_name,
        index_type,
        rows_base,
        batch_size,
        probes,
        run_no,
        total_elapsed_ms,
        elapsed_ms_per_operation,
        affected_rows,
        found_rows,
        trigger_rows
    FROM lab4.extended_all_sizes_measurements
    WHERE rows_base IN (
        10, 25, 50, 100, 250, 500,
        1000, 2500, 5000,
        10000, 25000, 50000,
        100000, 250000, 500000
    )
    ORDER BY operation_name, rows_base, index_type, run_no, measurement_id
) TO STDOUT WITH CSV HEADER;
SQL

"${PSQL[@]}" > report/12_dense_under_1m_aggregated.csv <<'SQL'
COPY (
    SELECT
        operation_name,
        index_type,
        rows_base,
        count(*) AS runs,
        min(batch_size) AS batch_size_min,
        max(batch_size) AS batch_size_max,
        min(probes) AS probes_min,
        max(probes) AS probes_max,
        round(avg(total_elapsed_ms), 6) AS avg_total_elapsed_ms,
        round(min(total_elapsed_ms), 6) AS min_total_elapsed_ms,
        round(max(total_elapsed_ms), 6) AS max_total_elapsed_ms,
        round(stddev_samp(total_elapsed_ms), 6) AS stddev_total_elapsed_ms,
        round(avg(elapsed_ms_per_operation), 9) AS avg_elapsed_ms_per_operation,
        min(affected_rows) AS affected_rows_min,
        max(affected_rows) AS affected_rows_max,
        min(found_rows) AS found_rows_min,
        max(found_rows) AS found_rows_max,
        min(trigger_rows) AS trigger_rows_min,
        max(trigger_rows) AS trigger_rows_max
    FROM lab4.extended_all_sizes_measurements
    WHERE rows_base IN (
        10, 25, 50, 100, 250, 500,
        1000, 2500, 5000,
        10000, 25000, 50000,
        100000, 250000, 500000
    )
    GROUP BY operation_name, index_type, rows_base
    ORDER BY operation_name, rows_base, index_type
) TO STDOUT WITH CSV HEADER;
SQL

"${PSQL[@]}" > report/12_dense_under_1m_sizes.csv <<'SQL'
COPY (
    SELECT
        operation_name,
        index_type,
        rows_base,
        table_name,
        relation_bytes,
        indexes_bytes,
        total_bytes,
        relation_size,
        indexes_size,
        total_size
    FROM lab4.extended_all_sizes_sizes
    WHERE rows_base IN (
        10, 25, 50, 100, 250, 500,
        1000, 2500, 5000,
        10000, 25000, 50000,
        100000, 250000, 500000
    )
    ORDER BY operation_name, rows_base, index_type, size_id
) TO STDOUT WITH CSV HEADER;
SQL

"${PSQL[@]}" > report/12_dense_under_1m_checks.csv <<'SQL'
COPY (
    WITH checks AS (
        SELECT
            'select_raw_rows_expected_180' AS check_name,
            count(*) AS actual_value,
            CASE WHEN count(*) = 180 THEN 'OK' ELSE 'FAIL' END AS check_result
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'select'

        UNION ALL

        SELECT
            'insert_raw_rows_expected_375',
            count(*),
            CASE WHEN count(*) = 375 THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'insert'

        UNION ALL

        SELECT
            'update_raw_rows_expected_375',
            count(*),
            CASE WHEN count(*) = 375 THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'update'

        UNION ALL

        SELECT
            'select_found_rows_equal_probes',
            count(*),
            CASE WHEN bool_and(found_rows = probes) THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'select'

        UNION ALL

        SELECT
            'insert_affected_rows_equal_batch',
            count(*),
            CASE WHEN bool_and(affected_rows = batch_size) THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'insert'

        UNION ALL

        SELECT
            'update_affected_and_trigger_rows_equal_batch',
            count(*),
            CASE WHEN bool_and(affected_rows = batch_size AND trigger_rows = batch_size) THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'update'

        UNION ALL

        SELECT
            'dense_table_sizes_expected_15_select',
            count(DISTINCT rows_base),
            CASE WHEN count(DISTINCT rows_base) = 15 THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'select'

        UNION ALL

        SELECT
            'dense_table_sizes_expected_15_insert',
            count(DISTINCT rows_base),
            CASE WHEN count(DISTINCT rows_base) = 15 THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'insert'

        UNION ALL

        SELECT
            'dense_table_sizes_expected_15_update',
            count(DISTINCT rows_base),
            CASE WHEN count(DISTINCT rows_base) = 15 THEN 'OK' ELSE 'FAIL' END
        FROM lab4.extended_all_sizes_measurements
        WHERE operation_name = 'update'
    )
    SELECT *
    FROM checks
    ORDER BY check_name
) TO STDOUT WITH CSV HEADER;
SQL

echo "exported:"
echo "  report/12_dense_under_1m_raw.csv"
echo "  report/12_dense_under_1m_aggregated.csv"
echo "  report/12_dense_under_1m_sizes.csv"
echo "  report/12_dense_under_1m_checks.csv"
