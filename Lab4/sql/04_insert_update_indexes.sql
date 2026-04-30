\pset pager off
\timing on

\echo '=== ЛР-4. Блок 4: влияние индексов на INSERT и UPDATE ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.insert_update_measurements CASCADE;

DROP TABLE IF EXISTS lab4.mod_no_index CASCADE;
DROP TABLE IF EXISTS lab4.mod_simple_index CASCADE;
DROP TABLE IF EXISTS lab4.mod_unique_index CASCADE;
DROP TABLE IF EXISTS lab4.mod_expr_index CASCADE;
DROP TABLE IF EXISTS lab4.mod_func_index CASCADE;

CREATE TABLE lab4.insert_update_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at    timestamp NOT NULL DEFAULT clock_timestamp(),
    operation_name text NOT NULL,
    table_name     text NOT NULL,
    index_type     text NOT NULL,
    rows_before    bigint NOT NULL,
    affected_rows  bigint NOT NULL,
    run_no         integer NOT NULL,
    elapsed_ms     numeric(12, 3) NOT NULL
);

CREATE TABLE lab4.mod_no_index (
    id          bigint NOT NULL,
    customer_id integer NOT NULL,
    code        text NOT NULL,
    amount      numeric(12, 2) NOT NULL,
    payload     text NOT NULL,
    updated_at  timestamp NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE lab4.mod_simple_index (LIKE lab4.mod_no_index INCLUDING DEFAULTS);
CREATE TABLE lab4.mod_unique_index (LIKE lab4.mod_no_index INCLUDING DEFAULTS);
CREATE TABLE lab4.mod_expr_index   (LIKE lab4.mod_no_index INCLUDING DEFAULTS);
CREATE TABLE lab4.mod_func_index   (LIKE lab4.mod_no_index INCLUDING DEFAULTS);

CREATE INDEX idx_mod_simple_customer_id
ON lab4.mod_simple_index (customer_id);

CREATE UNIQUE INDEX idx_mod_unique_id
ON lab4.mod_unique_index (id);

CREATE INDEX idx_mod_expr_lower_code
ON lab4.mod_expr_index ((lower(code)));

CREATE OR REPLACE FUNCTION lab4.payload_prefix(p_payload text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT left(p_payload, 8);
$$;

CREATE INDEX idx_mod_func_payload_prefix
ON lab4.mod_func_index (lab4.payload_prefix(payload));

CREATE OR REPLACE FUNCTION lab4.fill_mod_table(p_table_name text, p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('TRUNCATE TABLE lab4.%I', p_table_name);

    EXECUTE format(
        'INSERT INTO lab4.%I (id, customer_id, code, amount, payload)
         SELECT
             g,
             (g %% 50000)::integer + 1,
             ''code_'' || (g %% 10000)::text,
             round(((g %% 100000)::numeric / 100 + 10), 2),
             md5(g::text || random()::text)
         FROM generate_series(1, %s) AS g',
        p_table_name,
        p_rows
    );

    EXECUTE format('ANALYZE lab4.%I', p_table_name);
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_insert_batch(
    p_table_name text,
    p_index_type text,
    p_rows_before bigint,
    p_insert_rows bigint,
    p_run_no integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    t1 double precision;
    t2 double precision;
BEGIN
    PERFORM lab4.fill_mod_table(p_table_name, p_rows_before);

    t1 := extract(epoch from clock_timestamp()) * 1000;

    EXECUTE format(
        'INSERT INTO lab4.%I (id, customer_id, code, amount, payload)
         SELECT
             %s + g,
             ((%s + g) %% 50000)::integer + 1,
             ''code_'' || ((%s + g) %% 10000)::text,
             round((((%s + g) %% 100000)::numeric / 100 + 10), 2),
             md5((%s + g)::text || random()::text)
         FROM generate_series(1, %s) AS g',
        p_table_name,
        p_rows_before,
        p_rows_before,
        p_rows_before,
        p_rows_before,
        p_rows_before,
        p_insert_rows
    );

    t2 := extract(epoch from clock_timestamp()) * 1000;

    INSERT INTO lab4.insert_update_measurements (
        operation_name,
        table_name,
        index_type,
        rows_before,
        affected_rows,
        run_no,
        elapsed_ms
    )
    VALUES (
        'insert_batch',
        p_table_name,
        p_index_type,
        p_rows_before,
        p_insert_rows,
        p_run_no,
        round((t2 - t1)::numeric, 3)
    );
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_nonindexed(
    p_table_name text,
    p_index_type text,
    p_rows_before bigint,
    p_run_no integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    t1 double precision;
    t2 double precision;
    v_affected bigint;
BEGIN
    PERFORM lab4.fill_mod_table(p_table_name, p_rows_before);

    t1 := extract(epoch from clock_timestamp()) * 1000;

    EXECUTE format(
        'UPDATE lab4.%I
         SET amount = amount + 1
         WHERE customer_id BETWEEN 10000 AND 10100',
        p_table_name
    );

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    t2 := extract(epoch from clock_timestamp()) * 1000;

    INSERT INTO lab4.insert_update_measurements (
        operation_name,
        table_name,
        index_type,
        rows_before,
        affected_rows,
        run_no,
        elapsed_ms
    )
    VALUES (
        'update_nonindexed_amount',
        p_table_name,
        p_index_type,
        p_rows_before,
        v_affected,
        p_run_no,
        round((t2 - t1)::numeric, 3)
    );
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_indexed(
    p_table_name text,
    p_index_type text,
    p_rows_before bigint,
    p_run_no integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    t1 double precision;
    t2 double precision;
    v_affected bigint;
BEGIN
    PERFORM lab4.fill_mod_table(p_table_name, p_rows_before);

    t1 := extract(epoch from clock_timestamp()) * 1000;

    IF p_table_name = 'mod_simple_index' THEN
        EXECUTE 'UPDATE lab4.mod_simple_index
                 SET customer_id = customer_id + 1000000
                 WHERE customer_id BETWEEN 10000 AND 10100';

    ELSIF p_table_name = 'mod_unique_index' THEN
        EXECUTE 'UPDATE lab4.mod_unique_index
                 SET id = id + 1000000000
                 WHERE customer_id BETWEEN 10000 AND 10100';

    ELSIF p_table_name = 'mod_expr_index' THEN
        EXECUTE 'UPDATE lab4.mod_expr_index
                 SET code = code || ''_upd''
                 WHERE customer_id BETWEEN 10000 AND 10100';

    ELSIF p_table_name = 'mod_func_index' THEN
        EXECUTE 'UPDATE lab4.mod_func_index
                 SET payload = md5(payload || random()::text)
                 WHERE customer_id BETWEEN 10000 AND 10100';

    ELSE
        EXECUTE 'UPDATE lab4.mod_no_index
                 SET payload = md5(payload || random()::text)
                 WHERE customer_id BETWEEN 10000 AND 10100';
    END IF;

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    t2 := extract(epoch from clock_timestamp()) * 1000;

    INSERT INTO lab4.insert_update_measurements (
        operation_name,
        table_name,
        index_type,
        rows_before,
        affected_rows,
        run_no,
        elapsed_ms
    )
    VALUES (
        'update_indexed_field',
        p_table_name,
        p_index_type,
        p_rows_before,
        v_affected,
        p_run_no,
        round((t2 - t1)::numeric, 3)
    );
END;
$$;

\echo '=== Размеры пустых таблиц с разными индексами ==='

SELECT
    relname AS table_name,
    pg_size_pretty(pg_relation_size(('lab4.' || relname)::regclass)) AS relation_size,
    pg_size_pretty(pg_indexes_size(('lab4.' || relname)::regclass)) AS indexes_size,
    pg_size_pretty(pg_total_relation_size(('lab4.' || relname)::regclass)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab4'
  AND relname IN (
      'mod_no_index',
      'mod_simple_index',
      'mod_unique_index',
      'mod_expr_index',
      'mod_func_index'
  )
ORDER BY relname;

\echo '=== Замеры INSERT batch: 100 000 строк в таблице, вставка 10 000 строк ==='

SELECT lab4.measure_insert_batch('mod_no_index',     'no_index',         100000, 10000, 1);
SELECT lab4.measure_insert_batch('mod_simple_index', 'simple_btree',     100000, 10000, 1);
SELECT lab4.measure_insert_batch('mod_unique_index', 'unique_btree',     100000, 10000, 1);
SELECT lab4.measure_insert_batch('mod_expr_index',   'expression_index', 100000, 10000, 1);
SELECT lab4.measure_insert_batch('mod_func_index',   'function_index',   100000, 10000, 1);

SELECT lab4.measure_insert_batch('mod_no_index',     'no_index',         100000, 10000, 2);
SELECT lab4.measure_insert_batch('mod_simple_index', 'simple_btree',     100000, 10000, 2);
SELECT lab4.measure_insert_batch('mod_unique_index', 'unique_btree',     100000, 10000, 2);
SELECT lab4.measure_insert_batch('mod_expr_index',   'expression_index', 100000, 10000, 2);
SELECT lab4.measure_insert_batch('mod_func_index',   'function_index',   100000, 10000, 2);

SELECT lab4.measure_insert_batch('mod_no_index',     'no_index',         100000, 10000, 3);
SELECT lab4.measure_insert_batch('mod_simple_index', 'simple_btree',     100000, 10000, 3);
SELECT lab4.measure_insert_batch('mod_unique_index', 'unique_btree',     100000, 10000, 3);
SELECT lab4.measure_insert_batch('mod_expr_index',   'expression_index', 100000, 10000, 3);
SELECT lab4.measure_insert_batch('mod_func_index',   'function_index',   100000, 10000, 3);

\echo '=== Замеры UPDATE неиндексируемого поля amount ==='

SELECT lab4.measure_update_nonindexed('mod_no_index',     'no_index',         100000, 1);
SELECT lab4.measure_update_nonindexed('mod_simple_index', 'simple_btree',     100000, 1);
SELECT lab4.measure_update_nonindexed('mod_unique_index', 'unique_btree',     100000, 1);
SELECT lab4.measure_update_nonindexed('mod_expr_index',   'expression_index', 100000, 1);
SELECT lab4.measure_update_nonindexed('mod_func_index',   'function_index',   100000, 1);

SELECT lab4.measure_update_nonindexed('mod_no_index',     'no_index',         100000, 2);
SELECT lab4.measure_update_nonindexed('mod_simple_index', 'simple_btree',     100000, 2);
SELECT lab4.measure_update_nonindexed('mod_unique_index', 'unique_btree',     100000, 2);
SELECT lab4.measure_update_nonindexed('mod_expr_index',   'expression_index', 100000, 2);
SELECT lab4.measure_update_nonindexed('mod_func_index',   'function_index',   100000, 2);

SELECT lab4.measure_update_nonindexed('mod_no_index',     'no_index',         100000, 3);
SELECT lab4.measure_update_nonindexed('mod_simple_index', 'simple_btree',     100000, 3);
SELECT lab4.measure_update_nonindexed('mod_unique_index', 'unique_btree',     100000, 3);
SELECT lab4.measure_update_nonindexed('mod_expr_index',   'expression_index', 100000, 3);
SELECT lab4.measure_update_nonindexed('mod_func_index',   'function_index',   100000, 3);

\echo '=== Замеры UPDATE индексируемого поля / выражения ==='

SELECT lab4.measure_update_indexed('mod_no_index',     'no_index',         100000, 1);
SELECT lab4.measure_update_indexed('mod_simple_index', 'simple_btree',     100000, 1);
SELECT lab4.measure_update_indexed('mod_unique_index', 'unique_btree',     100000, 1);
SELECT lab4.measure_update_indexed('mod_expr_index',   'expression_index', 100000, 1);
SELECT lab4.measure_update_indexed('mod_func_index',   'function_index',   100000, 1);

SELECT lab4.measure_update_indexed('mod_no_index',     'no_index',         100000, 2);
SELECT lab4.measure_update_indexed('mod_simple_index', 'simple_btree',     100000, 2);
SELECT lab4.measure_update_indexed('mod_unique_index', 'unique_btree',     100000, 2);
SELECT lab4.measure_update_indexed('mod_expr_index',   'expression_index', 100000, 2);
SELECT lab4.measure_update_indexed('mod_func_index',   'function_index',   100000, 2);

SELECT lab4.measure_update_indexed('mod_no_index',     'no_index',         100000, 3);
SELECT lab4.measure_update_indexed('mod_simple_index', 'simple_btree',     100000, 3);
SELECT lab4.measure_update_indexed('mod_unique_index', 'unique_btree',     100000, 3);
SELECT lab4.measure_update_indexed('mod_expr_index',   'expression_index', 100000, 3);
SELECT lab4.measure_update_indexed('mod_func_index',   'function_index',   100000, 3);

\echo '=== Размеры таблиц после тестов ==='

SELECT
    relname AS table_name,
    pg_relation_size(('lab4.' || relname)::regclass) AS relation_bytes,
    pg_indexes_size(('lab4.' || relname)::regclass) AS indexes_bytes,
    pg_total_relation_size(('lab4.' || relname)::regclass) AS total_bytes,
    pg_size_pretty(pg_relation_size(('lab4.' || relname)::regclass)) AS relation_size,
    pg_size_pretty(pg_indexes_size(('lab4.' || relname)::regclass)) AS indexes_size,
    pg_size_pretty(pg_total_relation_size(('lab4.' || relname)::regclass)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab4'
  AND relname IN (
      'mod_no_index',
      'mod_simple_index',
      'mod_unique_index',
      'mod_expr_index',
      'mod_func_index'
  )
ORDER BY relname;

\echo '=== Итоговая таблица INSERT / UPDATE ==='

SELECT
    operation_name,
    index_type,
    count(*) AS runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
FROM lab4.insert_update_measurements
GROUP BY operation_name, index_type
ORDER BY
    CASE operation_name
        WHEN 'insert_batch' THEN 1
        WHEN 'update_nonindexed_amount' THEN 2
        WHEN 'update_indexed_field' THEN 3
        ELSE 4
    END,
    CASE index_type
        WHEN 'no_index' THEN 1
        WHEN 'simple_btree' THEN 2
        WHEN 'unique_btree' THEN 3
        WHEN 'expression_index' THEN 4
        WHEN 'function_index' THEN 5
        ELSE 6
    END;

\echo '=== Проверка количества строк в тестовых таблицах ==='

SELECT 'mod_no_index' AS table_name, count(*) AS rows_count FROM lab4.mod_no_index
UNION ALL
SELECT 'mod_simple_index', count(*) FROM lab4.mod_simple_index
UNION ALL
SELECT 'mod_unique_index', count(*) FROM lab4.mod_unique_index
UNION ALL
SELECT 'mod_expr_index', count(*) FROM lab4.mod_expr_index
UNION ALL
SELECT 'mod_func_index', count(*) FROM lab4.mod_func_index
ORDER BY table_name;
