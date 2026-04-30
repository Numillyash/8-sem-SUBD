\pset pager off
\timing on

\echo '=== ЛР-4. Блок 2: секционирование данных ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.partition_measurements CASCADE;
DROP TABLE IF EXISTS lab4.orders_plain CASCADE;
DROP TABLE IF EXISTS lab4.orders_partitioned CASCADE;

CREATE TABLE lab4.orders_plain (
    order_id     bigint NOT NULL,
    customer_id  integer NOT NULL,
    order_date   date NOT NULL,
    amount       numeric(12, 2) NOT NULL,
    status       text NOT NULL,
    payload      text NOT NULL
);

CREATE TABLE lab4.orders_partitioned (
    order_id     bigint NOT NULL,
    customer_id  integer NOT NULL,
    order_date   date NOT NULL,
    amount       numeric(12, 2) NOT NULL,
    status       text NOT NULL,
    payload      text NOT NULL
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
    run_no         integer NOT NULL,
    elapsed_ms     numeric(12, 3) NOT NULL,
    result_value   numeric
);

\echo '=== Заполнение обычной таблицы 1 000 000 строк ==='

INSERT INTO lab4.orders_plain (order_id, customer_id, order_date, amount, status, payload)
SELECT
    g AS order_id,
    (g % 50000)::integer + 1 AS customer_id,
    date '2024-01-01' + ((g - 1) % 366)::integer AS order_date,
    round(((g % 100000)::numeric / 100 + 10), 2) AS amount,
    CASE
        WHEN g % 10 = 0 THEN 'cancelled'
        WHEN g % 3 = 0 THEN 'paid'
        ELSE 'new'
    END AS status,
    md5(g::text || '_payload') AS payload
FROM generate_series(1, 1000000) AS g;

\echo '=== Заполнение секционированной таблицы теми же данными ==='

INSERT INTO lab4.orders_partitioned (order_id, customer_id, order_date, amount, status, payload)
SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    status,
    payload
FROM lab4.orders_plain;

ANALYZE lab4.orders_plain;
ANALYZE lab4.orders_partitioned;

\echo '=== Размеры обычной и секционированной таблиц ==='

SELECT
    'orders_plain' AS object_name,
    pg_size_pretty(pg_relation_size('lab4.orders_plain'::regclass)) AS relation_size,
    pg_size_pretty(pg_total_relation_size('lab4.orders_plain'::regclass)) AS total_size
UNION ALL
SELECT
    'orders_partitioned',
    pg_size_pretty(pg_relation_size('lab4.orders_partitioned'::regclass)),
    pg_size_pretty(pg_total_relation_size('lab4.orders_partitioned'::regclass));

\echo '=== Размеры секций ==='

SELECT
    c.relname AS partition_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_size_pretty(pg_relation_size(c.oid)) AS relation_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab4'
  AND c.relname LIKE 'orders_partitioned_2024_q%'
ORDER BY c.relname;

CREATE OR REPLACE FUNCTION lab4.measure_query(
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

        INSERT INTO lab4.partition_measurements (
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

\echo '=== EXPLAIN для запроса по одной секции: обычная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_plain
WHERE order_date >= date '2024-02-01'
  AND order_date <  date '2024-03-01';

\echo '=== EXPLAIN для запроса по одной секции: секционированная таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(amount)
FROM lab4.orders_partitioned
WHERE order_date >= date '2024-02-01'
  AND order_date <  date '2024-03-01';

\echo '=== Замеры SELECT по одной секции ==='

SELECT lab4.measure_query(
    'one_partition_range',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-02-01'' AND order_date < date ''2024-03-01''',
    10
);

SELECT lab4.measure_query(
    'one_partition_range',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-02-01'' AND order_date < date ''2024-03-01''',
    10
);

\echo '=== Замеры SELECT по двум секциям ==='

SELECT lab4.measure_query(
    'two_partitions_range',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-03-01'' AND order_date < date ''2024-05-01''',
    10
);

SELECT lab4.measure_query(
    'two_partitions_range',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-03-01'' AND order_date < date ''2024-05-01''',
    10
);

\echo '=== Замеры SELECT по нескольким секциям ==='

SELECT lab4.measure_query(
    'three_partitions_range',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-02-01'' AND order_date < date ''2024-09-01''',
    10
);

SELECT lab4.measure_query(
    'three_partitions_range',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-02-01'' AND order_date < date ''2024-09-01''',
    10
);

\echo '=== Замеры SELECT по всей таблице ==='

SELECT lab4.measure_query(
    'full_table_range',
    'orders_plain',
    'SELECT sum(amount) FROM lab4.orders_plain WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2025-01-01''',
    10
);

SELECT lab4.measure_query(
    'full_table_range',
    'orders_partitioned',
    'SELECT sum(amount) FROM lab4.orders_partitioned WHERE order_date >= date ''2024-01-01'' AND order_date < date ''2025-01-01''',
    10
);

\echo '=== Итоговая таблица по секционированию ==='

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
        WHEN 'one_partition_range' THEN 1
        WHEN 'two_partitions_range' THEN 2
        WHEN 'three_partitions_range' THEN 3
        WHEN 'full_table_range' THEN 4
        ELSE 5
    END,
    table_name;

\echo '=== Проверка количества строк ==='

SELECT 'orders_plain' AS table_name, count(*) AS rows_count FROM lab4.orders_plain
UNION ALL
SELECT 'orders_partitioned', count(*) FROM lab4.orders_partitioned;
