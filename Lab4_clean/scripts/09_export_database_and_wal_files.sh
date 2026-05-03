#!/usr/bin/env bash
set -euo pipefail

cd /mnt/c/Users/Georgul/Documents/8_sem/SUBD/Lab4_clean
mkdir -p report logs

export PGPASSWORD=lab4pass

PSQL=(psql -h 127.0.0.1 -p 15435 -U lab4user -d subd_lab4_clean -P pager=off)

echo "=== Export database size ==="
"${PSQL[@]}" -c "\copy (
    SELECT
        current_database() AS database_name,
        pg_database_size(current_database()) AS database_bytes,
        pg_size_pretty(pg_database_size(current_database())) AS database_size
) TO 'report/09_database_size_after_heavy.csv' WITH CSV HEADER;"

echo "=== Export relation sizes ==="
"${PSQL[@]}" -c "\copy (
    SELECT
        n.nspname AS schema_name,
        c.relname AS relation_name,
        c.relkind AS relation_kind,
        pg_relation_size(c.oid) AS relation_bytes,
        pg_indexes_size(c.oid) AS indexes_bytes,
        pg_total_relation_size(c.oid) AS total_bytes,
        pg_size_pretty(pg_relation_size(c.oid)) AS relation_size,
        pg_size_pretty(pg_indexes_size(c.oid)) AS indexes_size,
        pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'lab4'
      AND c.relkind IN ('r', 'p')
    ORDER BY pg_total_relation_size(c.oid) DESC, c.relname
) TO 'report/09_relation_sizes_after_heavy.csv' WITH CSV HEADER;"

PG_CONTAINER="$(docker compose ps -q | head -n1)"

echo "=== Export filesystem usage inside PostgreSQL container ==="
{
    echo "filesystem,size,used,available,use_percent,mountpoint"
    docker exec "$PG_CONTAINER" sh -lc "df -h /var/lib/postgresql/data | tail -n +2" \
        | awk '{print $1 "," $2 "," $3 "," $4 "," $5 "," $6}'
} > report/09_pg_data_filesystem_usage.csv

echo "=== Export pg_wal files ==="
{
    echo "wal_file,size_bytes"
    docker exec "$PG_CONTAINER" sh -lc "find /var/lib/postgresql/data/pg_wal -maxdepth 1 -type f -printf '%f,%s\n' | sort"
} > report/09_pg_wal_files.csv

echo "=== Export pg_wal summary ==="
{
    echo "wal_files_count,wal_total_bytes"
    docker exec "$PG_CONTAINER" sh -lc "find /var/lib/postgresql/data/pg_wal -maxdepth 1 -type f -printf '%s\n' | awk '{count++; sum+=\$1} END {print count \",\" sum}'"
} > report/09_pg_wal_summary.csv

echo "exported:"
echo "  report/09_database_size_after_heavy.csv"
echo "  report/09_relation_sizes_after_heavy.csv"
echo "  report/09_pg_data_filesystem_usage.csv"
echo "  report/09_pg_wal_files.csv"
echo "  report/09_pg_wal_summary.csv"
