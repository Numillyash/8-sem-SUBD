\pset pager off
\timing on

\echo '=== ЛР-4. Методическое дозакрытие: страницы, секции, серии SELECT/INSERT/UPDATE ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.method_page_growth_test CASCADE;
DROP TABLE IF EXISTS lab4.method_page_growth_measurements CASCADE;

CREATE TABLE lab4.method_page_growth_test (
    id bigint NOT NULL,
    payload text NOT NULL
);

CREATE TABLE lab4.method_page_growth_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at timestamp NOT NULL DEFAULT clock_timestamp(),
    rows_in_table bigint NOT NULL,
    relation_bytes bigint NOT NULL,
    relation_pages numeric(12, 2) NOT NULL,
    total_relation_bytes bigint NOT NULL,
    avg_relation_bytes_per_row numeric(12, 2)
);

\echo '=== Микротест роста размера таблицы по страницам PostgreSQL ==='

DO $$
DECLARE
    v_rows bigint;
    v_relation_bytes bigint;
    v_total_relation_bytes bigint;
BEGIN
    FOREACH v_rows IN ARRAY ARRAY[
        0::bigint,
        1::bigint,
        2::bigint,
        5::bigint,
        10::bigint,
        20::bigint,
        50::bigint,
        100::bigint,
        200::bigint,
        500::bigint,
        1000::bigint,
        2000::bigint,
        5000::bigint,
        10000::bigint
    ]
    LOOP
        TRUNCATE TABLE lab4.method_page_growth_test;

        IF v_rows > 0 THEN
            INSERT INTO lab4.method_page_growth_test (id, payload)
            SELECT
                g,
                md5(g::text || random()::text)
            FROM generate_series(1, v_rows) AS g;
        END IF;

        ANALYZE lab4.method_page_growth_test;

        SELECT pg_relation_size('lab4.method_page_growth_test'::regclass)
        INTO v_relation_bytes;

        SELECT pg_total_relation_size('lab4.method_page_growth_test'::regclass)
        INTO v_total_relation_bytes;

        INSERT INTO lab4.method_page_growth_measurements (
            rows_in_table,
            relation_bytes,
            relation_pages,
            total_relation_bytes,
            avg_relation_bytes_per_row
        )
        VALUES (
            v_rows,
            v_relation_bytes,
            round(v_relation_bytes::numeric / 8192, 2),
            v_total_relation_bytes,
            CASE
                WHEN v_rows = 0 THEN NULL
                ELSE round(v_relation_bytes::numeric / v_rows, 2)
            END
        );
    END LOOP;
END $$;

SELECT
    rows_in_table,
    relation_bytes,
    relation_pages,
    total_relation_bytes,
    avg_relation_bytes_per_row
FROM lab4.method_page_growth_measurements
ORDER BY rows_in_table;

DROP TABLE IF EXISTS lab4.method_partition_strict_measurements CASCADE;

CREATE TABLE lab4.method_partition_strict_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at timestamp NOT NULL DEFAULT clock_timestamp(),
    test_name text NOT NULL,
    table_name text NOT NULL,
    run_no integer NOT NULL,
    elapsed_ms numeric(12, 3) NOT NULL,
    result_value numeric
);

CREATE OR REPLACE FUNCTION lab4.measure_method_partition_strict(
    p_test_name text,
    p_table_name text,
    p_sql text,
    p_runs integer DEFAULT 10
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    t1 double precision;
    t2 double precision;
    v_result numeric;
BEGIN
    FOR i IN 1..p_runs LOOP
        t1 := extract(epoch from clock_timestamp()) * 1000;
        EXECUTE p_sql INTO v_result;
        t2 := extract(epoch from clock_timestamp()) * 1000;

        INSERT INTO lab4.method_partition_strict_measurements (
            test_name,
            table_name,
            run_no,
            elapsed_ms,
            result_value
        )
        VALUES (
            p_test_name,
            p_table_name,
            i,
            round((t2 - t1)::numeric, 3),
            v_result
        );
    END LOOP;
END;
$$;

\echo '=== EXPLAIN: первая секция, обычная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_plain
WHERE order_date >= date '2024-01-01'
  AND order_date <  date '2024-04-01';

\echo '=== EXPLAIN: первая секция, секционированная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_partitioned
WHERE order_date >= date '2024-01-01'
  AND order_date <  date '2024-04-01';

\echo '=== EXPLAIN: вторая секция, секционированная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_partitioned
WHERE order_date >= date '2024-04-01'
  AND order_date <  date '2024-07-01';

\echo '=== Замеры секционирования строго по методичке ==='

SELECT lab4.measure_method_partition_strict(
    'first_section',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-04-01''',
    10
);

SELECT lab4.measure_method_partition_strict(
    'first_section',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-04-01''',
    10
);

SELECT lab4.measure_method_partition_strict(
    'second_section',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-04-01'' AND order_date < date ''2024-07-01''',
    10
);

SELECT lab4.measure_method_partition_strict(
    'second_section',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-04-01'' AND order_date < date ''2024-07-01''',
    10
);

SELECT lab4.measure_method_partition_strict(
    'first_and_second_sections',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-07-01''',
    10
);

SELECT lab4.measure_method_partition_strict(
    'first_and_second_sections',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-07-01''',
    10
);

SELECT
    test_name,
    table_name,
    count(*) AS runs,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms,
    min(result_value) AS result_check_min,
    max(result_value) AS result_check_max
FROM lab4.method_partition_strict_measurements
GROUP BY test_name, table_name
ORDER BY
    CASE test_name
        WHEN 'first_section' THEN 1
        WHEN 'second_section' THEN 2
        WHEN 'first_and_second_sections' THEN 3
        ELSE 4
    END,
    table_name;

DROP TABLE IF EXISTS lab4.method_series_measurements CASCADE;

DROP TABLE IF EXISTS lab4.method_select_no_index CASCADE;
DROP TABLE IF EXISTS lab4.method_select_id_index CASCADE;

DROP TABLE IF EXISTS lab4.method_mod_no_index CASCADE;
DROP TABLE IF EXISTS lab4.method_mod_simple_index CASCADE;
DROP TABLE IF EXISTS lab4.method_mod_unique_index CASCADE;
DROP TABLE IF EXISTS lab4.method_mod_expr_index CASCADE;
DROP TABLE IF EXISTS lab4.method_mod_func_index CASCADE;

CREATE TABLE lab4.method_series_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at timestamp NOT NULL DEFAULT clock_timestamp(),
    operation_name text NOT NULL,
    table_name text NOT NULL,
    index_type text NOT NULL,
    rows_before bigint NOT NULL,
    run_no integer NOT NULL,
    target_id bigint,
    affected_rows bigint,
    elapsed_ms numeric(12, 3) NOT NULL
);

CREATE TABLE lab4.method_select_no_index (
    id bigint NOT NULL,
    payload text NOT NULL
);

CREATE TABLE lab4.method_select_id_index (
    id bigint NOT NULL,
    payload text NOT NULL
);

CREATE INDEX idx_method_select_id
ON lab4.method_select_id_index (id);

CREATE TABLE lab4.method_mod_no_index (
    id bigint NOT NULL,
    customer_id integer NOT NULL,
    code text NOT NULL,
    amount numeric(12, 2) NOT NULL,
    payload text NOT NULL
);

CREATE TABLE lab4.method_mod_simple_index (LIKE lab4.method_mod_no_index);
CREATE TABLE lab4.method_mod_unique_index (LIKE lab4.method_mod_no_index);
CREATE TABLE lab4.method_mod_expr_index   (LIKE lab4.method_mod_no_index);
CREATE TABLE lab4.method_mod_func_index   (LIKE lab4.method_mod_no_index);

CREATE INDEX idx_method_mod_simple_customer
ON lab4.method_mod_simple_index (customer_id);

CREATE UNIQUE INDEX idx_method_mod_unique_id
ON lab4.method_mod_unique_index (id);

CREATE INDEX idx_method_mod_expr_lower_code
ON lab4.method_mod_expr_index ((lower(code)));

CREATE INDEX idx_method_mod_func_payload_prefix
ON lab4.method_mod_func_index (lab4.payload_prefix(payload));

CREATE OR REPLACE FUNCTION lab4.fill_method_select_table(
    p_table_name text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('TRUNCATE TABLE lab4.%I', p_table_name);

    EXECUTE format(
        'INSERT INTO lab4.%I (id, payload)
         SELECT g, md5(g::text || random()::text)
         FROM generate_series(1, %s) AS g',
        p_table_name,
        p_rows
    );

    EXECUTE format('ANALYZE lab4.%I', p_table_name);
END;
$$;

CREATE OR REPLACE FUNCTION lab4.fill_method_mod_table(
    p_table_name text,
    p_rows bigint
)
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

CREATE OR REPLACE FUNCTION lab4.measure_method_select_series(
    p_table_name text,
    p_index_type text,
    p_rows bigint,
    p_runs integer DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    t1 double precision;
    t2 double precision;
    v_target bigint;
    v_payload text;
BEGIN
    PERFORM lab4.fill_method_select_table(p_table_name, p_rows);

    FOR i IN 1..p_runs LOOP
        v_target := floor(random() * p_rows)::bigint + 1;

        t1 := extract(epoch from clock_timestamp()) * 1000;

        EXECUTE format(
            'SELECT payload FROM lab4.%I WHERE id = $1',
            p_table_name
        )
        INTO v_payload
        USING v_target;

        t2 := extract(epoch from clock_timestamp()) * 1000;

        INSERT INTO lab4.method_series_measurements (
            operation_name,
            table_name,
            index_type,
            rows_before,
            run_no,
            target_id,
            affected_rows,
            elapsed_ms
        )
        VALUES (
            'select_one_random_row',
            p_table_name,
            p_index_type,
            p_rows,
            i,
            v_target,
            CASE WHEN v_payload IS NULL THEN 0 ELSE 1 END,
            round((t2 - t1)::numeric, 3)
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_method_insert_series(
    p_table_name text,
    p_index_type text,
    p_rows bigint,
    p_runs integer DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    t1 double precision;
    t2 double precision;
    v_new_id bigint;
BEGIN
    PERFORM lab4.fill_method_mod_table(p_table_name, p_rows);

    FOR i IN 1..p_runs LOOP
        v_new_id := p_rows + i;

        t1 := extract(epoch from clock_timestamp()) * 1000;

        EXECUTE format(
            'INSERT INTO lab4.%I (id, customer_id, code, amount, payload)
             VALUES ($1, $2, $3, $4, $5)',
            p_table_name
        )
        USING
            v_new_id,
            ((v_new_id % 50000)::integer + 1),
            'code_' || (v_new_id % 10000)::text,
            round(((v_new_id % 100000)::numeric / 100 + 10), 2),
            md5(v_new_id::text || random()::text);

        t2 := extract(epoch from clock_timestamp()) * 1000;

        INSERT INTO lab4.method_series_measurements (
            operation_name,
            table_name,
            index_type,
            rows_before,
            run_no,
            target_id,
            affected_rows,
            elapsed_ms
        )
        VALUES (
            'insert_one_random_row',
            p_table_name,
            p_index_type,
            p_rows,
            i,
            v_new_id,
            1,
            round((t2 - t1)::numeric, 3)
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_method_update_series(
    p_table_name text,
    p_index_type text,
    p_rows bigint,
    p_runs integer DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    t1 double precision;
    t2 double precision;
    v_target bigint;
    v_affected bigint;
BEGIN
    PERFORM lab4.fill_method_mod_table(p_table_name, p_rows);

    FOR i IN 1..p_runs LOOP
        v_target := ((i * 9973) % p_rows) + 1;

        t1 := extract(epoch from clock_timestamp()) * 1000;

        IF p_table_name = 'method_mod_simple_index' THEN
            EXECUTE 'UPDATE lab4.method_mod_simple_index
                     SET customer_id = customer_id + 1000000
                     WHERE id = $1'
            USING v_target;

        ELSIF p_table_name = 'method_mod_unique_index' THEN
            EXECUTE 'UPDATE lab4.method_mod_unique_index
                     SET id = id + 1000000000 + $2
                     WHERE id = $1'
            USING v_target, i;

        ELSIF p_table_name = 'method_mod_expr_index' THEN
            EXECUTE 'UPDATE lab4.method_mod_expr_index
                     SET code = code || ''_upd''
                     WHERE id = $1'
            USING v_target;

        ELSIF p_table_name = 'method_mod_func_index' THEN
            EXECUTE 'UPDATE lab4.method_mod_func_index
                     SET payload = md5(payload || random()::text)
                     WHERE id = $1'
            USING v_target;

        ELSE
            EXECUTE 'UPDATE lab4.method_mod_no_index
                     SET payload = md5(payload || random()::text)
                     WHERE id = $1'
            USING v_target;
        END IF;

        GET DIAGNOSTICS v_affected = ROW_COUNT;

        t2 := extract(epoch from clock_timestamp()) * 1000;

        INSERT INTO lab4.method_series_measurements (
            operation_name,
            table_name,
            index_type,
            rows_before,
            run_no,
            target_id,
            affected_rows,
            elapsed_ms
        )
        VALUES (
            'update_one_random_row',
            p_table_name,
            p_index_type,
            p_rows,
            i,
            v_target,
            v_affected,
            round((t2 - t1)::numeric, 3)
        );
    END LOOP;
END;
$$;

\echo '=== Серии SELECT/INSERT/UPDATE по размерам таблиц ==='

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
        RAISE NOTICE 'Running size %', v_rows;

        PERFORM lab4.measure_method_select_series('method_select_no_index', 'without_index', v_rows, 5);
        PERFORM lab4.measure_method_select_series('method_select_id_index', 'btree_id_index', v_rows, 5);

        PERFORM lab4.measure_method_insert_series('method_mod_no_index',     'no_index',         v_rows, 5);
        PERFORM lab4.measure_method_insert_series('method_mod_simple_index', 'simple_btree',     v_rows, 5);
        PERFORM lab4.measure_method_insert_series('method_mod_unique_index', 'unique_btree',     v_rows, 5);
        PERFORM lab4.measure_method_insert_series('method_mod_expr_index',   'expression_index', v_rows, 5);
        PERFORM lab4.measure_method_insert_series('method_mod_func_index',   'function_index',   v_rows, 5);

        PERFORM lab4.measure_method_update_series('method_mod_no_index',     'no_index',         v_rows, 5);
        PERFORM lab4.measure_method_update_series('method_mod_simple_index', 'simple_btree',     v_rows, 5);
        PERFORM lab4.measure_method_update_series('method_mod_unique_index', 'unique_btree',     v_rows, 5);
        PERFORM lab4.measure_method_update_series('method_mod_expr_index',   'expression_index', v_rows, 5);
        PERFORM lab4.measure_method_update_series('method_mod_func_index',   'function_index',   v_rows, 5);
    END LOOP;
END $$;

\echo '=== Итоговая таблица серии SELECT/INSERT/UPDATE ==='

SELECT
    operation_name,
    index_type,
    rows_before,
    count(*) AS runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
FROM lab4.method_series_measurements
GROUP BY operation_name, index_type, rows_before
ORDER BY
    CASE operation_name
        WHEN 'select_one_random_row' THEN 1
        WHEN 'insert_one_random_row' THEN 2
        WHEN 'update_one_random_row' THEN 3
        ELSE 4
    END,
    rows_before,
    CASE index_type
        WHEN 'without_index' THEN 1
        WHEN 'btree_id_index' THEN 2
        WHEN 'no_index' THEN 3
        WHEN 'simple_btree' THEN 4
        WHEN 'unique_btree' THEN 5
        WHEN 'expression_index' THEN 6
        WHEN 'function_index' THEN 7
        ELSE 8
    END;

\echo '=== Размеры финальных методических таблиц ==='

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
      'method_select_no_index',
      'method_select_id_index',
      'method_mod_no_index',
      'method_mod_simple_index',
      'method_mod_unique_index',
      'method_mod_expr_index',
      'method_mod_func_index',
      'method_page_growth_test'
  )
ORDER BY relname;
