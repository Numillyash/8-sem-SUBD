#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off -At)

echo "=== Row counts after heavy SELECT ==="
"${PSQL[@]}" -c "
SELECT 'heavy_select_no_index=' || count(*) FROM lab4.heavy_select_no_index
UNION ALL
SELECT 'heavy_select_btree=' || count(*) FROM lab4.heavy_select_btree;
"

echo "=== Measurement groups ==="
"${PSQL[@]}" -c "
SELECT index_state || ' | rows=' || rows_before ||
       ' | runs=' || count(*) ||
       ' | probes=' || min(probes_count) || '..' || max(probes_count) ||
       ' | found=' || min(found_rows) || '..' || max(found_rows) ||
       ' | avg_total_sec=' || round(avg(total_elapsed_seconds), 3) ||
       ' | avg_one_select_ms=' || round(avg(avg_elapsed_ms), 6)
FROM lab4.heavy_select_measurements
GROUP BY index_state, rows_before
ORDER BY rows_before, index_state;
"

echo "=== Seconds check for non-indexed nonclustered SELECT ==="
"${PSQL[@]}" -c "
SELECT rows_before || ' rows | avg_total_sec=' || round(avg(total_elapsed_seconds), 3) ||
       ' | ' ||
       CASE
         WHEN avg(total_elapsed_seconds) >= 1
         THEN 'OK'
         ELSE 'FAIL'
       END
FROM lab4.heavy_select_measurements
WHERE index_state = 'without_index_nonclustered'
GROUP BY rows_before
ORDER BY rows_before;
"

echo "=== Correctness check ==="
"${PSQL[@]}" -c "
SELECT index_state || ' | sizes=' || count(DISTINCT rows_before) ||
       ' | total_runs=' || count(*) ||
       ' | found_min=' || min(found_rows) ||
       ' | probes_min=' || min(probes_count) ||
       ' | ' ||
       CASE
         WHEN min(found_rows) = min(probes_count)
          AND max(found_rows) = max(probes_count)
         THEN 'OK'
         ELSE 'FAIL'
       END
FROM lab4.heavy_select_measurements
GROUP BY index_state
ORDER BY index_state;
"

echo "=== Expected files ==="
ls -lah \
  logs/07_heavy_select_nonclustered.log \
  logs/08_export_heavy_select_nonclustered.log \
  report/08_heavy_select_nonclustered_measurements.csv \
  report/08_heavy_select_nonclustered_sizes.csv \
  charts/08_heavy_select_total_seconds.png \
  charts/08_heavy_select_avg_ms.png
