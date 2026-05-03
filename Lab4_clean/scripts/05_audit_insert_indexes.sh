#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -At)

echo "=== Row counts after final INSERT series ==="
"${PSQL[@]}" -c "
SELECT 'insert_no_index=' || count(*) FROM lab4.insert_no_index
UNION ALL
SELECT 'insert_simple_btree=' || count(*) FROM lab4.insert_simple_btree
UNION ALL
SELECT 'insert_unique_btree=' || count(*) FROM lab4.insert_unique_btree
UNION ALL
SELECT 'insert_expression_index=' || count(*) FROM lab4.insert_expression_index
UNION ALL
SELECT 'insert_function_index=' || count(*) FROM lab4.insert_function_index;
"

echo "=== Measurement groups ==="
"${PSQL[@]}" -c "
SELECT index_type || ' | rows_base=' || rows_base || ' | runs=' || count(*) ||
       ' | batch=' || min(batch_size) || '..' || max(batch_size) ||
       ' | inserted=' || min(inserted_rows) || '..' || max(inserted_rows) ||
       ' | avg_total_ms=' || round(avg(total_elapsed_ms), 3) ||
       ' | avg_per_row_ms=' || round(avg(avg_elapsed_ms_per_row), 6)
FROM lab4.insert_measurements
GROUP BY index_type, rows_base
ORDER BY rows_base, index_type;
"

echo "=== Correctness check ==="
"${PSQL[@]}" -c "
SELECT index_type || ' | sizes=' || count(DISTINCT rows_base) ||
       ' | total_runs=' || count(*) ||
       ' | batch=' || min(batch_size) || '..' || max(batch_size) ||
       ' | inserted=' || min(inserted_rows) || '..' || max(inserted_rows) ||
       ' | ' ||
       CASE
         WHEN min(inserted_rows) = min(batch_size)
          AND max(inserted_rows) = max(batch_size)
         THEN 'OK'
         ELSE 'FAIL'
       END
FROM lab4.insert_measurements
GROUP BY index_type
ORDER BY index_type;
"

echo "=== Expected files ==="
ls -lah \
  logs/04_insert_indexes.log \
  logs/05_export_insert_indexes.log \
  report/04_insert_indexes_measurements.csv \
  report/04_insert_indexes_sizes.csv \
  charts/04_insert_indexes.png \
  charts/04_insert_indexes_per_row.png
