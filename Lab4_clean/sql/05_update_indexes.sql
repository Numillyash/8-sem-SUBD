\pset pager off
\timing on
\set ON_ERROR_STOP on

\echo '=== ЛР-4. Шаг 6: влияние индексов на UPDATE ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.update_measurements CASCADE;
DROP TABLE IF EXISTS lab4.update_trigger_audit CASCADE;

DROP TABLE IF EXISTS lab4.update_no_extra_index CASCADE;
DROP TABLE IF EXISTS lab4.update_simple_btree CASCADE;
DROP TABLE IF EXISTS lab4.update_unique_btree CASCADE;
DROP TABLE IF EXISTS lab4.update_expression_index CASCADE;
DROP TABLE IF EXISTS lab4.update_function_index CASCADE;

DROP FUNCTION IF EXISTS lab4.update_function_key(text) CASCADE;
DROP FUNCTION IF EXISTS lab4.update_trigger_fn() CASCADE;
DROP FUNCTION IF EXISTS lab4.fill_update_table(text, bigint) CASCADE;
DROP FUNCTION IF EXISTS lab4.measure_update_table(text, text, bigint, bigint, integer) CASCADE;

CREATE TABLE lab4.update_measurements (
    measurement_id             bigserial PRIMARY KEY,
    measured_at                timestamp NOT NULL DEFAULT clock_timestamp(),
    table_name                 text NOT NULL,
    index_type                 text NOT NULL,
    rows_base                  bigint NOT NULL,
    batch_size                 bigint NOT NULL,
    run_no                     integer NOT NULL,
    update_marker              bigint NOT NULL,
    total_elapsed_ms           numeric(14, 3) NOT NULL,
    avg_elapsed_ms_per_row     numeric(14, 6) NOT NULL,
    affected_rows              bigint NOT NULL,
    trigger_rows               bigint NOT NULL
);

CREATE TABLE lab4.update_trigger_audit (
    audit_id       bigserial PRIMARY KEY,
    table_name     text NOT NULL,
    update_marker  bigint NOT NULL,
    changed_at     timestamp NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION lab4.update_function_key(p_payload text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT md5(p_payload || ':' || length(p_payload)::text || ':' || substring(p_payload from 1 for 16));
$$;

CREATE OR REPLACE FUNCTION lab4.update_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO lab4.update_trigger_audit (table_name, update_marker)
    VALUES (TG_TABLE_NAME, NEW.update_marker);

    RETURN NEW;
END;
$$;

CREATE TABLE lab4.update_no_extra_index (
    id            bigint NOT NULL,
    lookup_id     bigint NOT NULL,
    customer_id   integer NOT NULL,
    unique_key    bigint NOT NULL,
    code          text NOT NULL,
    amount        numeric(12, 2) NOT NULL,
    payload       text NOT NULL,
    update_marker bigint NOT NULL DEFAULT 0
);

CREATE TABLE lab4.update_simple_btree     (LIKE lab4.update_no_extra_index);
CREATE TABLE lab4.update_unique_btree     (LIKE lab4.update_no_extra_index);
CREATE TABLE lab4.update_expression_index (LIKE lab4.update_no_extra_index);
CREATE TABLE lab4.update_function_index   (LIKE lab4.update_no_extra_index);

\echo '=== 6.1. Технический lookup_id индекс создается у всех таблиц ==='

CREATE INDEX idx_update_no_extra_lookup
ON lab4.update_no_extra_index (lookup_id);

CREATE INDEX idx_update_simple_lookup
ON lab4.update_simple_btree (lookup_id);

CREATE INDEX idx_update_unique_lookup
ON lab4.update_unique_btree (lookup_id);

CREATE INDEX idx_update_expression_lookup
ON lab4.update_expression_index (lookup_id);

CREATE INDEX idx_update_function_lookup
ON lab4.update_function_index (lookup_id);

\echo '=== 6.2. Дополнительные исследуемые индексы ==='

CREATE INDEX idx_update_simple_customer
ON lab4.update_simple_btree (customer_id);

CREATE UNIQUE INDEX idx_update_unique_key
ON lab4.update_unique_btree (unique_key);

CREATE INDEX idx_update_expression_lower_code
ON lab4.update_expression_index ((lower(code)));

CREATE INDEX idx_update_function_payload
ON lab4.update_function_index (lab4.update_function_key(payload));

\echo '=== 6.3. AFTER UPDATE триггеры для контроля факта обновления ==='

CREATE TRIGGER trg_update_no_extra_index
AFTER UPDATE ON lab4.update_no_extra_index
FOR EACH ROW EXECUTE FUNCTION lab4.update_trigger_fn();

CREATE TRIGGER trg_update_simple_btree
AFTER UPDATE ON lab4.update_simple_btree
FOR EACH ROW EXECUTE FUNCTION lab4.update_trigger_fn();

CREATE TRIGGER trg_update_unique_btree
AFTER UPDATE ON lab4.update_unique_btree
FOR EACH ROW EXECUTE FUNCTION lab4.update_trigger_fn();

CREATE TRIGGER trg_update_expression_index
AFTER UPDATE ON lab4.update_expression_index
FOR EACH ROW EXECUTE FUNCTION lab4.update_trigger_fn();

CREATE TRIGGER trg_update_function_index
AFTER UPDATE ON lab4.update_function_index
FOR EACH ROW EXECUTE FUNCTION lab4.update_trigger_fn();

CREATE OR REPLACE FUNCTION lab4.fill_update_table(
    p_table_name text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('TRUNCATE TABLE lab4.%I', p_table_name);

    EXECUTE format(
        $fmt$
        INSERT INTO lab4.%I
        (
            id,
            lookup_id,
            customer_id,
            unique_key,
            code,
            amount,
            payload,
            update_marker
        )
        SELECT
            v_id,
            v_id AS lookup_id,
            (((v_id * 7919) %% 100000)::integer + 1) AS customer_id,
            v_id AS unique_key,
            'code_' || (v_id %% 50000)::text AS code,
            round((((v_id * 37) %% 100000)::numeric / 100 + 10), 2) AS amount,
            md5(v_id::text || '_update_base') || md5((v_id * 17)::text) AS payload,
            0 AS update_marker
        FROM generate_series(1::bigint, %s::bigint) AS v_id
        $fmt$,
        p_table_name,
        p_rows
    );

    EXECUTE format('ANALYZE lab4.%I', p_table_name);
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_table(
    p_table_name text,
    p_index_type text,
    p_rows_base bigint,
    p_batch_size bigint DEFAULT 1000,
    p_runs integer DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run integer;
    v_from bigint;
    v_to bigint;
    v_marker bigint;
    v_affected bigint;
    v_trigger_rows bigint;
    t1 double precision;
    t2 double precision;
BEGIN
    PERFORM lab4.fill_update_table(p_table_name, p_rows_base);

    FOR v_run IN 1..p_runs LOOP
        v_from := ((v_run - 1) * p_batch_size) + 1;
        v_to := v_run * p_batch_size;
        v_marker := p_rows_base * 1000 + v_run;

        DELETE FROM lab4.update_trigger_audit
        WHERE table_name = p_table_name
          AND update_marker = v_marker;

        t1 := extract(epoch FROM clock_timestamp()) * 1000;

        EXECUTE format(
            $fmt$
            UPDATE lab4.%I
            SET
                customer_id = (((customer_id::bigint + 13) %% 100000)::integer + 1),
                unique_key = id + (%s::bigint * 10000000::bigint),
                code = 'upd_' || id::text || '_' || %s::text,
                amount = amount + 1,
                payload = md5(id::text || ':' || %s::text) || md5((id * 17)::text || ':' || %s::text),
                update_marker = %s
            WHERE lookup_id BETWEEN %s AND %s
            $fmt$,
            p_table_name,
            v_marker,
            v_marker,
            v_marker,
            v_marker,
            v_marker,
            v_from,
            v_to
        );

        GET DIAGNOSTICS v_affected = ROW_COUNT;

        SELECT count(*)
        INTO v_trigger_rows
        FROM lab4.update_trigger_audit
        WHERE table_name = p_table_name
          AND update_marker = v_marker;

        t2 := extract(epoch FROM clock_timestamp()) * 1000;

        INSERT INTO lab4.update_measurements (
            table_name,
            index_type,
            rows_base,
            batch_size,
            run_no,
            update_marker,
            total_elapsed_ms,
            avg_elapsed_ms_per_row,
            affected_rows,
            trigger_rows
        )
        VALUES (
            p_table_name,
            p_index_type,
            p_rows_base,
            p_batch_size,
            v_run,
            v_marker,
            round((t2 - t1)::numeric, 3),
            round(((t2 - t1)::numeric / p_batch_size), 6),
            v_affected,
            v_trigger_rows
        );
    END LOOP;
END;
$$;

\echo '=== 6.4. Запуск серий UPDATE по размерам таблицы ==='

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
        RAISE NOTICE 'Running UPDATE size %', v_rows;

        PERFORM lab4.measure_update_table('update_no_extra_index',    'no_extra_index',  v_rows, 1000, 6);
        PERFORM lab4.measure_update_table('update_simple_btree',      'simple_btree',    v_rows, 1000, 6);
        PERFORM lab4.measure_update_table('update_unique_btree',      'unique_btree',    v_rows, 1000, 6);
        PERFORM lab4.measure_update_table('update_expression_index',  'expression_index',v_rows, 1000, 6);
        PERFORM lab4.measure_update_table('update_function_index',    'function_index',  v_rows, 1000, 6);
    END LOOP;
END $$;

\echo '=== 6.5. Итоговая таблица UPDATE ==='

SELECT
    index_type,
    rows_base,
    count(*) AS runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    round(avg(total_elapsed_ms), 3) AS avg_total_elapsed_ms,
    round(min(total_elapsed_ms), 3) AS min_total_elapsed_ms,
    round(max(total_elapsed_ms), 3) AS max_total_elapsed_ms,
    round(stddev_samp(total_elapsed_ms), 3) AS stddev_total_elapsed_ms,
    round(avg(avg_elapsed_ms_per_row), 6) AS avg_elapsed_ms_per_row
FROM lab4.update_measurements
GROUP BY index_type, rows_base
ORDER BY
    rows_base,
    CASE index_type
        WHEN 'no_extra_index' THEN 1
        WHEN 'simple_btree' THEN 2
        WHEN 'unique_btree' THEN 3
        WHEN 'expression_index' THEN 4
        WHEN 'function_index' THEN 5
        ELSE 6
    END;

\echo '=== 6.6. Проверка корректности UPDATE и триггеров ==='

SELECT
    index_type,
    count(DISTINCT rows_base) AS tested_table_sizes,
    count(*) AS total_runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    CASE
        WHEN min(affected_rows) = min(batch_size)
         AND max(affected_rows) = max(batch_size)
         AND min(trigger_rows) = min(batch_size)
         AND max(trigger_rows) = max(batch_size)
        THEN 'OK: every UPDATE changed expected rows and trigger fired for every row'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.update_measurements
GROUP BY index_type
ORDER BY index_type;

\echo '=== 6.7. Размеры таблиц UPDATE после финального размера ==='

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
  AND c.relname IN (
      'update_no_extra_index',
      'update_simple_btree',
      'update_unique_btree',
      'update_expression_index',
      'update_function_index'
  )
ORDER BY c.relname;

\echo '=== 6.8. EXPLAIN контроль UPDATE: базовая таблица ==='

EXPLAIN (ANALYZE, BUFFERS)
UPDATE lab4.update_no_extra_index
SET
    customer_id = (((customer_id::bigint + 13) % 100000)::integer + 1),
    unique_key = id + (900000001::bigint * 10000000::bigint),
    code = 'explain_' || id::text,
    amount = amount + 1,
    payload = md5(id::text || ':explain'),
    update_marker = 900000001
WHERE lookup_id BETWEEN 1 AND 1000;

\echo '=== 6.9. EXPLAIN контроль UPDATE: функциональный индекс ==='

EXPLAIN (ANALYZE, BUFFERS)
UPDATE lab4.update_function_index
SET
    customer_id = (((customer_id::bigint + 13) % 100000)::integer + 1),
    unique_key = id + (900000002::bigint * 10000000::bigint),
    code = 'explain_' || id::text,
    amount = amount + 1,
    payload = md5(id::text || ':explain'),
    update_marker = 900000002
WHERE lookup_id BETWEEN 1 AND 1000;

\echo '=== Шаг 6 SQL завершен ==='
