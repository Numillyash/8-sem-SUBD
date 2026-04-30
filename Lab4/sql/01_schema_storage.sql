\pset pager off
\timing on

\echo '=== ЛР-4. Блок 1: схема, размеры БД и рост хранилища ==='

DROP SCHEMA IF EXISTS lab4 CASCADE;
CREATE SCHEMA lab4;
SET search_path TO lab4, public;

CREATE TABLE lab4.storage_plain (
    id          bigint NOT NULL,
    user_name   text NOT NULL,
    aux         integer NOT NULL,
    created_at  timestamp NOT NULL DEFAULT clock_timestamp(),
    payload     text NOT NULL
);

CREATE TABLE lab4.storage_measurements (
    measurement_id      bigserial PRIMARY KEY,
    measured_at         timestamp NOT NULL DEFAULT clock_timestamp(),
    rows_in_table       bigint NOT NULL,
    database_bytes      bigint NOT NULL,
    relation_bytes      bigint NOT NULL,
    total_relation_bytes bigint NOT NULL,
    indexes_bytes       bigint NOT NULL,
    toast_bytes         bigint NOT NULL,
    avg_relation_bytes_per_row numeric(12, 2),
    avg_total_bytes_per_row    numeric(12, 2)
);

CREATE OR REPLACE FUNCTION lab4.fill_storage_plain(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE lab4.storage_plain;

    INSERT INTO lab4.storage_plain (id, user_name, aux, created_at, payload)
    SELECT
        g,
        'user_' || g::text,
        (random() * 1000000000)::integer,
        clock_timestamp(),
        md5(g::text || random()::text)
    FROM generate_series(1, p_rows) AS g;

    ANALYZE lab4.storage_plain;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_storage_plain(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_database_bytes bigint;
    v_relation_bytes bigint;
    v_total_relation_bytes bigint;
    v_indexes_bytes bigint;
    v_toast_bytes bigint;
BEGIN
    PERFORM lab4.fill_storage_plain(p_rows);

    SELECT pg_database_size(current_database())
    INTO v_database_bytes;

    SELECT pg_relation_size('lab4.storage_plain'::regclass)
    INTO v_relation_bytes;

    SELECT pg_total_relation_size('lab4.storage_plain'::regclass)
    INTO v_total_relation_bytes;

    SELECT pg_indexes_size('lab4.storage_plain'::regclass)
    INTO v_indexes_bytes;

    SELECT pg_total_relation_size('lab4.storage_plain'::regclass)
           - pg_relation_size('lab4.storage_plain'::regclass)
           - pg_indexes_size('lab4.storage_plain'::regclass)
    INTO v_toast_bytes;

    INSERT INTO lab4.storage_measurements (
        rows_in_table,
        database_bytes,
        relation_bytes,
        total_relation_bytes,
        indexes_bytes,
        toast_bytes,
        avg_relation_bytes_per_row,
        avg_total_bytes_per_row
    )
    VALUES (
        p_rows,
        v_database_bytes,
        v_relation_bytes,
        v_total_relation_bytes,
        v_indexes_bytes,
        v_toast_bytes,
        round(v_relation_bytes::numeric / NULLIF(p_rows, 0), 2),
        round(v_total_relation_bytes::numeric / NULLIF(p_rows, 0), 2)
    );
END;
$$;

\echo '=== Версия PostgreSQL ==='
SELECT version();

\echo '=== Размеры всех баз данных ==='
SELECT
    datname AS database_name,
    pg_database_size(datname) AS size_bytes,
    pg_size_pretty(pg_database_size(datname)) AS size_pretty,
    datistemplate AS is_template
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

\echo '=== Таблицы текущей базы до заполнения ==='
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_total_relation_size(c.oid) AS total_bytes,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

\echo '=== Замеры роста хранилища ==='
SELECT lab4.measure_storage_plain(10);
SELECT lab4.measure_storage_plain(100);
SELECT lab4.measure_storage_plain(1000);
SELECT lab4.measure_storage_plain(10000);
SELECT lab4.measure_storage_plain(100000);
SELECT lab4.measure_storage_plain(1000000);

\echo '=== Итоговая таблица замеров ==='
SELECT
    rows_in_table,
    database_bytes,
    pg_size_pretty(database_bytes) AS database_size,
    relation_bytes,
    pg_size_pretty(relation_bytes) AS relation_size,
    total_relation_bytes,
    pg_size_pretty(total_relation_bytes) AS total_relation_size,
    indexes_bytes,
    toast_bytes,
    avg_relation_bytes_per_row,
    avg_total_bytes_per_row
FROM lab4.storage_measurements
ORDER BY rows_in_table;

\echo '=== Проверка фактического числа строк в последнем состоянии таблицы ==='
SELECT count(*) AS rows_now FROM lab4.storage_plain;
