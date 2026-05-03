\pset pager off
\timing on
\set ON_ERROR_STOP on

\echo '=== ЛР-4. Шаг 5: влияние индексов на INSERT ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.insert_measurements CASCADE;

DROP TABLE IF EXISTS lab4.insert_no_index CASCADE;
DROP TABLE IF EXISTS lab4.insert_simple_btree CASCADE;
DROP TABLE IF EXISTS lab4.insert_unique_btree CASCADE;
DROP TABLE IF EXISTS lab4.insert_expression_index CASCADE;
DROP TABLE IF EXISTS lab4.insert_function_index CASCADE;

DROP FUNCTION IF EXISTS lab4.insert_function_key(text) CASCADE;
DROP FUNCTION IF EXISTS lab4.fill_insert_table(text, bigint) CASCADE;
DROP FUNCTION IF EXISTS lab4.measure_insert_table(text, text, bigint, bigint, integer) CASCADE;

CREATE TABLE lab4.insert_measurements (
    measurement_id             bigserial PRIMARY KEY,
    measured_at                timestamp NOT NULL DEFAULT clock_timestamp(),
    table_name                 text NOT NULL,
    index_type                 text NOT NULL,
    rows_base                  bigint NOT NULL,
    rows_before_actual         bigint NOT NULL,
    batch_size                 bigint NOT NULL,
    run_no                     integer NOT NULL,
    total_elapsed_ms           numeric(14, 3) NOT NULL,
    avg_elapsed_ms_per_row     numeric(14, 6) NOT NULL,
    inserted_rows              bigint NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.insert_function_key(p_payload text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT md5(p_payload || ':' || length(p_payload)::text || ':' || substring(p_payload from 1 for 16));
$$;

CREATE TABLE lab4.insert_no_index (
    id          bigint NOT NULL,
    customer_id integer NOT NULL,
    unique_key  bigint NOT NULL,
    code        text NOT NULL,
    amount      numeric(12, 2) NOT NULL,
    payload     text NOT NULL
);

CREATE TABLE lab4.insert_simple_btree     (LIKE lab4.insert_no_index);
CREATE TABLE lab4.insert_unique_btree     (LIKE lab4.insert_no_index);
CREATE TABLE lab4.insert_expression_index (LIKE lab4.insert_no_index);
CREATE TABLE lab4.insert_function_index   (LIKE lab4.insert_no_index);

CREATE INDEX idx_insert_simple_customer
ON lab4.insert_simple_btree (customer_id);

CREATE UNIQUE INDEX idx_insert_unique_key
ON lab4.insert_unique_btree (unique_key);

CREATE INDEX idx_insert_expression_lower_code
ON lab4.insert_expression_index ((lower(code)));

CREATE INDEX idx_insert_function_payload
ON lab4.insert_function_index (lab4.insert_function_key(payload));

CREATE OR REPLACE FUNCTION lab4.fill_insert_table(
    p_table_name text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('TRUNCATE TABLE lab4.%I', p_table_name);

    EXECUTE format(
        'INSERT INTO lab4.%I (id, customer_id, unique_key, code, amount, payload)
         SELECT
             v_id,
             (((v_id * 7919) %% 100000)::integer + 1) AS customer_id,
             v_id AS unique_key,
             ''code_'' || (v_id %% 50000)::text AS code,
             round((((v_id * 37) %% 100000)::numeric / 100 + 10), 2) AS amount,
             md5(v_id::text || ''_insert_base'') || md5((v_id * 17)::text)
         FROM generate_series(1::bigint, %s::bigint) AS v_id',
        p_table_name,
        p_rows
    );

    EXECUTE format('ANALYZE lab4.%I', p_table_name);
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_insert_table(
    p_table_name text,
    p_index_type text,
    p_rows_base bigint,
    p_batch_size bigint DEFAULT 1000,
    p_runs integer DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run integer;
    v_start bigint;
    v_end bigint;
    v_rows_before bigint;
    v_inserted bigint;
    t1 double precision;
    t2 double precision;
BEGIN
    PERFORM lab4.fill_insert_table(p_table_name, p_rows_base);

    FOR v_run IN 1..p_runs LOOP
        EXECUTE format('SELECT count(*) FROM lab4.%I', p_table_name)
        INTO v_rows_before;

        v_start := p_rows_base + ((v_run - 1) * p_batch_size) + 1;
        v_end   := p_rows_base + (v_run * p_batch_size);

        t1 := extract(epoch FROM clock_timestamp()) * 1000;

        EXECUTE format(
            'INSERT INTO lab4.%I (id, customer_id, unique_key, code, amount, payload)
             SELECT
                 v_id,
                 (((v_id * 7919) %% 100000)::integer + 1) AS customer_id,
                 v_id AS unique_key,
                 ''code_'' || (v_id %% 50000)::text AS code,
                 round((((v_id * 37) %% 100000)::numeric / 100 + 10), 2) AS amount,
                 md5(v_id::text || ''_insert_batch'') || md5((v_id * 17)::text)
             FROM generate_series(%s::bigint, %s::bigint) AS v_id',
            p_table_name,
            v_start,
            v_end
        );

        GET DIAGNOSTICS v_inserted = ROW_COUNT;

        t2 := extract(epoch FROM clock_timestamp()) * 1000;

        INSERT INTO lab4.insert_measurements (
            table_name,
            index_type,
            rows_base,
            rows_before_actual,
            batch_size,
            run_no,
            total_elapsed_ms,
            avg_elapsed_ms_per_row,
            inserted_rows
        )
        VALUES (
            p_table_name,
            p_index_type,
            p_rows_base,
            v_rows_before,
            p_batch_size,
            v_run,
            round((t2 - t1)::numeric, 3),
            round(((t2 - t1)::numeric / p_batch_size), 6),
            v_inserted
        );
    END LOOP;
END;
$$;

\echo '=== 5.1. Запуск серий INSERT по размерам таблицы ==='

DO $$
DECLARE
    v_rows bigint;
BEGIN
    FOREACH v_rows IN ARRAY ARRAY[
        10000::bigint,
        50000::bigint,
        100000::bigint,
        500000::bigint,
        1000000::bigint
    ]
    LOOP
        RAISE NOTICE 'Running INSERT size %', v_rows;

        PERFORM lab4.measure_insert_table('insert_no_index',          'no_index',         v_rows, 1000, 6);
        PERFORM lab4.measure_insert_table('insert_simple_btree',      'simple_btree',     v_rows, 1000, 6);
        PERFORM lab4.measure_insert_table('insert_unique_btree',      'unique_btree',     v_rows, 1000, 6);
        PERFORM lab4.measure_insert_table('insert_expression_index',  'expression_index', v_rows, 1000, 6);
        PERFORM lab4.measure_insert_table('insert_function_index',    'function_index',   v_rows, 1000, 6);
    END LOOP;
END $$;

\echo '=== 5.2. Итоговая таблица INSERT ==='

SELECT
    index_type,
    rows_base,
    count(*) AS runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(inserted_rows) AS inserted_rows_min,
    max(inserted_rows) AS inserted_rows_max,
    round(avg(total_elapsed_ms), 3) AS avg_total_elapsed_ms,
    round(min(total_elapsed_ms), 3) AS min_total_elapsed_ms,
    round(max(total_elapsed_ms), 3) AS max_total_elapsed_ms,
    round(stddev_samp(total_elapsed_ms), 3) AS stddev_total_elapsed_ms,
    round(avg(avg_elapsed_ms_per_row), 6) AS avg_elapsed_ms_per_row
FROM lab4.insert_measurements
GROUP BY index_type, rows_base
ORDER BY
    rows_base,
    CASE index_type
        WHEN 'no_index' THEN 1
        WHEN 'simple_btree' THEN 2
        WHEN 'unique_btree' THEN 3
        WHEN 'expression_index' THEN 4
        WHEN 'function_index' THEN 5
        ELSE 6
    END;

\echo '=== 5.3. Проверка корректности INSERT ==='

SELECT
    index_type,
    count(DISTINCT rows_base) AS tested_table_sizes,
    count(*) AS total_runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(inserted_rows) AS inserted_rows_min,
    max(inserted_rows) AS inserted_rows_max,
    CASE
        WHEN min(inserted_rows) = min(batch_size)
         AND max(inserted_rows) = max(batch_size)
        THEN 'OK: every INSERT batch inserted expected rows'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.insert_measurements
GROUP BY index_type
ORDER BY index_type;

\echo '=== 5.4. Размеры таблиц INSERT после финального размера ==='

SELECT
    c.relname AS table_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_size_pretty(pg_relation_size(c.oid)) AS relation_size,
    pg_indexes_size(c.oid) AS indexes_bytes,
    pg_size_pretty(pg_indexes_size(c.oid)) AS indexes_size,
    pg_total_relation_size(c.oid) AS total_bytes,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab4'
  AND c.relname IN (
      'insert_no_index',
      'insert_simple_btree',
      'insert_unique_btree',
      'insert_expression_index',
      'insert_function_index'
  )
ORDER BY c.relname;

\echo '=== Шаг 5 SQL завершен ==='
