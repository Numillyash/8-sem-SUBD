\pset pager off
\timing on

\echo '=== ЛР-4. Шаг 2: рост хранилища таблицы логгирования ==='

DROP SCHEMA IF EXISTS lab4 CASCADE;
CREATE SCHEMA lab4;
SET search_path TO lab4, public;

CREATE TABLE lab4.user_log_storage (
    log_id       bigint NOT NULL,
    user_name    text NOT NULL,
    event_type   text NOT NULL,
    object_id    bigint NOT NULL,
    created_at   timestamp NOT NULL,
    payload      text NOT NULL
);

CREATE TABLE lab4.storage_growth_measurements (
    measurement_id              bigserial PRIMARY KEY,
    measured_at                 timestamp NOT NULL DEFAULT clock_timestamp(),
    rows_target                 bigint NOT NULL,
    rows_actual                 bigint NOT NULL,
    database_bytes              bigint NOT NULL,
    relation_bytes              bigint NOT NULL,
    relation_pages              numeric(14, 2) NOT NULL,
    total_relation_bytes        bigint NOT NULL,
    indexes_bytes               bigint NOT NULL,
    toast_bytes                 bigint NOT NULL,
    relation_filepath           text NOT NULL,
    avg_relation_bytes_per_row  numeric(14, 2),
    avg_total_bytes_per_row     numeric(14, 2)
);

CREATE OR REPLACE FUNCTION lab4.fill_user_log_storage(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE lab4.user_log_storage;

    INSERT INTO lab4.user_log_storage
    (
        log_id,
        user_name,
        event_type,
        object_id,
        created_at,
        payload
    )
    SELECT
        g AS log_id,
        'user_' || lpad((g % 100)::text, 3, '0') AS user_name,
        CASE g % 4
            WHEN 0 THEN 'login'
            WHEN 1 THEN 'read'
            WHEN 2 THEN 'update'
            ELSE 'logout'
        END AS event_type,
        g % 10000 AS object_id,
        timestamp '2024-01-01 00:00:00' + make_interval(secs => g::integer % 1000000) AS created_at,
        'payload_' || md5(g::text) || repeat('x', 32) AS payload
    FROM generate_series(1, p_rows) AS g;

    ANALYZE lab4.user_log_storage;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_user_log_storage(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows_actual bigint;
BEGIN
    PERFORM lab4.fill_user_log_storage(p_rows);

    SELECT count(*)
    INTO v_rows_actual
    FROM lab4.user_log_storage;

    INSERT INTO lab4.storage_growth_measurements
    (
        rows_target,
        rows_actual,
        database_bytes,
        relation_bytes,
        relation_pages,
        total_relation_bytes,
        indexes_bytes,
        toast_bytes,
        relation_filepath,
        avg_relation_bytes_per_row,
        avg_total_bytes_per_row
    )
    SELECT
        p_rows,
        v_rows_actual,
        pg_database_size(current_database()),
        pg_relation_size('lab4.user_log_storage'::regclass),
        pg_relation_size('lab4.user_log_storage'::regclass)::numeric / current_setting('block_size')::numeric,
        pg_total_relation_size('lab4.user_log_storage'::regclass),
        pg_indexes_size('lab4.user_log_storage'::regclass),
        GREATEST(
            pg_total_relation_size('lab4.user_log_storage'::regclass)
            - pg_relation_size('lab4.user_log_storage'::regclass)
            - pg_indexes_size('lab4.user_log_storage'::regclass),
            0
        ),
        pg_relation_filepath('lab4.user_log_storage'::regclass),
        CASE
            WHEN v_rows_actual = 0 THEN NULL
            ELSE round(pg_relation_size('lab4.user_log_storage'::regclass)::numeric / v_rows_actual, 2)
        END,
        CASE
            WHEN v_rows_actual = 0 THEN NULL
            ELSE round(pg_total_relation_size('lab4.user_log_storage'::regclass)::numeric / v_rows_actual, 2)
        END;
END;
$$;

\echo '=== 2.1. Замеры роста таблицы ==='

SELECT lab4.measure_user_log_storage(0);
SELECT lab4.measure_user_log_storage(1);
SELECT lab4.measure_user_log_storage(2);
SELECT lab4.measure_user_log_storage(5);
SELECT lab4.measure_user_log_storage(10);
SELECT lab4.measure_user_log_storage(20);
SELECT lab4.measure_user_log_storage(50);
SELECT lab4.measure_user_log_storage(100);
SELECT lab4.measure_user_log_storage(200);
SELECT lab4.measure_user_log_storage(500);
SELECT lab4.measure_user_log_storage(1000);
SELECT lab4.measure_user_log_storage(2000);
SELECT lab4.measure_user_log_storage(5000);
SELECT lab4.measure_user_log_storage(10000);
SELECT lab4.measure_user_log_storage(50000);
SELECT lab4.measure_user_log_storage(100000);
SELECT lab4.measure_user_log_storage(500000);
SELECT lab4.measure_user_log_storage(1000000);

\echo '=== 2.2. Итоговая таблица роста ==='

SELECT
    rows_actual,
    database_bytes,
    pg_size_pretty(database_bytes) AS database_size,
    relation_bytes,
    pg_size_pretty(relation_bytes) AS relation_size,
    relation_pages,
    total_relation_bytes,
    pg_size_pretty(total_relation_bytes) AS total_relation_size,
    indexes_bytes,
    toast_bytes,
    relation_filepath,
    avg_relation_bytes_per_row,
    avg_total_bytes_per_row
FROM lab4.storage_growth_measurements
ORDER BY rows_actual;

\echo '=== 2.3. Проверка, что relation растет страницами по 8192 байта ==='

SELECT
    rows_actual,
    relation_bytes,
    relation_pages,
    CASE
        WHEN relation_bytes % current_setting('block_size')::integer = 0
        THEN 'OK: multiple of block_size'
        ELSE 'FAIL'
    END AS page_check
FROM lab4.storage_growth_measurements
ORDER BY rows_actual;

\echo '=== 2.4. Прирост размера между соседними замерами ==='

SELECT
    rows_actual,
    relation_bytes,
    relation_bytes - lag(relation_bytes) OVER (ORDER BY rows_actual) AS relation_delta_bytes,
    rows_actual - lag(rows_actual) OVER (ORDER BY rows_actual) AS rows_delta,
    CASE
        WHEN rows_actual - lag(rows_actual) OVER (ORDER BY rows_actual) > 0
        THEN round(
            (relation_bytes - lag(relation_bytes) OVER (ORDER BY rows_actual))::numeric
            / (rows_actual - lag(rows_actual) OVER (ORDER BY rows_actual)),
            2
        )
        ELSE NULL
    END AS delta_bytes_per_row
FROM lab4.storage_growth_measurements
ORDER BY rows_actual;

\echo '=== 2.5. Оценка стабильного размера одной записи по крупным таблицам ==='

WITH large_points AS (
    SELECT *
    FROM lab4.storage_growth_measurements
    WHERE rows_actual IN (100000, 1000000)
),
calc AS (
    SELECT
        max(relation_bytes) - min(relation_bytes) AS bytes_delta,
        max(rows_actual) - min(rows_actual) AS rows_delta
    FROM large_points
)
SELECT
    bytes_delta,
    rows_delta,
    round(bytes_delta::numeric / rows_delta, 2) AS stable_relation_bytes_per_row
FROM calc;

\echo '=== 2.6. Проверка прогноза размера relation для разных N ==='

WITH base AS (
    SELECT
        rows_actual AS base_rows,
        relation_bytes AS base_relation_bytes
    FROM lab4.storage_growth_measurements
    WHERE rows_actual = 100000
),
coef AS (
    SELECT
        (m2.relation_bytes - m1.relation_bytes)::numeric
        / (m2.rows_actual - m1.rows_actual)::numeric AS bytes_per_row
    FROM lab4.storage_growth_measurements m1
    JOIN lab4.storage_growth_measurements m2 ON true
    WHERE m1.rows_actual = 100000
      AND m2.rows_actual = 1000000
),
prediction AS (
    SELECT
        m.rows_actual,
        m.relation_bytes AS actual_relation_bytes,
        round(
            b.base_relation_bytes
            + (m.rows_actual - b.base_rows) * c.bytes_per_row,
            0
        ) AS predicted_relation_bytes
    FROM lab4.storage_growth_measurements m
    CROSS JOIN base b
    CROSS JOIN coef c
    WHERE m.rows_actual IN (200000, 500000, 1000000)
       OR m.rows_actual IN (500000, 1000000)
)
SELECT
    rows_actual,
    actual_relation_bytes,
    predicted_relation_bytes,
    actual_relation_bytes - predicted_relation_bytes AS prediction_error_bytes,
    CASE
        WHEN actual_relation_bytes = 0 THEN NULL
        ELSE round(
            abs(actual_relation_bytes - predicted_relation_bytes)
            / actual_relation_bytes::numeric * 100,
            3
        )
    END AS prediction_error_percent
FROM prediction
ORDER BY rows_actual;

\echo '=== 2.7. Контроль финального количества строк ==='

SELECT
    count(*) AS rows_now
FROM lab4.user_log_storage;

\echo '=== Шаг 2 SQL завершен ==='
