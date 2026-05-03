#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report logs

export PGPASSWORD=lab4pass

psql \
  -h 127.0.0.1 \
  -p 15435 \
  -U lab4user \
  -d subd_lab4_clean \
  -v ON_ERROR_STOP=1 \
  -P pager=off \
  -c "\copy (
    SELECT
      rows_actual,
      database_bytes,
      relation_bytes,
      relation_pages,
      total_relation_bytes,
      indexes_bytes,
      toast_bytes,
      avg_relation_bytes_per_row,
      avg_total_bytes_per_row
    FROM lab4.storage_growth_measurements
    ORDER BY rows_actual
  ) TO 'report/01_storage_growth.csv' WITH (FORMAT csv, HEADER true)"

echo "exported: report/01_storage_growth.csv"
