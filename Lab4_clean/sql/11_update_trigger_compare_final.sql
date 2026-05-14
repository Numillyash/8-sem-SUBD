\pset pager off
\timing on

SET client_min_messages = notice;
SET jit = off;
SET synchronous_commit = off;
SET work_mem = '256MB';

CREATE SCHEMA IF NOT EXISTS lab4;

DROP TABLE IF EXISTS lab4.update_trigger_compare_measurements CASCADE;

CREATE UNLOGGED TABLE lab4.update_trigger_compare_measurements
(
    id                         bigserial PRIMARY KEY,
    measured_at                 timestamp NOT NULL DEFAULT clock_timestamp(),
    index_type                  text NOT NULL,
    trigger_mode                text NOT NULL,
    rows_base                   integer NOT NULL,
    run_no                      integer NOT NULL,
    chunk_count                 integer NOT NULL,
    chunk_size                  integer NOT NULL,
    affected_rows               integer NOT NULL,
    trigger_rows                integer NOT NULL,
    total_elapsed_ms            numeric NOT NULL,
    avg_elapsed_ms_per_row      numeric NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.update_trigger_payload_len(p text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT length(p);
$$;

CREATE OR REPLACE FUNCTION lab4.update_trigger_compare_audit_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO lab4.update_trigger_compare_audit
    (
        run_tag,
        index_type,
        old_id,
        new_id,
        changed_at
    )
    VALUES
    (
        current_setting('lab4.current_run_tag', true),
        current_setting('lab4.current_index_type', true),
        OLD.id,
        NEW.id,
        clock_timestamp()
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.update_trigger_compare_fill
(
    p_rows integer,
    p_index_type text,
    p_trigger_enabled boolean
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'DROP TABLE IF EXISTS lab4.update_trigger_compare_work CASCADE';
    EXECUTE 'DROP TABLE IF EXISTS lab4.update_trigger_compare_audit CASCADE';

    EXECUTE '
        CREATE UNLOGGED TABLE lab4.update_trigger_compare_work
        (
            id            bigserial PRIMARY KEY,
            lookup_id     bigint NOT NULL,
            update_value  bigint NOT NULL,
            payload       text NOT NULL,
            audit_marker  integer NOT NULL DEFAULT 0
        )
    ';

    EXECUTE format($q$
        INSERT INTO lab4.update_trigger_compare_work
        (
            lookup_id,
            update_value,
            payload
        )
        SELECT
            g,
            g,
            repeat(md5(g::text), 2)
        FROM generate_series(1, %s) AS g
        ORDER BY random()
    $q$, p_rows);

    EXECUTE '
        CREATE UNLOGGED TABLE lab4.update_trigger_compare_audit
        (
            id          bigserial PRIMARY KEY,
            run_tag     text,
            index_type  text,
            old_id      bigint,
            new_id      bigint,
            changed_at  timestamp NOT NULL
        )
    ';

    -- Настоящий вариант без индекса поиска: lookup_id не индексируется.
    IF p_index_type <> 'no_lookup_index' THEN
        EXECUTE '
            CREATE INDEX idx_update_trigger_lookup
            ON lab4.update_trigger_compare_work(lookup_id)
        ';
    END IF;

    IF p_index_type = 'simple_btree' THEN
        EXECUTE '
            CREATE INDEX idx_update_trigger_simple
            ON lab4.update_trigger_compare_work(update_value)
        ';
    ELSIF p_index_type = 'unique_btree' THEN
        EXECUTE '
            CREATE UNIQUE INDEX idx_update_trigger_unique
            ON lab4.update_trigger_compare_work(update_value)
        ';
    ELSIF p_index_type = 'expression_index' THEN
        EXECUTE '
            CREATE INDEX idx_update_trigger_expression
            ON lab4.update_trigger_compare_work((lower(payload)))
        ';
    ELSIF p_index_type = 'function_index' THEN
        EXECUTE '
            CREATE INDEX idx_update_trigger_function
            ON lab4.update_trigger_compare_work((lab4.update_trigger_payload_len(payload)))
        ';
    END IF;

    IF p_trigger_enabled THEN
        EXECUTE '
            CREATE TRIGGER trg_update_trigger_compare_audit
            AFTER UPDATE ON lab4.update_trigger_compare_work
            FOR EACH ROW
            EXECUTE FUNCTION lab4.update_trigger_compare_audit_fn()
        ';
    END IF;

    EXECUTE 'ANALYZE lab4.update_trigger_compare_work';
END;
$$;

CREATE OR REPLACE FUNCTION lab4.update_trigger_compare_run
(
    p_rows integer,
    p_index_type text,
    p_trigger_enabled boolean,
    p_run_no integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_mode              text := CASE WHEN p_trigger_enabled THEN 'with_trigger' ELSE 'without_trigger' END;
    v_start             timestamp;
    v_elapsed_ms         numeric;
    v_chunk_no           integer;
    v_chunk_count        integer := 100;
    v_chunk_size         integer := 10;
    v_lo                 bigint;
    v_hi                 bigint;
    v_missing            integer;
    v_part_affected      integer;
    v_total_affected     integer := 0;
    v_trigger_rows       integer := 0;
    v_set_sql            text;
BEGIN
    PERFORM set_config(
        'lab4.current_run_tag',
        p_index_type || ':' || v_mode || ':rows=' || p_rows::text || ':run=' || p_run_no::text,
        true
    );

    PERFORM set_config('lab4.current_index_type', p_index_type, true);

    IF p_index_type IN ('simple_btree', 'unique_btree') THEN
        v_set_sql := 'update_value = update_value + 1000000';
    ELSIF p_index_type IN ('expression_index', 'function_index') THEN
        v_set_sql := 'payload = payload || ''x''';
    ELSE
        v_set_sql := 'audit_marker = audit_marker + 1';
    END IF;

    EXECUTE 'TRUNCATE lab4.update_trigger_compare_audit';

    v_start := clock_timestamp();

    FOR v_chunk_no IN 1..v_chunk_count LOOP
        v_lo := (((v_chunk_no - 1) * v_chunk_size) % p_rows) + 1;
        v_hi := LEAST(v_lo + v_chunk_size - 1, p_rows);

        EXECUTE format(
            'UPDATE lab4.update_trigger_compare_work SET %s WHERE lookup_id BETWEEN $1 AND $2',
            v_set_sql
        )
        USING v_lo, v_hi;

        GET DIAGNOSTICS v_part_affected = ROW_COUNT;
        v_total_affected := v_total_affected + v_part_affected;

        v_missing := v_chunk_size - v_part_affected;

        IF v_missing > 0 THEN
            EXECUTE format(
                'UPDATE lab4.update_trigger_compare_work SET %s WHERE lookup_id BETWEEN 1 AND $1',
                v_set_sql
            )
            USING v_missing;

            GET DIAGNOSTICS v_part_affected = ROW_COUNT;
            v_total_affected := v_total_affected + v_part_affected;
        END IF;
    END LOOP;

    v_elapsed_ms := extract(epoch FROM (clock_timestamp() - v_start)) * 1000;

    SELECT count(*)
    INTO v_trigger_rows
    FROM lab4.update_trigger_compare_audit;

    INSERT INTO lab4.update_trigger_compare_measurements
    (
        index_type,
        trigger_mode,
        rows_base,
        run_no,
        chunk_count,
        chunk_size,
        affected_rows,
        trigger_rows,
        total_elapsed_ms,
        avg_elapsed_ms_per_row
    )
    VALUES
    (
        p_index_type,
        v_mode,
        p_rows,
        p_run_no,
        v_chunk_count,
        v_chunk_size,
        v_total_affected,
        v_trigger_rows,
        v_elapsed_ms,
        v_elapsed_ms / NULLIF(v_total_affected, 0)
    );
END;
$$;

DO $$
DECLARE
    v_sizes integer[] := ARRAY[
        10, 25, 50, 100, 250, 500,
        1000, 2500, 5000, 10000, 25000, 50000,
        100000, 250000, 500000
    ];

    -- no_lookup_index нужен только для общего графика настоящего безиндексного поиска.
    -- no_extra_index нужен как базовый вариант с индексом поиска, но без дополнительного индекса.
    v_index_types text[] := ARRAY[
        'no_lookup_index',
        'no_extra_index',
        'simple_btree',
        'unique_btree',
        'expression_index',
        'function_index'
    ];

    v_size integer;
    v_index_type text;
    v_trigger_enabled boolean;
    v_run integer;
    v_trigger_modes boolean[];
BEGIN
    FOREACH v_size IN ARRAY v_sizes LOOP
        FOREACH v_index_type IN ARRAY v_index_types LOOP

            IF v_index_type IN ('no_lookup_index', 'no_extra_index') THEN
                v_trigger_modes := ARRAY[false];
            ELSE
                v_trigger_modes := ARRAY[false, true];
            END IF;

            FOREACH v_trigger_enabled IN ARRAY v_trigger_modes LOOP
                RAISE NOTICE 'UPDATE trigger compare: rows=%, index_type=%, trigger=%',
                    v_size, v_index_type, v_trigger_enabled;

                PERFORM lab4.update_trigger_compare_fill
                (
                    v_size,
                    v_index_type,
                    v_trigger_enabled
                );

                FOR v_run IN 1..5 LOOP
                    PERFORM lab4.update_trigger_compare_run
                    (
                        v_size,
                        v_index_type,
                        v_trigger_enabled,
                        v_run
                    );
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;
END $$;

\echo '=== UPDATE trigger compare summary ==='

SELECT
    index_type,
    trigger_mode,
    rows_base,
    count(*) AS runs,
    min(chunk_count) AS chunk_count_min,
    max(chunk_count) AS chunk_count_max,
    min(chunk_size) AS chunk_size_min,
    max(chunk_size) AS chunk_size_max,
    min(affected_rows) AS affected_min,
    max(affected_rows) AS affected_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    round(avg(total_elapsed_ms), 6) AS avg_total_elapsed_ms,
    round(avg(avg_elapsed_ms_per_row), 9) AS avg_elapsed_ms_per_row
FROM lab4.update_trigger_compare_measurements
GROUP BY index_type, trigger_mode, rows_base
ORDER BY
    rows_base,
    index_type,
    trigger_mode;

\echo '=== UPDATE trigger compare checks ==='

SELECT
    index_type,
    trigger_mode,
    rows_base,
    min(affected_rows) AS affected_min,
    max(affected_rows) AS affected_max,
    min(trigger_rows) AS trigger_rows_min,
    max(trigger_rows) AS trigger_rows_max,
    CASE
        WHEN min(affected_rows) <> 1000 OR max(affected_rows) <> 1000
            THEN 'FAIL: affected_rows must be 1000'
        WHEN trigger_mode = 'with_trigger'
             AND (min(trigger_rows) <> 1000 OR max(trigger_rows) <> 1000)
            THEN 'FAIL: trigger_rows must be 1000'
        WHEN trigger_mode = 'without_trigger'
             AND (min(trigger_rows) <> 0 OR max(trigger_rows) <> 0)
            THEN 'FAIL: trigger_rows must be 0'
        ELSE 'OK'
    END AS check_result
FROM lab4.update_trigger_compare_measurements
GROUP BY index_type, trigger_mode, rows_base
ORDER BY
    rows_base,
    index_type,
    trigger_mode;

\echo '=== EXPLAIN control: true no lookup index ==='

SELECT lab4.update_trigger_compare_fill(500000, 'no_lookup_index', false);

EXPLAIN (ANALYZE, BUFFERS)
UPDATE lab4.update_trigger_compare_work
SET audit_marker = audit_marker + 1
WHERE lookup_id BETWEEN 499991 AND 500000;

\echo '=== EXPLAIN control: indexed lookup ==='

SELECT lab4.update_trigger_compare_fill(500000, 'simple_btree', false);

EXPLAIN (ANALYZE, BUFFERS)
UPDATE lab4.update_trigger_compare_work
SET update_value = update_value + 1000000
WHERE lookup_id BETWEEN 499991 AND 500000;

DROP TABLE IF EXISTS lab4.update_trigger_compare_work CASCADE;
DROP TABLE IF EXISTS lab4.update_trigger_compare_audit CASCADE;

\echo '=== UPDATE trigger compare done ==='
