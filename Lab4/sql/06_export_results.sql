\pset pager off

\echo '=== Экспорт итоговых таблиц ЛР-4 ==='

\copy (
    SELECT
        rows_in_table,
        database_bytes,
        relation_bytes,
        total_relation_bytes,
        indexes_bytes,
        toast_bytes,
        avg_relation_bytes_per_row,
        avg_total_bytes_per_row
    FROM lab4.storage_measurements
    ORDER BY rows_in_table
) TO 'report/storage_measurements.csv' WITH CSV HEADER;

\copy (
    SELECT
        test_name,
        table_name,
        round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
        round(min(elapsed_ms), 3) AS min_elapsed_ms,
        round(max(elapsed_ms), 3) AS max_elapsed_ms,
        round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
    FROM lab4.partition_measurements
    GROUP BY test_name, table_name
    ORDER BY
        CASE test_name
            WHEN 'one_partition_range' THEN 1
            WHEN 'two_partitions_range' THEN 2
            WHEN 'three_partitions_range' THEN 3
            WHEN 'full_table_range' THEN 4
            ELSE 5
        END,
        table_name
) TO 'report/partition_measurements.csv' WITH CSV HEADER;

\copy (
    SELECT
        test_name,
        index_state,
        round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
        round(min(elapsed_ms), 3) AS min_elapsed_ms,
        round(max(elapsed_ms), 3) AS max_elapsed_ms,
        round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
    FROM lab4.index_select_measurements
    GROUP BY test_name, index_state
    ORDER BY index_state
) TO 'report/index_select_measurements.csv' WITH CSV HEADER;

\copy (
    SELECT
        operation_name,
        index_type,
        round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
        round(min(elapsed_ms), 3) AS min_elapsed_ms,
        round(max(elapsed_ms), 3) AS max_elapsed_ms,
        round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
    FROM lab4.insert_update_measurements
    GROUP BY operation_name, index_type
    ORDER BY operation_name, index_type
) TO 'report/insert_update_measurements.csv' WITH CSV HEADER;

\copy (
    SELECT
        test_name,
        index_type,
        round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
        round(min(elapsed_ms), 3) AS min_elapsed_ms,
        round(max(elapsed_ms), 3) AS max_elapsed_ms,
        round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
    FROM lab4.clean_update_measurements
    GROUP BY test_name, index_type
    ORDER BY test_name, index_type
) TO 'report/clean_update_measurements.csv' WITH CSV HEADER;

\copy (
    SELECT
        relname AS table_name,
        pg_relation_size(('lab4.' || relname)::regclass) AS relation_bytes,
        pg_indexes_size(('lab4.' || relname)::regclass) AS indexes_bytes,
        pg_total_relation_size(('lab4.' || relname)::regclass) AS total_bytes
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'lab4'
      AND relname IN (
          'mod_no_index',
          'mod_simple_index',
          'mod_unique_index',
          'mod_expr_index',
          'mod_func_index',
          'clean_no_index',
          'clean_customer_index',
          'clean_code_index',
          'clean_payload_func_index'
      )
    ORDER BY relname
) TO 'report/table_sizes.csv' WITH CSV HEADER;

\echo '=== Экспорт завершен ==='
