\pset pager off
\timing on
\set ON_ERROR_STOP on

\echo '=== ЛР-4. Шаг 4: влияние B-tree индекса на SELECT ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.select_measurements CASCADE;
DROP TABLE IF EXISTS lab4.select_no_index CASCADE;
DROP TABLE IF EXISTS lab4.select_btree_index CASCADE;

CREATE TABLE lab4.select_no_index (
    id         bigint NOT NULL,
    lookup_key bigint NOT NULL,
    payload    text NOT NULL
);

CREATE TABLE lab4.select_btree_index (
    id         bigint NOT NULL,
    lookup_key bigint NOT NULL,
    payload    text NOT NULL
);

CREATE INDEX idx_select_btree_lookup_key
ON lab4.select_btree_index (lookup_key);

CREATE TABLE lab4.select_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at    timestamp NOT NULL DEFAULT clock_timestamp(),
    table_name     text NOT NULL,
    index_state    text NOT NULL,
    rows_before    bigint NOT NULL,
    run_no         integer NOT NULL,
    probes_count   integer NOT NULL,
    total_elapsed_ms numeric(14, 3) NOT NULL,
    avg_elapsed_ms   numeric(14, 6) NOT NULL,
    found_rows     integer NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.fill_select_table(
    p_table_name text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('TRUNCATE TABLE lab4.%I', p_table_name);

    EXECUTE format(
        'INSERT INTO lab4.%I (id, lookup_key, payload)
         SELECT
             g,
             g,
             md5(g::text || ''_select_test'')
         FROM generate_series(1, %s) AS g',
        p_table_name,
        p_rows
    );

    EXECUTE format('ANALYZE lab4.%I', p_table_name);
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_select_table(
    p_table_name text,
    p_index_state text,
    p_rows bigint,
    p_runs integer DEFAULT 5,
    p_probes integer DEFAULT 20
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run integer;
    v_probe integer;
    v_target bigint;
    v_payload text;
    v_found integer;
    t1 double precision;
    t2 double precision;
BEGIN
    PERFORM lab4.fill_select_table(p_table_name, p_rows);

    FOR v_run IN 1..p_runs LOOP
        v_found := 0;
        t1 := extract(epoch FROM clock_timestamp()) * 1000;

        FOR v_probe IN 1..p_probes LOOP
            v_target := (((v_probe::bigint * 104729) + (v_run::bigint * 8191)) % p_rows) + 1;

            EXECUTE format(
                'SELECT payload FROM lab4.%I WHERE lookup_key = $1',
                p_table_name
            )
            INTO v_payload
            USING v_target;

            IF v_payload IS NOT NULL THEN
                v_found := v_found + 1;
            END IF;
        END LOOP;

        t2 := extract(epoch FROM clock_timestamp()) * 1000;

        INSERT INTO lab4.select_measurements (
            table_name,
            index_state,
            rows_before,
            run_no,
            probes_count,
            total_elapsed_ms,
            avg_elapsed_ms,
            found_rows
        )
        VALUES (
            p_table_name,
            p_index_state,
            p_rows,
            v_run,
            p_probes,
            round((t2 - t1)::numeric, 3),
            round(((t2 - t1)::numeric / p_probes), 6),
            v_found
        );
    END LOOP;
END;
$$;

\echo '=== 4.1. Запуск серий SELECT по размерам таблицы ==='

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
        RAISE NOTICE 'Running SELECT size %', v_rows;

        PERFORM lab4.measure_select_table('select_no_index',    'without_index', v_rows, 5, 200);
        PERFORM lab4.measure_select_table('select_btree_index', 'btree_index',   v_rows, 5, 200);
    END LOOP;
END $$;

\echo '=== 4.2. EXPLAIN без индекса, 1 000 000 строк ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT payload
FROM lab4.select_no_index
WHERE lookup_key = 777777;

\echo '=== 4.3. EXPLAIN с B-tree индексом, 1 000 000 строк ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT payload
FROM lab4.select_btree_index
WHERE lookup_key = 777777;

\echo '=== 4.4. Итоговая таблица SELECT ==='

SELECT
    index_state,
    rows_before,
    count(*) AS runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    min(found_rows) AS found_rows_min,
    max(found_rows) AS found_rows_max,
    round(avg(avg_elapsed_ms), 6) AS avg_elapsed_ms,
    round(min(avg_elapsed_ms), 6) AS min_elapsed_ms,
    round(max(avg_elapsed_ms), 6) AS max_elapsed_ms,
    round(stddev_samp(avg_elapsed_ms), 6) AS stddev_elapsed_ms
FROM lab4.select_measurements
GROUP BY index_state, rows_before
ORDER BY
    rows_before,
    CASE index_state
        WHEN 'without_index' THEN 1
        WHEN 'btree_index' THEN 2
        ELSE 3
    END;

\echo '=== 4.5. Проверка корректности SELECT ==='

SELECT
    index_state,
    count(DISTINCT rows_before) AS tested_table_sizes,
    count(*) AS total_runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    min(found_rows) AS found_rows_min,
    max(found_rows) AS found_rows_max,
    CASE
        WHEN min(found_rows) = min(probes_count)
         AND max(found_rows) = max(probes_count)
        THEN 'OK: every SELECT probe found exactly one row'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.select_measurements
GROUP BY index_state
ORDER BY index_state;

\echo '=== 4.6. Размеры таблиц SELECT ==='

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
  AND c.relname IN ('select_no_index', 'select_btree_index')
ORDER BY c.relname;

\echo '=== Шаг 4 SQL завершен ==='
