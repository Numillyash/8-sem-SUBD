\pset pager off
\timing on

\echo '=== ЛР-4. Дополнительный блок: чистая стоимость UPDATE индексируемых полей ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.clean_update_measurements CASCADE;

DROP TABLE IF EXISTS lab4.clean_no_index CASCADE;
DROP TABLE IF EXISTS lab4.clean_customer_index CASCADE;
DROP TABLE IF EXISTS lab4.clean_code_index CASCADE;
DROP TABLE IF EXISTS lab4.clean_payload_func_index CASCADE;

CREATE TABLE lab4.clean_update_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at    timestamp NOT NULL DEFAULT clock_timestamp(),
    test_name      text NOT NULL,
    table_name     text NOT NULL,
    index_type     text NOT NULL,
    run_no         integer NOT NULL,
    affected_rows  bigint NOT NULL,
    elapsed_ms     numeric(12, 3) NOT NULL
);

CREATE TABLE lab4.clean_no_index (
    id          bigint NOT NULL,
    customer_id integer NOT NULL,
    code        text NOT NULL,
    amount      numeric(12, 2) NOT NULL,
    payload     text NOT NULL
);

CREATE TABLE lab4.clean_customer_index (LIKE lab4.clean_no_index);
CREATE TABLE lab4.clean_code_index (LIKE lab4.clean_no_index);
CREATE TABLE lab4.clean_payload_func_index (LIKE lab4.clean_no_index);

CREATE INDEX idx_clean_customer_id
ON lab4.clean_customer_index (customer_id);

CREATE INDEX idx_clean_lower_code
ON lab4.clean_code_index ((lower(code)));

CREATE INDEX idx_clean_payload_prefix
ON lab4.clean_payload_func_index (lab4.payload_prefix(payload));

CREATE OR REPLACE FUNCTION lab4.fill_clean_update_table(p_table_name text, p_rows bigint)
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

CREATE OR REPLACE FUNCTION lab4.measure_clean_update(
    p_table_name text,
    p_index_type text,
    p_test_name text,
    p_update_sql text,
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
    PERFORM lab4.fill_clean_update_table(p_table_name, 100000);

    t1 := extract(epoch from clock_timestamp()) * 1000;

    EXECUTE p_update_sql;

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    t2 := extract(epoch from clock_timestamp()) * 1000;

    INSERT INTO lab4.clean_update_measurements (
        test_name,
        table_name,
        index_type,
        run_no,
        affected_rows,
        elapsed_ms
    )
    VALUES (
        p_test_name,
        p_table_name,
        p_index_type,
        p_run_no,
        v_affected,
        round((t2 - t1)::numeric, 3)
    );
END;
$$;

\echo '=== Тест 1: UPDATE неиндексируемого поля amount, одинаковый диапазон по id ==='

SELECT lab4.measure_clean_update(
    'clean_no_index',
    'no_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_no_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_customer_index',
    'customer_btree',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_customer_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_code_index',
    'expression_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_code_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_payload_func_index',
    'function_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_payload_func_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_no_index',
    'no_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_no_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_customer_index',
    'customer_btree',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_customer_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_code_index',
    'expression_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_code_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_payload_func_index',
    'function_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_payload_func_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_no_index',
    'no_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_no_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    3
);

SELECT lab4.measure_clean_update(
    'clean_customer_index',
    'customer_btree',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_customer_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    3
);

SELECT lab4.measure_clean_update(
    'clean_code_index',
    'expression_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_code_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    3
);

SELECT lab4.measure_clean_update(
    'clean_payload_func_index',
    'function_index',
    'update_nonindexed_amount_by_id',
    'UPDATE lab4.clean_payload_func_index SET amount = amount + 1 WHERE id BETWEEN 10000 AND 20000',
    3
);

\echo '=== Тест 2: UPDATE индексируемых полей, одинаковый диапазон по id ==='

SELECT lab4.measure_clean_update(
    'clean_no_index',
    'no_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_no_index SET payload = md5(payload || random()::text) WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_customer_index',
    'customer_btree',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_customer_index SET customer_id = customer_id + 1000000 WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_code_index',
    'expression_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_code_index SET code = code || ''_upd'' WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_payload_func_index',
    'function_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_payload_func_index SET payload = md5(payload || random()::text) WHERE id BETWEEN 10000 AND 20000',
    1
);

SELECT lab4.measure_clean_update(
    'clean_no_index',
    'no_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_no_index SET payload = md5(payload || random()::text) WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_customer_index',
    'customer_btree',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_customer_index SET customer_id = customer_id + 1000000 WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_code_index',
    'expression_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_code_index SET code = code || ''_upd'' WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_payload_func_index',
    'function_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_payload_func_index SET payload = md5(payload || random()::text) WHERE id BETWEEN 10000 AND 20000',
    2
);

SELECT lab4.measure_clean_update(
    'clean_no_index',
    'no_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_no_index SET payload = md5(payload || random()::text) WHERE id BETWEEN 10000 AND 20000',
    3
);

SELECT lab4.measure_clean_update(
    'clean_customer_index',
    'customer_btree',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_customer_index SET customer_id = customer_id + 1000000 WHERE id BETWEEN 10000 AND 20000',
    3
);

SELECT lab4.measure_clean_update(
    'clean_code_index',
    'expression_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_code_index SET code = code || ''_upd'' WHERE id BETWEEN 10000 AND 20000',
    3
);

SELECT lab4.measure_clean_update(
    'clean_payload_func_index',
    'function_index',
    'update_changed_field_by_id',
    'UPDATE lab4.clean_payload_func_index SET payload = md5(payload || random()::text) WHERE id BETWEEN 10000 AND 20000',
    3
);

\echo '=== Размеры таблиц после чистого теста UPDATE ==='

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
      'clean_no_index',
      'clean_customer_index',
      'clean_code_index',
      'clean_payload_func_index'
  )
ORDER BY relname;

\echo '=== Итоговая таблица чистого теста UPDATE ==='

SELECT
    test_name,
    index_type,
    count(*) AS runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
FROM lab4.clean_update_measurements
GROUP BY test_name, index_type
ORDER BY
    CASE test_name
        WHEN 'update_nonindexed_amount_by_id' THEN 1
        WHEN 'update_changed_field_by_id' THEN 2
        ELSE 3
    END,
    CASE index_type
        WHEN 'no_index' THEN 1
        WHEN 'customer_btree' THEN 2
        WHEN 'expression_index' THEN 3
        WHEN 'function_index' THEN 4
        ELSE 5
    END;
