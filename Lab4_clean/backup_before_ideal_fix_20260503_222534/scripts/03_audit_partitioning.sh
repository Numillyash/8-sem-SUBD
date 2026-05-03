#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -At)

echo "=== Row counts ==="
"${PSQL[@]}" -c "
SELECT 'orders_plain=' || count(*) FROM lab4.orders_plain
UNION ALL
SELECT 'orders_partitioned=' || count(*) FROM lab4.orders_partitioned;
"

echo "=== Measurement groups ==="
"${PSQL[@]}" -c "
SELECT test_name || ' | ' || table_name || ' | runs=' || count(*) || ' | avg_ms=' || round(avg(elapsed_ms), 3)
FROM lab4.partition_measurements
GROUP BY test_name, table_name
ORDER BY test_name, table_name;
"

echo "=== Result equality check ==="
"${PSQL[@]}" -c "
WITH grouped AS (
    SELECT test_name, table_name, min(result_value) AS result_value
    FROM lab4.partition_measurements
    GROUP BY test_name, table_name
),
pairs AS (
    SELECT
        p.test_name,
        p.result_value AS plain_result,
        q.result_value AS partitioned_result,
        p.result_value - q.result_value AS diff
    FROM grouped p
    JOIN grouped q ON q.test_name = p.test_name
    WHERE p.table_name = 'orders_plain'
      AND q.table_name = 'orders_partitioned'
)
SELECT test_name || ' | diff=' || diff || ' | ' ||
       CASE WHEN diff = 0 THEN 'OK' ELSE 'FAIL' END
FROM pairs
ORDER BY test_name;
"

echo "=== Expected files ==="
ls -lah \
  logs/02_partitioning.log \
  logs/03_export_partitioning.log \
  report/02_partitioning_measurements.csv \
  report/02_partitioning_sizes.csv \
  charts/02_partitioning.png
