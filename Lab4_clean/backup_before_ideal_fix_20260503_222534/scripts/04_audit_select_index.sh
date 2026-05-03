#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -At)

echo "=== Row counts ==="
"${PSQL[@]}" -c "
SELECT 'select_no_index=' || count(*) FROM lab4.select_no_index
UNION ALL
SELECT 'select_btree_index=' || count(*) FROM lab4.select_btree_index;
"

echo "=== Measurement groups ==="
"${PSQL[@]}" -c "
SELECT index_state || ' | rows=' || rows_before || ' | runs=' || count(*) ||
       ' | probes=' || min(probes_count) || '..' || max(probes_count) ||
       ' | found=' || min(found_rows) || '..' || max(found_rows) ||
       ' | avg_ms=' || round(avg(avg_elapsed_ms), 6)
FROM lab4.select_measurements
GROUP BY index_state, rows_before
ORDER BY rows_before, index_state;
"

echo "=== Correctness check ==="
"${PSQL[@]}" -c "
SELECT index_state || ' | sizes=' || count(DISTINCT rows_before) ||
       ' | total_runs=' || count(*) ||
       ' | probes=' || min(probes_count) || '..' || max(probes_count) ||
       ' | found=' || min(found_rows) || '..' || max(found_rows) ||
       ' | ' ||
       CASE
         WHEN min(found_rows) = min(probes_count)
          AND max(found_rows) = max(probes_count)
         THEN 'OK'
         ELSE 'FAIL'
       END
FROM lab4.select_measurements
GROUP BY index_state
ORDER BY index_state;
"

echo "=== Expected files ==="
ls -lah \
  logs/03_select_index.log \
  logs/04_export_select_index.log \
  report/03_select_index_measurements.csv \
  report/03_select_index_sizes.csv \
  charts/03_select_index.png
