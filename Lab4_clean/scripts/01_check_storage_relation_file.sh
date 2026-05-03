#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p logs report

export PGPASSWORD=lab4pass

REL_INFO=$(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -At -P pager=off -c "
SELECT
    pg_relation_size('lab4.user_log_storage'::regclass)::text || ',' ||
    pg_total_relation_size('lab4.user_log_storage'::regclass)::text || ',' ||
    pg_relation_filepath('lab4.user_log_storage'::regclass);
")

PG_RELATION_BYTES=$(echo "$REL_INFO" | cut -d',' -f1)
PG_TOTAL_BYTES=$(echo "$REL_INFO" | cut -d',' -f2)
REL_PATH=$(echo "$REL_INFO" | cut -d',' -f3)

STAT_BYTES=$(docker exec subd_lab4_clean_pg stat -c '%s' "/var/lib/postgresql/data/${REL_PATH}")
DU_BYTES=$(docker exec subd_lab4_clean_pg du -b "/var/lib/postgresql/data/${REL_PATH}" | awk '{print $1}')

{
  echo "relation_name,pg_relation_bytes,pg_total_relation_bytes,relation_filepath,stat_bytes,du_bytes,check_result"
  if [[ "$PG_RELATION_BYTES" == "$STAT_BYTES" ]]; then
    echo "lab4.user_log_storage,$PG_RELATION_BYTES,$PG_TOTAL_BYTES,$REL_PATH,$STAT_BYTES,$DU_BYTES,OK"
  else
    echo "lab4.user_log_storage,$PG_RELATION_BYTES,$PG_TOTAL_BYTES,$REL_PATH,$STAT_BYTES,$DU_BYTES,FAIL"
  fi
} | tee report/storage_relation_file_check.csv
