#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean

export PGPASSWORD=lab4pass

PSQL=(
  psql
  -h 127.0.0.1
  -p 15435
  -U lab4user
  -d subd_lab4_clean
  -v ON_ERROR_STOP=1
  -P pager=off
)

echo "=== EXTENDED AUDIT: raw measurement counts ==="
"${PSQL[@]}" -c "
SELECT
    operation_name,
    count(*) AS raw_rows,
    count(DISTINCT rows_base) AS tested_table_sizes,
    min(rows_base) AS min_rows,
    max(rows_base) AS max_rows
FROM lab4.extended_all_sizes_measurements
GROUP BY operation_name
ORDER BY operation_name;
"

echo
echo "=== EXTENDED AUDIT: expected counts ==="
"${PSQL[@]}" -c "
WITH checks AS (
    SELECT
        'select_raw_rows_expected_96' AS check_name,
        count(*) AS actual_value,
        CASE WHEN count(*) = 96 THEN 'OK' ELSE 'FAIL' END AS check_result
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'select'

    UNION ALL

    SELECT
        'insert_raw_rows_expected_200',
        count(*),
        CASE WHEN count(*) = 200 THEN 'OK' ELSE 'FAIL' END
    FROM lab4.extended_all_sizes_measurements
    WHERE operation_name = 'insert'

    UNION ALL

    SELECT
        'update_raw_rows_expected_200',
        count(*),
        CASE WHEN count(*) = 200 THEN 'OK' ELSE 'FAIL' END
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
)
SELECT *
FROM checks
ORDER BY check_name;
"

echo
echo "=== EXTENDED AUDIT: heavy non-indexed SELECT seconds check ==="
"${PSQL[@]}" -c "
SELECT
    rows_base,
    count(*) AS runs,
    min(probes) AS probes_min,
    max(probes) AS probes_max,
    round(avg(total_elapsed_ms) / 1000.0, 3) AS avg_total_elapsed_seconds,
    round(avg(elapsed_ms_per_operation), 6) AS avg_elapsed_ms_per_select,
    CASE
        WHEN avg(total_elapsed_ms) >= 1000 THEN 'OK'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.extended_all_sizes_measurements
WHERE operation_name = 'select'
  AND index_type = 'without_index_nonclustered'
  AND rows_base IN (25000000, 50000000)
GROUP BY rows_base
ORDER BY rows_base;
"

echo
echo "=== EXTENDED AUDIT: expected report CSV files ==="

expected_reports=(
  "report/10_extended_all_sizes_raw.csv"
  "report/10_extended_all_sizes_aggregated.csv"
  "report/10_extended_all_sizes_sizes.csv"
  "report/10_extended_all_sizes_checks.csv"
  "report/10_extended_all_sizes_heavy_seconds_check.csv"
)

for f in "${expected_reports[@]}"; do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: $f"
  fi
done

echo
echo "=== EXTENDED AUDIT: expected chart files ==="

expected_charts=(
  "charts/10_ext_select_avg_ms.png"
  "charts/10_ext_select_total_seconds.png"
  "charts/10_ext_insert_total_ms.png"
  "charts/10_ext_insert_per_row_ms.png"
  "charts/10_ext_update_total_ms.png"
  "charts/10_ext_update_per_row_ms.png"
  "charts/10_ext_final_total_sizes.png"
  "charts/10_ext_final_index_sizes.png"
)

for f in "${expected_charts[@]}"; do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: $f"
  fi
done

echo
echo "=== EXTENDED AUDIT DONE ==="
