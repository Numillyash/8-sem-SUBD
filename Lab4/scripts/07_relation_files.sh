#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4
mkdir -p report logs

export PGPASSWORD=lab4pass

OUT="report/relation_file_sizes.csv"
TMP="report/relation_file_paths.tsv"

psql -h 127.0.0.1 -p 15434 -U lab4user -d subd_lab4 -P pager=off -At -F $'\t' -c "
SELECT
    c.oid::regclass::text AS relation_name,
    pg_relation_size(c.oid) AS pg_relation_bytes,
    pg_total_relation_size(c.oid) AS pg_total_relation_bytes,
    pg_relation_filepath(c.oid) AS relation_filepath
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab4'
  AND c.relkind IN ('r', 'p')
  AND c.relname IN (
      'storage_plain',
      'orders_plain',
      'orders_partitioned_2024_q1',
      'orders_partitioned_2024_q2',
      'orders_partitioned_2024_q3',
      'orders_partitioned_2024_q4',
      'index_select_test',
      'mod_no_index',
      'mod_simple_index',
      'mod_unique_index',
      'mod_expr_index',
      'mod_func_index'
  )
ORDER BY relation_name;
" > "$TMP"

echo "relation_name,pg_relation_bytes,pg_total_relation_bytes,relation_filepath,stat_bytes,du_bytes" > "$OUT"

while IFS=$'\t' read -r relation_name pg_relation_bytes pg_total_relation_bytes relation_filepath; do
    stat_bytes="$(docker exec subd_lab4_pg bash -lc "stat -c '%s' /var/lib/postgresql/data/${relation_filepath}" 2>/dev/null || echo "NA")"
    du_bytes="$(docker exec subd_lab4_pg bash -lc "du -b /var/lib/postgresql/data/${relation_filepath} | awk '{print \$1}'" 2>/dev/null || echo "NA")"
    echo "${relation_name},${pg_relation_bytes},${pg_total_relation_bytes},${relation_filepath},${stat_bytes},${du_bytes}" >> "$OUT"
done < "$TMP"

cat "$OUT"
