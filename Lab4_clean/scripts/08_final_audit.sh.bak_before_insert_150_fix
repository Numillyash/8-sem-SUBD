#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report logs

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

PSQL_CSV=(
  psql
  -h 127.0.0.1
  -p 15435
  -U lab4user
  -d subd_lab4_clean
  -v ON_ERROR_STOP=1
  -P pager=off
  --csv
)

echo "=== FINAL AUDIT: database objects ==="

"${PSQL[@]}" <<'SQL'
SELECT
    object_name,
    rows_count
FROM (
    SELECT 'lab4.user_log_storage' AS object_name, count(*)::text AS rows_count FROM lab4.user_log_storage
    UNION ALL SELECT 'lab4.orders_plain', count(*)::text FROM lab4.orders_plain
    UNION ALL SELECT 'lab4.orders_partitioned', count(*)::text FROM lab4.orders_partitioned
    UNION ALL SELECT 'lab4.partition_measurements', count(*)::text FROM lab4.partition_measurements
    UNION ALL SELECT 'lab4.select_measurements', count(*)::text FROM lab4.select_measurements
    UNION ALL SELECT 'lab4.insert_measurements', count(*)::text FROM lab4.insert_measurements
    UNION ALL SELECT 'lab4.update_measurements', count(*)::text FROM lab4.update_measurements
    UNION ALL SELECT 'lab4.update_trigger_audit', count(*)::text FROM lab4.update_trigger_audit
    UNION ALL SELECT 'lab4.heavy_select_no_index', count(*)::text FROM lab4.heavy_select_no_index
    UNION ALL SELECT 'lab4.heavy_select_btree', count(*)::text FROM lab4.heavy_select_btree
    UNION ALL SELECT 'lab4.heavy_select_measurements', count(*)::text FROM lab4.heavy_select_measurements
) AS t
ORDER BY object_name;
SQL

"${PSQL_CSV[@]}" > report/09_final_database_object_counts.csv <<'SQL'
SELECT
    object_name,
    rows_count
FROM (
    SELECT 'lab4.user_log_storage' AS object_name, count(*)::text AS rows_count FROM lab4.user_log_storage
    UNION ALL SELECT 'lab4.orders_plain', count(*)::text FROM lab4.orders_plain
    UNION ALL SELECT 'lab4.orders_partitioned', count(*)::text FROM lab4.orders_partitioned
    UNION ALL SELECT 'lab4.partition_measurements', count(*)::text FROM lab4.partition_measurements
    UNION ALL SELECT 'lab4.select_measurements', count(*)::text FROM lab4.select_measurements
    UNION ALL SELECT 'lab4.insert_measurements', count(*)::text FROM lab4.insert_measurements
    UNION ALL SELECT 'lab4.update_measurements', count(*)::text FROM lab4.update_measurements
    UNION ALL SELECT 'lab4.update_trigger_audit', count(*)::text FROM lab4.update_trigger_audit
    UNION ALL SELECT 'lab4.heavy_select_no_index', count(*)::text FROM lab4.heavy_select_no_index
    UNION ALL SELECT 'lab4.heavy_select_btree', count(*)::text FROM lab4.heavy_select_btree
    UNION ALL SELECT 'lab4.heavy_select_measurements', count(*)::text FROM lab4.heavy_select_measurements
) AS t
ORDER BY object_name;
SQL

echo
echo "=== FINAL AUDIT: measurement checks ==="

"${PSQL[@]}" <<'SQL'
SELECT
    'partition_measurements_expected_60' AS check_name,
    count(*) AS actual_value,
    CASE WHEN count(*) = 60 THEN 'OK' ELSE 'FAIL' END AS check_result
FROM lab4.partition_measurements

UNION ALL

SELECT
    'select_measurements_expected_50',
    count(*),
    CASE WHEN count(*) = 50 THEN 'OK' ELSE 'FAIL' END
FROM lab4.select_measurements

UNION ALL

SELECT
    'insert_measurements_expected_125',
    count(*),
    CASE WHEN count(*) = 125 THEN 'OK' ELSE 'FAIL' END
FROM lab4.insert_measurements

UNION ALL

SELECT
    'update_measurements_expected_125',
    count(*),
    CASE WHEN count(*) = 125 THEN 'OK' ELSE 'FAIL' END
FROM lab4.update_measurements

UNION ALL

SELECT
    'heavy_select_measurements_expected_18',
    count(*),
    CASE WHEN count(*) = 18 THEN 'OK' ELSE 'FAIL' END
FROM lab4.heavy_select_measurements;
SQL

"${PSQL_CSV[@]}" > report/09_final_measurement_checks.csv <<'SQL'
SELECT
    'partition_measurements_expected_60' AS check_name,
    count(*) AS actual_value,
    CASE WHEN count(*) = 60 THEN 'OK' ELSE 'FAIL' END AS check_result
FROM lab4.partition_measurements

UNION ALL

SELECT
    'select_measurements_expected_50',
    count(*),
    CASE WHEN count(*) = 50 THEN 'OK' ELSE 'FAIL' END
FROM lab4.select_measurements

UNION ALL

SELECT
    'insert_measurements_expected_125',
    count(*),
    CASE WHEN count(*) = 125 THEN 'OK' ELSE 'FAIL' END
FROM lab4.insert_measurements

UNION ALL

SELECT
    'update_measurements_expected_125',
    count(*),
    CASE WHEN count(*) = 125 THEN 'OK' ELSE 'FAIL' END
FROM lab4.update_measurements

UNION ALL

SELECT
    'heavy_select_measurements_expected_18',
    count(*),
    CASE WHEN count(*) = 18 THEN 'OK' ELSE 'FAIL' END
FROM lab4.heavy_select_measurements;
SQL

echo
echo "=== FINAL AUDIT: heavy SELECT seconds check ==="

"${PSQL[@]}" <<'SQL'
SELECT
    rows_before,
    count(*) AS runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    round(avg(total_elapsed_seconds), 3) AS avg_total_elapsed_seconds,
    round(avg(avg_elapsed_ms), 6) AS avg_elapsed_ms_per_select,
    CASE
        WHEN avg(total_elapsed_seconds) >= 1
        THEN 'OK: average series time is at least 1 second'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.heavy_select_measurements
WHERE index_state = 'without_index_nonclustered'
GROUP BY rows_before
ORDER BY rows_before;
SQL

"${PSQL_CSV[@]}" > report/09_final_heavy_select_seconds_check.csv <<'SQL'
SELECT
    rows_before,
    count(*) AS runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    round(avg(total_elapsed_seconds), 3) AS avg_total_elapsed_seconds,
    round(avg(avg_elapsed_ms), 6) AS avg_elapsed_ms_per_select,
    CASE
        WHEN avg(total_elapsed_seconds) >= 1
        THEN 'OK: average series time is at least 1 second'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.heavy_select_measurements
WHERE index_state = 'without_index_nonclustered'
GROUP BY rows_before
ORDER BY rows_before;
SQL

echo
echo "=== FINAL AUDIT: expected report CSV files ==="

expected_report_files=(
  report/01_storage_growth.csv
  report/storage_relation_file_check.csv
  report/02_partitioning_measurements.csv
  report/02_partitioning_sizes.csv
  report/03_select_index_measurements.csv
  report/03_select_index_sizes.csv
  report/04_insert_indexes_measurements.csv
  report/04_insert_indexes_sizes.csv
  report/05_update_indexes_measurements.csv
  report/05_update_indexes_sizes.csv
  report/05_update_trigger_control.csv
  report/08_heavy_select_nonclustered_measurements.csv
  report/08_heavy_select_nonclustered_sizes.csv
  report/09_final_database_object_counts.csv
  report/09_final_measurement_checks.csv
  report/09_final_heavy_select_seconds_check.csv
)

for f in "${expected_report_files[@]}"; do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: missing or empty $f"
  fi
done

echo
echo "=== FINAL AUDIT: expected chart files ==="

expected_chart_files=(
  charts/01_storage_growth_relation.png
  charts/02_partitioning.png
  charts/03_select_index.png
  charts/03_select_index_btree_zoom.png
  charts/04_insert_indexes.png
  charts/04_insert_indexes_per_row.png
  charts/05_update_indexes.png
  charts/05_update_indexes_per_row.png
  charts/08_heavy_select_total_seconds.png
  charts/08_heavy_select_avg_ms.png
)

for f in "${expected_chart_files[@]}"; do
  if [[ -s "$f" ]]; then
    echo "OK: $f"
  else
    echo "FAIL: missing or empty $f"
  fi
done

echo
echo "=== FINAL AUDIT: artifact manifest ==="

{
  echo "kind,path,size_bytes"
  find logs report charts sql scripts -type f | sort | while read -r f; do
    size=$(stat -c%s "$f")
    case "$f" in
      logs/*) kind="log" ;;
      report/*) kind="report_csv" ;;
      charts/*) kind="chart" ;;
      sql/*) kind="sql" ;;
      scripts/*) kind="script" ;;
      *) kind="file" ;;
    esac
    echo "$kind,$f,$size"
  done
} > report/09_final_artifact_manifest.csv

cat report/09_final_artifact_manifest.csv

echo
echo "=== FINAL AUDIT DONE ==="
