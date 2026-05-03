\pset pager off
\timing on

\echo '=== ЛР-4. Исправленный эксперимент UPDATE: одинаковый поиск, разные индексы, контроль триггеров ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.update_cost_measurements CASCADE;
DROP TABLE IF EXISTS lab4.update_cost_trigger_audit CASCADE;

DROP TABLE IF EXISTS lab4.update_cost_lookup_only CASCADE;
DROP TABLE IF EXISTS lab4.update_cost_simple_btree CASCADE;
DROP TABLE IF EXISTS lab4.update_cost_unique_btree CASCADE;
DROP TABLE IF EXISTS lab4.update_cost_expression_index CASCADE;
DROP TABLE IF EXISTS lab4.update_cost_function_index CASCADE;

DROP FUNCTION IF EXISTS lab4.update_cost_trigger_fn() CASCADE;
DROP FUNCTION IF EXISTS lab4.update_cost_function_key(bigint) CASCADE;
DROP FUNCTION IF EXISTS lab4.fill_update_cost_table(text, bigint) CASCADE;
DROP FUNCTION IF EXISTS lab4.measure_update_cost_table(text, text, bigint, bigint, integer) CASCADE;

CREATE TABLE lab4.update_cost_measurements (
    measurement_id bigserial PRIMARY KEY,
    measured_at timestamp NOT NULL DEFAULT clock_timestamp(),
    operation_name text NOT NULL,
    table_name text NOT NULL,
    index_type text NOT NULL,
    rows_before bigint NOT NULL,
    batch_size bigint NOT NULL,
    run_no integer NOT NULL,
    elapsed_ms numeric(12, 3) NOT NULL,
    affected_rows bigint NOT NULL,
    trigger_rows bigint NOT NULL
);

CREATE TABLE lab4.update_cost_trigger_audit (
    audit_id bigserial PRIMARY KEY,
    audit_at timestamp NOT NULL DEFAULT clock_timestamp(),
    run_id text NOT NULL,
    table_name text NOT NULL,
    old_tracked_value bigint NOT NULL,
    new_tracked_value bigint NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.update_cost_function_key(p_value bigint)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT md5(
        p_value::text || ':' ||
        (p_value * 17)::text || ':' ||
        (p_value * 31)::text || ':' ||
        (p_value * 47)::text
    );
$$;

CREATE OR REPLACE FUNCTION lab4.update_cost_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id text;
BEGIN
    v_run_id := current_setting('lab4.update_run_id', true);

    IF v_run_id IS NULL OR v_run_id = '' THEN
        v_run_id := 'manual_or_unmarked_update';
    END IF;

    INSERT INTO lab4.update_cost_trigger_audit (
        run_id,
        table_name,
        old_tracked_value,
        new_tracked_value
    )
    VALUES (
        v_run_id,
        TG_TABLE_NAME,
        OLD.tracked_value,
        NEW.tracked_value
    );

    RETURN NEW;
END;
$$;

CREATE TABLE lab4.update_cost_lookup_only (
    id bigint NOT NULL,
    lookup_id bigint NOT NULL,
    tracked_value bigint NOT NULL,
    payload text NOT NULL
);

CREATE TABLE lab4.update_cost_simple_btree      (LIKE lab4.update_cost_lookup_only);
CREATE TABLE lab4.update_cost_unique_btree      (LIKE lab4.update_cost_lookup_only);
CREATE TABLE lab4.update_cost_expression_index  (LIKE lab4.update_cost_lookup_only);
CREATE TABLE lab4.update_cost_function_index    (LIKE lab4.update_cost_lookup_only);

-- Одинаковый технический индекс поиска есть у всех таблиц.
-- Поэтому сравнивается не скорость поиска строки, а стоимость поддержки дополнительного индекса.
CREATE INDEX idx_update_cost_lookup_only_lookup
ON lab4.update_cost_lookup_only (lookup_id);

CREATE INDEX idx_update_cost_simple_lookup
ON lab4.update_cost_simple_btree (lookup_id);

CREATE INDEX idx_update_cost_unique_lookup
ON lab4.update_cost_unique_btree (lookup_id);

CREATE INDEX idx_update_cost_expression_lookup
ON lab4.update_cost_expression_index (lookup_id);

CREATE INDEX idx_update_cost_function_lookup
ON lab4.update_cost_function_index (lookup_id);

-- Проверяемые дополнительные индексы.
CREATE INDEX idx_update_cost_simple_tracked
ON lab4.update_cost_simple_btree (tracked_value);

CREATE UNIQUE INDEX idx_update_cost_unique_tracked
ON lab4.update_cost_unique_btree (tracked_value);

CREATE INDEX idx_update_cost_expression_tracked
ON lab4.update_cost_expression_index ((tracked_value + 0));

CREATE INDEX idx_update_cost_function_tracked
ON lab4.update_cost_function_index (lab4.update_cost_function_key(tracked_value));

CREATE TRIGGER trg_update_cost_lookup_only
AFTER UPDATE ON lab4.update_cost_lookup_only
FOR EACH ROW EXECUTE FUNCTION lab4.update_cost_trigger_fn();

CREATE TRIGGER trg_update_cost_simple_btree
AFTER UPDATE ON lab4.update_cost_simple_btree
FOR EACH ROW EXECUTE FUNCTION lab4.update_cost_trigger_fn();

CREATE TRIGGER trg_update_cost_unique_btree
AFTER UPDATE ON lab4.update_cost_unique_btree
FOR EACH ROW EXECUTE FUNCTION lab4.update_cost_trigger_fn();

CREATE TRIGGER trg_update_cost_expression_index
AFTER UPDATE ON lab4.update_cost_expression_index
FOR EACH ROW EXECUTE FUNCTION lab4.update_cost_trigger_fn();

CREATE TRIGGER trg_update_cost_function_index
AFTER UPDATE ON lab4.update_cost_function_index
FOR EACH ROW EXECUTE FUNCTION lab4.update_cost_trigger_fn();

CREATE OR REPLACE FUNCTION lab4.fill_update_cost_table(
    p_table_name text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('TRUNCATE TABLE lab4.%I', p_table_name);

    EXECUTE format(
        'INSERT INTO lab4.%I (id, lookup_id, tracked_value, payload)
         SELECT
             g,
             g,
             g,
             md5(g::text || random()::text)
         FROM generate_series(1, %s) AS g',
        p_table_name,
        p_rows
    );

    EXECUTE format('ANALYZE lab4.%I', p_table_name);
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_cost_table(
    p_table_name text,
    p_index_type text,
    p_rows bigint,
    p_batch_size bigint DEFAULT 1000,
    p_runs integer DEFAULT 5
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    t1 double precision;
    t2 double precision;
    v_start bigint;
    v_finish bigint;
    v_delta bigint;
    v_affected bigint;
    v_trigger_rows bigint;
    v_run_id text;
BEGIN
    PERFORM lab4.fill_update_cost_table(p_table_name, p_rows);

    FOR i IN 1..p_runs LOOP
        v_start := 1 + ((i - 1) * p_batch_size * 7) % (p_rows - p_batch_size);
        v_finish := v_start + p_batch_size - 1;

        -- Большой сдвиг нужен, чтобы не нарушить UNIQUE для unique_btree.
        v_delta := p_rows + i * 10000000;

        v_run_id := p_table_name || '_rows_' || p_rows::text || '_run_' || i::text;
        PERFORM set_config('lab4.update_run_id', v_run_id, true);

        t1 := extract(epoch from clock_timestamp()) * 1000;

        EXECUTE format(
            'UPDATE lab4.%I
             SET tracked_value = tracked_value + $1
             WHERE lookup_id BETWEEN $2 AND $3',
            p_table_name
        )
        USING v_delta, v_start, v_finish;

        GET DIAGNOSTICS v_affected = ROW_COUNT;

        t2 := extract(epoch from clock_timestamp()) * 1000;

        SELECT count(*)
        INTO v_trigger_rows
        FROM lab4.update_cost_trigger_audit
        WHERE run_id = v_run_id;

        INSERT INTO lab4.update_cost_measurements (
            operation_name,
            table_name,
            index_type,
            rows_before,
            batch_size,
            run_no,
            elapsed_ms,
            affected_rows,
            trigger_rows
        )
        VALUES (
            'update_batch_isolated_lookup',
            p_table_name,
            p_index_type,
            p_rows,
            p_batch_size,
            i,
            round((t2 - t1)::numeric, 3),
            v_affected,
            v_trigger_rows
        );
    END LOOP;
END;
$$;

\echo '=== Запуск исправленного эксперимента UPDATE ==='

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
        RAISE NOTICE 'Running isolated UPDATE size %', v_rows;

        PERFORM lab4.measure_update_cost_table('update_cost_lookup_only',       'lookup_only',      v_rows, 1000, 5);
        PERFORM lab4.measure_update_cost_table('update_cost_simple_btree',      'simple_btree',     v_rows, 1000, 5);
        PERFORM lab4.measure_update_cost_table('update_cost_unique_btree',      'unique_btree',     v_rows, 1000, 5);
        PERFORM lab4.measure_update_cost_table('update_cost_expression_index',  'expression_index', v_rows, 1000, 5);
        PERFORM lab4.measure_update_cost_table('update_cost_function_index',    'function_index',   v_rows, 1000, 5);
    END LOOP;
END $$;

\echo '=== Итоговая таблица исправленного UPDATE ==='

SELECT
    index_type,
    rows_before,
    batch_size,
    count(*) AS runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
    round(min(elapsed_ms), 3) AS min_elapsed_ms,
    round(max(elapsed_ms), 3) AS max_elapsed_ms,
    round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
FROM lab4.update_cost_measurements
GROUP BY index_type, rows_before, batch_size
ORDER BY
    rows_before,
    CASE index_type
        WHEN 'lookup_only' THEN 1
        WHEN 'simple_btree' THEN 2
        WHEN 'unique_btree' THEN 3
        WHEN 'expression_index' THEN 4
        WHEN 'function_index' THEN 5
        ELSE 6
    END;

\echo '=== Контроль срабатывания триггеров ==='

SELECT
    index_type,
    count(DISTINCT rows_before) AS tested_table_sizes,
    count(*) AS total_runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    CASE
        WHEN min(affected_rows) = 1000
         AND max(affected_rows) = 1000
         AND min(trigger_rows) = 1000
         AND max(trigger_rows) = 1000
        THEN 'OK: every UPDATE affected 1000 rows and trigger fired 1000 times'
        ELSE 'CHECK FAILED'
    END AS check_result
FROM lab4.update_cost_measurements
GROUP BY index_type
ORDER BY
    CASE index_type
        WHEN 'lookup_only' THEN 1
        WHEN 'simple_btree' THEN 2
        WHEN 'unique_btree' THEN 3
        WHEN 'expression_index' THEN 4
        WHEN 'function_index' THEN 5
        ELSE 6
    END;

\echo '=== EXPLAIN контроль: поиск через одинаковый lookup_id ==='

EXPLAIN (ANALYZE, BUFFERS)
UPDATE lab4.update_cost_lookup_only
SET tracked_value = tracked_value + 1
WHERE lookup_id BETWEEN 1000 AND 1999;

EXPLAIN (ANALYZE, BUFFERS)
UPDATE lab4.update_cost_function_index
SET tracked_value = tracked_value + 1
WHERE lookup_id BETWEEN 1000 AND 1999;
