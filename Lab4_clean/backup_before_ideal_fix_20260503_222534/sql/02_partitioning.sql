\pset pager off
\timing on
\set ON_ERROR_STOP on

\echo '=== ЛР-4. Шаг 3: секционирование данных ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.partition_measurements CASCADE;
DROP TABLE IF EXISTS lab4.orders_plain CASCADE;
DROP TABLE IF EXISTS lab4.orders_partitioned CASCADE;

CREATE TABLE lab4.orders_plain (
    order_id    bigint NOT NULL,
    customer_id integer NOT NULL,
    order_date  date NOT NULL,
    amount      numeric(12, 2) NOT NULL,
    status      text NOT NULL,
    payload     text NOT NULL
);

CREATE TABLE lab4.orders_partitioned (
    order_id    bigint NOT NULL,
    customer_id integer NOT NULL,
    order_date  date NOT NULL,
    amount      numeric(12, 2) NOT NULL,
    status      text NOT NULL,
    payload     text NOT NULL
) PARTITION BY RANGE (order_date);

CREATE TABLE lab4.orders_partitioned_2024_q1
PARTITION OF lab4.orders_partitioned
FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE lab4.orders_partitioned_2024_q2
PARTITION OF lab4.orders_partitioned
FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE lab4.orders_partitioned_2024_q3
PARTITION OF lab4.orders_partitioned
FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE lab4.orders_partitioned_2024_q4
PARTITION OF lab4.orders_partitioned
FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

CREATE TABLE lab4.partition_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at    timestamp NOT NULL DEFAULT clock_timestamp(),
    test_name      text NOT NULL,
    table_name     text NOT NULL,
    sql_text       text NOT NULL,
    run_no         integer NOT NULL,
    elapsed_ms     numeric(14, 3) NOT NULL,
    result_value   numeric NOT NULL
);

\echo '=== 3.1. Заполнение обычной таблицы 1 000 000 строк ==='

INSERT INTO lab4.orders_plain
(
    order_id,
    customer_id,
    order_date,
    amount,
    status,
    payload
)
SELECT
    g::bigint AS order_id,
    (((g::bigint * 7919) % 100000)::integer + 1) AS customer_id,
    date '2024-01-01' + ((g::bigint - 1) % 366)::integer AS order_date,
    round((((g::bigint * 37) % 100000)::numeric / 100 + 10), 2) AS amount,
    CASE
        WHEN g::bigint % 10 = 0 THEN 'cancelled'
        WHEN g::bigint % 3 = 0 THEN 'paid'
        ELSE 'new'
    END AS status,
    md5(g::text || '_partition_clean') AS payload
FROM generate_series(1, 1000000) AS g;

\echo '=== 3.2. Заполнение секционированной таблицы теми же данными ==='

INSERT INTO lab4.orders_partitioned
SELECT *
FROM lab4.orders_plain;

ANALYZE lab4.orders_plain;
ANALYZE lab4.orders_partitioned;

\echo '=== 3.3. Проверка количества строк ==='

SELECT 'orders_plain' AS table_name, count(*) AS rows_count
FROM lab4.orders_plain
UNION ALL
SELECT 'orders_partitioned' AS table_name, count(*) AS rows_count
FROM lab4.orders_partitioned
ORDER BY table_name;

\echo '=== 3.4. Проверка распределения строк по секциям ==='

SELECT
    'q1' AS section,
    count(*) AS rows_count
FROM lab4.orders_partitioned_2024_q1
UNION ALL
SELECT 'q2', count(*) FROM lab4.orders_partitioned_2024_q2
UNION ALL
SELECT 'q3', count(*) FROM lab4.orders_partitioned_2024_q3
UNION ALL
SELECT 'q4', count(*) FROM lab4.orders_partitioned_2024_q4
ORDER BY section;

\echo '=== 3.5. Размеры обычной таблицы, родителя и секций ==='

SELECT
    'orders_plain' AS object_name,
    pg_relation_size('lab4.orders_plain'::regclass) AS relation_bytes,
    pg_size_pretty(pg_relation_size('lab4.orders_plain'::regclass)) AS relation_size,
    pg_total_relation_size('lab4.orders_plain'::regclass) AS total_bytes,
    pg_size_pretty(pg_total_relation_size('lab4.orders_plain'::regclass)) AS total_size
UNION ALL
SELECT
    'orders_partitioned_parent' AS object_name,
    pg_relation_size('lab4.orders_partitioned'::regclass) AS relation_bytes,
    pg_size_pretty(pg_relation_size('lab4.orders_partitioned'::regclass)) AS relation_size,
    pg_total_relation_size('lab4.orders_partitioned'::regclass) AS total_bytes,
    pg_size_pretty(pg_total_relation_size('lab4.orders_partitioned'::regclass)) AS total_size
ORDER BY object_name;

SELECT
    c.relname AS partition_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_size_pretty(pg_relation_size(c.oid)) AS relation_size,
    pg_total_relation_size(c.oid) AS total_bytes,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab4'
  AND c.relname LIKE 'orders_partitioned_2024_q%'
ORDER BY c.relname;

CREATE OR REPLACE FUNCTION lab4.measure_partition_query(
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
        t1 := extract(epoch FROM clock_timestamp()) * 1000;
        EXECUTE p_sql INTO v_result;
        t2 := extract(epoch FROM clock_timestamp()) * 1000;

        INSERT INTO lab4.partition_measurements
        (
            test_name,
            table_name,
            sql_text,
            run_no,
            elapsed_ms,
            result_value
        )
        VALUES
        (
            p_test_name,
            p_table_name,
            p_sql,
            i,
            round((t2 - t1)::numeric, 3),
            COALESCE(v_result, 0)
        );
    END LOOP;
END;
$$;

\echo '=== 3.6. EXPLAIN: первая секция, обычная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_plain
WHERE order_date >= date '2024-01-01'
  AND order_date <  date '2024-04-01';

\echo '=== 3.7. EXPLAIN: первая секция, секционированная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_partitioned
WHERE order_date >= date '2024-01-01'
  AND order_date <  date '2024-04-01';

\echo '=== 3.8. EXPLAIN: вторая секция, секционированная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_partitioned
WHERE order_date >= date '2024-04-01'
  AND order_date <  date '2024-07-01';

\echo '=== 3.9. EXPLAIN: первая и вторая секции, секционированная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_partitioned
WHERE order_date >= date '2024-01-01'
  AND order_date <  date '2024-07-01';

\echo '=== 3.10. Замеры: первая секция ==='

SELECT lab4.measure_partition_query(
    'first_section',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-04-01''',
    10
);

SELECT lab4.measure_partition_query(
    'first_section',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-04-01''',
    10
);

\echo '=== 3.11. Замеры: вторая секция ==='

SELECT lab4.measure_partition_query(
    'second_section',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-04-01'' AND order_date < date ''2024-07-01''',
    10
);

SELECT lab4.measure_partition_query(
    'second_section',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-04-01'' AND order_date < date ''2024-07-01''',
    10
);

\echo '=== 3.12. Замеры: первая и вторая секции ==='

SELECT lab4.measure_partition_query(
    'first_and_second_sections',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-07-01''',
    10
);

SELECT lab4.measure_partition_query(
    'first_and_second_sections',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2024-07-01''',
    10
);

\echo '=== 3.13. Итоговая таблица секционирования ==='

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
FROM lab4.partition_measurements
GROUP BY test_name, table_name
ORDER BY
    CASE test_name
        WHEN 'first_section' THEN 1
        WHEN 'second_section' THEN 2
        WHEN 'first_and_second_sections' THEN 3
        ELSE 4
    END,
    table_name;

\echo '=== 3.14. Проверка равенства результатов plain и partitioned ==='

WITH grouped AS (
    SELECT
        test_name,
        table_name,
        min(result_value) AS result_value
    FROM lab4.partition_measurements
    GROUP BY test_name, table_name
),
pairs AS (
    SELECT
        p.test_name,
        p.result_value AS plain_result,
        q.result_value AS partitioned_result,
        p.result_value - q.result_value AS diff
    FROM grouped p
    JOIN grouped q ON q.test_name = p.test_name
    WHERE p.table_name = 'orders_plain'
      AND q.table_name = 'orders_partitioned'
)
SELECT
    test_name,
    plain_result,
    partitioned_result,
    diff,
    CASE
        WHEN diff = 0 THEN 'OK'
        ELSE 'FAIL'
    END AS result_check
FROM pairs
ORDER BY
    CASE test_name
        WHEN 'first_section' THEN 1
        WHEN 'second_section' THEN 2
        WHEN 'first_and_second_sections' THEN 3
        ELSE 4
    END;

\echo '=== Шаг 3 SQL завершен ==='
