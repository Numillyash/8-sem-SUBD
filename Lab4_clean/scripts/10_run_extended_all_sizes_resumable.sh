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

psql_scalar() {
  "${PSQL[@]}" -At -c "$1"
}

psql_exec() {
  "${PSQL[@]}" -c "$1"
}

need_setup="$(psql_scalar "
SELECT CASE
    WHEN to_regclass('lab4.extended_all_sizes_measurements') IS NULL
      OR to_regprocedure('lab4.ext_prepare_select(bigint)') IS NULL
      OR to_regprocedure('lab4.ext_prepare_insert_table(bigint)') IS NULL
      OR to_regprocedure('lab4.ext_prepare_update_table(bigint)') IS NULL
    THEN 'yes'
    ELSE 'no'
END;
")"

if [[ "${RESET_EXTENDED:-0}" == "1" || "$need_setup" == "yes" ]]; then
  echo "=== Running extended setup. Existing extended measurements will be reset. ==="
  "${PSQL[@]}" -f sql/07a_extended_setup_only.sql
fi

sizes=(10 100 1000 10000 100000 1000000 25000000 50000000)
insert_indexes=(no_index simple_btree unique_btree expression_index function_index)
update_indexes=(no_extra_index simple_btree unique_btree expression_index function_index)

select_done_count() {
  local rows="$1"
  psql_scalar "
SELECT count(*)
FROM lab4.extended_all_sizes_measurements
WHERE operation_name = 'select'
  AND rows_base = ${rows};
"
}

combo_done_count() {
  local operation="$1"
  local index_type="$2"
  local rows="$3"
  psql_scalar "
SELECT count(*)
FROM lab4.extended_all_sizes_measurements
WHERE operation_name = '${operation}'
  AND index_type = '${index_type}'
  AND rows_base = ${rows};
"
}

for rows in "${sizes[@]}"; do
  if [[ "$rows" -ge 50000000 ]]; then
    select_probes=5
  elif [[ "$rows" -ge 25000000 ]]; then
    select_probes=10
  else
    select_probes=200
  fi

  if [[ "$rows" -lt 1000 ]]; then
    batch_size="$rows"
  else
    batch_size=1000
  fi

  echo
  echo "============================================================"
  echo "EXTENDED SIZE: ${rows}"
  echo "============================================================"

  select_count="$(select_done_count "$rows")"

  if [[ "$select_count" -eq 12 ]]; then
    echo "SELECT size ${rows}: already done"
  else
    echo "SELECT size ${rows}: running from scratch"

    psql_exec "
DELETE FROM lab4.extended_all_sizes_measurements
WHERE operation_name = 'select'
  AND rows_base = ${rows};

DELETE FROM lab4.extended_all_sizes_sizes
WHERE operation_name = 'select'
  AND rows_base = ${rows};

DROP TABLE IF EXISTS lab4.ext_select_work;
"

    psql_exec "SELECT lab4.ext_prepare_select(${rows});"

    psql_exec "
SELECT lab4.ext_measure_select(
    'without_index_nonclustered',
    ${rows},
    ${select_probes},
    6
);
"

    psql_exec "
CREATE INDEX idx_ext_select_lookup
ON lab4.ext_select_work (lookup_key);

ANALYZE lab4.ext_select_work;

SELECT lab4.ext_record_size(
    'select',
    'btree_index_nonclustered',
    ${rows},
    'lab4.ext_select_work'
);
"

    psql_exec "
SELECT lab4.ext_measure_select(
    'btree_index_nonclustered',
    ${rows},
    ${select_probes},
    6
);
"

    psql_exec "DROP TABLE IF EXISTS lab4.ext_select_work;"
  fi

  echo
  echo "INSERT size ${rows}, batch ${batch_size}"

  for index_type in "${insert_indexes[@]}"; do
    done_count="$(combo_done_count insert "$index_type" "$rows")"

    if [[ "$done_count" -eq 5 ]]; then
      echo "INSERT size ${rows}, index ${index_type}: already done"
      continue
    fi

    echo "INSERT size ${rows}, index ${index_type}: running"

    psql_exec "
DELETE FROM lab4.extended_all_sizes_measurements
WHERE operation_name = 'insert'
  AND index_type = '${index_type}'
  AND rows_base = ${rows};

DELETE FROM lab4.extended_all_sizes_sizes
WHERE operation_name = 'insert'
  AND index_type = '${index_type}'
  AND rows_base = ${rows};

DROP TABLE IF EXISTS lab4.ext_insert_work;
"

    psql_exec "SELECT lab4.ext_prepare_insert_table(${rows});"
    psql_exec "SELECT lab4.ext_apply_insert_index('${index_type}', ${rows});"
    psql_exec "SELECT lab4.ext_measure_insert_table('${index_type}', ${rows}, ${batch_size}, 5);"
    psql_exec "DROP TABLE IF EXISTS lab4.ext_insert_work;"
  done

  echo
  echo "UPDATE size ${rows}, batch ${batch_size}"

  for index_type in "${update_indexes[@]}"; do
    done_count="$(combo_done_count update "$index_type" "$rows")"

    if [[ "$done_count" -eq 5 ]]; then
      echo "UPDATE size ${rows}, index ${index_type}: already done"
      continue
    fi

    echo "UPDATE size ${rows}, index ${index_type}: running"

    psql_exec "
DELETE FROM lab4.extended_update_trigger_audit
WHERE index_type = '${index_type}'
  AND rows_base = ${rows};

DELETE FROM lab4.extended_all_sizes_measurements
WHERE operation_name = 'update'
  AND index_type = '${index_type}'
  AND rows_base = ${rows};

DELETE FROM lab4.extended_all_sizes_sizes
WHERE operation_name = 'update'
  AND index_type = '${index_type}'
  AND rows_base = ${rows};

DROP TABLE IF EXISTS lab4.ext_update_work;
"

    psql_exec "SELECT lab4.ext_prepare_update_table(${rows});"
    psql_exec "SELECT lab4.ext_apply_update_index('${index_type}', ${rows});"
    psql_exec "SELECT lab4.ext_measure_update_table('${index_type}', ${rows}, ${batch_size}, 5);"
    psql_exec "DROP TABLE IF EXISTS lab4.ext_update_work;"
  done
done

echo
echo "=== EXTENDED RESUMABLE RUN DONE ==="

psql_exec "
SELECT
    operation_name,
    count(*) AS raw_measurements,
    count(DISTINCT rows_base) AS tested_table_sizes,
    min(rows_base) AS min_rows,
    max(rows_base) AS max_rows
FROM lab4.extended_all_sizes_measurements
GROUP BY operation_name
ORDER BY operation_name;
"
