\pset pager off
\timing on
\set ON_ERROR_STOP on

\echo '=== ЛР-4. Дополнительный тяжелый SELECT: 10-50 млн строк, не кластеризованные данные ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.heavy_select_measurements CASCADE;
DROP TABLE IF EXISTS lab4.heavy_select_no_index CASCADE;
DROP TABLE IF EXISTS lab4.heavy_select_btree CASCADE;

DROP FUNCTION IF EXISTS lab4.heavy_lookup_key(bigint, bigint) CASCADE;
DROP FUNCTION IF EXISTS lab4.fill_heavy_select_tables(bigint) CASCADE;
DROP FUNCTION IF EXISTS lab4.measure_heavy_select_table(text, text, bigint, integer, integer) CASCADE;

CREATE TABLE lab4.heavy_select_measurements (
    measurement_id         bigserial PRIMARY KEY,
    measured_at            timestamp NOT NULL DEFAULT clock_timestamp(),
    table_name             text NOT NULL,
    index_state            text NOT NULL,
    rows_before            bigint NOT NULL,
    run_no                 integer NOT NULL,
    probes_count           integer NOT NULL,
    total_elapsed_ms       numeric(16, 3) NOT NULL,
    total_elapsed_seconds  numeric(16, 3) NOT NULL,
    avg_elapsed_ms         numeric(16, 6) NOT NULL,
    found_rows             integer NOT NULL
);

CREATE TABLE lab4.heavy_select_no_index (
    id         bigint NOT NULL,
    lookup_key bigint NOT NULL,
    payload    text NOT NULL
);

CREATE TABLE lab4.heavy_select_btree (
    id         bigint NOT NULL,
    lookup_key bigint NOT NULL,
    payload    text NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.heavy_lookup_key(
    p_id bigint,
    p_rows bigint
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ((p_id * 2654435761::bigint) % p_rows) + 1;
$$;

CREATE OR REPLACE FUNCTION lab4.fill_heavy_select_tables(
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP INDEX IF EXISTS lab4.idx_heavy_select_btree_lookup;

    TRUNCATE TABLE lab4.heavy_select_no_index;
    TRUNCATE TABLE lab4.heavy_select_btree;

    RAISE NOTICE 'Filling heavy_select_no_index with % rows', p_rows;

    INSERT INTO lab4.heavy_select_no_index (id, lookup_key, payload)
    SELECT
        g AS id,
        lab4.heavy_lookup_key(g, p_rows) AS lookup_key,
        md5(g::text || '_heavy_select') || md5((g * 17)::text) AS payload
    FROM generate_series(1::bigint, p_rows) AS g;

    RAISE NOTICE 'Copying data to heavy_select_btree';

    INSERT INTO lab4.heavy_select_btree (id, lookup_key, payload)
    SELECT id, lookup_key, payload
    FROM lab4.heavy_select_no_index;

    RAISE NOTICE 'Creating B-tree index for % rows', p_rows;

    CREATE INDEX idx_heavy_select_btree_lookup
    ON lab4.heavy_select_btree (lookup_key);

    ANALYZE lab4.heavy_select_no_index;
    ANALYZE lab4.heavy_select_btree;

    CHECKPOINT;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_heavy_select_table(
    p_table_name text,
    p_index_state text,
    p_rows bigint,
    p_runs integer,
    p_probes integer
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

        INSERT INTO lab4.heavy_select_measurements (
            table_name,
            index_state,
            rows_before,
            run_no,
            probes_count,
            total_elapsed_ms,
            total_elapsed_seconds,
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
            round(((t2 - t1)::numeric / 1000), 3),
            round(((t2 - t1)::numeric / p_probes), 6),
            v_found
        );
    END LOOP;
END;
$$;

\echo '=== Запуск тяжелых серий SELECT ==='

DO $$
DECLARE
    v_rows bigint;
    v_probes integer;
BEGIN
    FOR v_rows, v_probes IN
        SELECT *
        FROM (
            VALUES
                (10000000::bigint, 20::integer),
                (25000000::bigint, 10::integer),
                (50000000::bigint, 5::integer)
        ) AS s(rows_count, probes_count)
    LOOP
        RAISE NOTICE 'Running heavy SELECT size %, probes %', v_rows, v_probes;

        PERFORM lab4.fill_heavy_select_tables(v_rows);

        PERFORM lab4.measure_heavy_select_table(
            'heavy_select_no_index',
            'without_index_nonclustered',
            v_rows,
            3,
            v_probes
        );

        PERFORM lab4.measure_heavy_select_table(
            'heavy_select_btree',
            'btree_index_nonclustered',
            v_rows,
            3,
            v_probes
        );
    END LOOP;
END $$;

\echo '=== Итоговая таблица тяжелого SELECT ==='

SELECT
    index_state,
    rows_before,
    count(*) AS runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    min(found_rows) AS found_rows_min,
    max(found_rows) AS found_rows_max,
    round(avg(total_elapsed_ms), 3) AS avg_total_elapsed_ms,
    round(avg(total_elapsed_seconds), 3) AS avg_total_elapsed_seconds,
    round(min(total_elapsed_seconds), 3) AS min_total_elapsed_seconds,
    round(max(total_elapsed_seconds), 3) AS max_total_elapsed_seconds,
    round(avg(avg_elapsed_ms), 6) AS avg_elapsed_ms_per_select
FROM lab4.heavy_select_measurements
GROUP BY index_state, rows_before
ORDER BY
    rows_before,
    CASE index_state
        WHEN 'without_index_nonclustered' THEN 1
        WHEN 'btree_index_nonclustered' THEN 2
        ELSE 3
    END;

\echo '=== Проверка секундной задержки для простой выборки без индекса ==='

SELECT
    rows_before,
    count(*) AS runs,
    min(probes_count) AS probes_min,
    max(probes_count) AS probes_max,
    round(avg(total_elapsed_seconds), 3) AS avg_total_elapsed_seconds,
    CASE
        WHEN avg(total_elapsed_seconds) >= 1
        THEN 'OK: average series time is at least 1 second'
        ELSE 'FAIL: average series time is less than 1 second'
    END AS check_result
FROM lab4.heavy_select_measurements
WHERE index_state = 'without_index_nonclustered'
GROUP BY rows_before
ORDER BY rows_before;

\echo '=== Размеры тяжелых таблиц после финального размера ==='

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
  AND c.relname IN ('heavy_select_no_index', 'heavy_select_btree')
ORDER BY c.relname;

\echo '=== EXPLAIN: тяжелая выборка без индекса ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT payload
FROM lab4.heavy_select_no_index
WHERE lookup_key = 7777777;

\echo '=== EXPLAIN: тяжелая выборка с B-tree индексом ==='

EXPLAIN (ANALYZE, BUFFERS)
SELECT payload
FROM lab4.heavy_select_btree
WHERE lookup_key = 7777777;

\echo '=== Тяжелый SELECT завершен ==='
