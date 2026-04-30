\pset pager off
\timing on

\echo '=== ЛР-4. Блок 3: влияние индексов на производительность выборки ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.index_select_test CASCADE;
DROP TABLE IF EXISTS lab4.index_select_measurements CASCADE;

CREATE TABLE lab4.index_select_test (
    id          bigint NOT NULL,
    customer_id integer NOT NULL,
    order_date  date NOT NULL,
    amount      numeric(12, 2) NOT NULL,
    status      text NOT NULL,
    payload     text NOT NULL
);

CREATE TABLE lab4.index_select_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at    timestamp NOT NULL DEFAULT clock_timestamp(),
    test_name      text NOT NULL,
    index_state    text NOT NULL,
    run_no         integer NOT NULL,
    elapsed_ms     numeric(12, 3) NOT NULL,
    result_count   bigint NOT NULL,
    result_sum     numeric(20, 2)
);

INSERT INTO lab4.index_select_test (id, customer_id, order_date, amount, status, payload)
SELECT
    g AS id,
    (g % 50000)::integer + 1 AS customer_id,
    date '2024-01-01' + ((g - 1) % 366)::integer AS order_date,
    round(((g % 100000)::numeric / 100 + 10), 2) AS amount,
    CASE
        WHEN g % 10 = 0 THEN 'cancelled'
        WHEN g % 3 = 0 THEN 'paid'
        ELSE 'new'
    END AS status,
    md5(g::text || '_index_select')
FROM generate_series(1, 1000000) AS g;

ANALYZE lab4.index_select_test;

CREATE OR REPLACE FUNCTION lab4.measure_index_select(
    p_test_name text,
    p_index_state text,
    p_runs integer DEFAULT 10
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    t1 double precision;
    t2 double precision;
    v_count bigint;
    v_sum numeric(20, 2);
BEGIN
    FOR i IN 1..p_runs LOOP
        t1 := extract(epoch from clock_timestamp()) * 1000;

        SELECT count(*), sum(amount)
        INTO v_count, v_sum
        FROM lab4.index_select_test
        WHERE customer_id = 12345;

        t2 := extract(epoch from clock_timestamp()) * 1000;

        INSERT INTO lab4.index_select_measurements (
            test_name,
            index_state,
            run_no,
            elapsed_ms,
            result_count,
            result_sum
        )
        VALUES (
            p_test_name,
            p_index_state,
            i,
            round((t2 - t1)::numeric, 3),
            v_count,
            v_sum
        );
    END LOOP;
END;
$$;

\echo '=== Размер таблицы до создания индекса ==='

SELECT
    pg_size_pretty(pg_relation_size('lab4.index_select_test'::regclass)) AS relation_size,
    pg_size_pretty(pg_indexes_size('lab4.index_select_test'::regclass)) AS indexes_size,
    pg_size_pretty(pg_total_relation_size('lab4.index_select_test'::regclass)) AS total_size;

\echo '=== EXPLAIN без индекса ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(amount)
FROM lab4.index_select_test
WHERE customer_id = 12345;

\echo '=== Замеры SELECT без индекса ==='

SELECT lab4.measure_index_select(
    'select_by_customer_id',
    'without_index',
    10
);

\echo '=== Создание B-tree индекса по customer_id ==='

CREATE INDEX idx_index_select_customer_id
ON lab4.index_select_test (customer_id);

ANALYZE lab4.index_select_test;

\echo '=== Размер таблицы после создания индекса ==='

SELECT
    pg_size_pretty(pg_relation_size('lab4.index_select_test'::regclass)) AS relation_size,
    pg_size_pretty(pg_indexes_size('lab4.index_select_test'::regclass)) AS indexes_size,
    pg_size_pretty(pg_total_relation_size('lab4.index_select_test'::regclass)) AS total_size;

\echo '=== EXPLAIN с индексом ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(amount)
FROM lab4.index_select_test
WHERE customer_id = 12345;

\echo '=== Замеры SELECT с индексом ==='

SELECT lab4.measure_index_select(
    'select_by_customer_id',
    'btree_index_customer_id',
    10
);

\echo '=== Итоговая таблица по выборке с индексом и без индекса ==='

SELECT
    test_name,
    index_state,
    count(*) AS runs,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms,
    min(result_count) AS result_count_min,
    max(result_count) AS result_count_max,
    min(result_sum) AS result_sum_min,
    max(result_sum) AS result_sum_max
FROM lab4.index_select_measurements
GROUP BY test_name, index_state
ORDER BY index_state;

\echo '=== Проверка количества строк ==='

SELECT count(*) AS rows_count FROM lab4.index_select_test;
