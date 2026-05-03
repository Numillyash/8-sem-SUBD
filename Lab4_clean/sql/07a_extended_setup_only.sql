\pset pager off
\timing on

\echo '=== ЛР-4. Расширенный transient-прогон: SELECT / INSERT / UPDATE на 10..50 000 000 строк ==='

SET search_path TO lab4, public;

DROP TABLE IF EXISTS lab4.extended_all_sizes_measurements CASCADE;
DROP TABLE IF EXISTS lab4.extended_all_sizes_sizes CASCADE;
DROP TABLE IF EXISTS lab4.extended_update_trigger_audit CASCADE;

DROP TABLE IF EXISTS lab4.ext_select_work CASCADE;
DROP TABLE IF EXISTS lab4.ext_insert_work CASCADE;
DROP TABLE IF EXISTS lab4.ext_update_work CASCADE;

DROP FUNCTION IF EXISTS lab4.ext_permutation_key(bigint, bigint);
DROP FUNCTION IF EXISTS lab4.ext_insert_function_key(text, integer);
DROP FUNCTION IF EXISTS lab4.ext_update_function_key(integer, integer);
DROP FUNCTION IF EXISTS lab4.ext_record_size(text, text, bigint, text);
DROP FUNCTION IF EXISTS lab4.ext_prepare_select(bigint);
DROP FUNCTION IF EXISTS lab4.ext_measure_select(text, bigint, integer, integer);
DROP FUNCTION IF EXISTS lab4.ext_prepare_insert_table(bigint);
DROP FUNCTION IF EXISTS lab4.ext_apply_insert_index(text, bigint);
DROP FUNCTION IF EXISTS lab4.ext_measure_insert_table(text, bigint, integer, integer);
DROP FUNCTION IF EXISTS lab4.ext_update_trigger_fn();
DROP FUNCTION IF EXISTS lab4.ext_prepare_update_table(bigint);
DROP FUNCTION IF EXISTS lab4.ext_apply_update_index(text, bigint);
DROP FUNCTION IF EXISTS lab4.ext_measure_update_table(text, bigint, integer, integer);

CREATE TABLE lab4.extended_all_sizes_measurements (
    measurement_id              bigserial PRIMARY KEY,
    measured_at                 timestamp NOT NULL DEFAULT clock_timestamp(),
    operation_name              text NOT NULL,
    index_type                  text NOT NULL,
    rows_base                   bigint NOT NULL,
    batch_size                  integer,
    probes                      integer,
    run_no                      integer NOT NULL,
    total_elapsed_ms            numeric(18, 6),
    elapsed_ms_per_operation    numeric(18, 6),
    affected_rows               bigint,
    found_rows                  bigint,
    trigger_rows                bigint
);

CREATE TABLE lab4.extended_all_sizes_sizes (
    size_id             bigserial PRIMARY KEY,
    measured_at         timestamp NOT NULL DEFAULT clock_timestamp(),
    operation_name      text NOT NULL,
    index_type          text NOT NULL,
    rows_base           bigint NOT NULL,
    table_name          text NOT NULL,
    relation_bytes      bigint NOT NULL,
    indexes_bytes       bigint NOT NULL,
    total_bytes         bigint NOT NULL,
    relation_size       text NOT NULL,
    indexes_size        text NOT NULL,
    total_size          text NOT NULL
);

CREATE TABLE lab4.extended_update_trigger_audit (
    audit_id        bigserial PRIMARY KEY,
    measurement_id  bigint NOT NULL,
    index_type      text NOT NULL,
    rows_base       bigint NOT NULL,
    row_id          bigint NOT NULL,
    fired_at        timestamp NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION lab4.ext_permutation_key(p_i bigint, p_mod bigint)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN $2 <= 0 THEN 0
        ELSE (($1 * 48271) % $2) + 1
    END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_insert_function_key(p_payload text, p_category integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT length($1) * 131 + COALESCE($2, 0);
$$;

CREATE OR REPLACE FUNCTION lab4.ext_update_function_key(p_changed_value integer, p_category integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE($1, 0) * 131 + COALESCE($2, 0);
$$;

CREATE OR REPLACE FUNCTION lab4.ext_record_size(
    p_operation_name text,
    p_index_type text,
    p_rows_base bigint,
    p_table_name text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_reg regclass;
BEGIN
    v_reg := to_regclass(p_table_name);

    IF v_reg IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO lab4.extended_all_sizes_sizes (
        operation_name,
        index_type,
        rows_base,
        table_name,
        relation_bytes,
        indexes_bytes,
        total_bytes,
        relation_size,
        indexes_size,
        total_size
    )
    SELECT
        p_operation_name,
        p_index_type,
        p_rows_base,
        p_table_name,
        pg_relation_size(v_reg),
        pg_indexes_size(v_reg),
        pg_total_relation_size(v_reg),
        pg_size_pretty(pg_relation_size(v_reg)),
        pg_size_pretty(pg_indexes_size(v_reg)),
        pg_size_pretty(pg_total_relation_size(v_reg));
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_prepare_select(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS lab4.ext_select_work;

    CREATE TABLE lab4.ext_select_work (
        id          bigint NOT NULL,
        lookup_key  bigint NOT NULL,
        aux         integer NOT NULL,
        payload     text NOT NULL
    );

    INSERT INTO lab4.ext_select_work (id, lookup_key, aux, payload)
    SELECT
        g,
        lab4.ext_permutation_key(g, p_rows),
        (g % 1000000)::integer,
        'payload_' || (g % 100000)::text
    FROM generate_series(1, p_rows) AS s(g);

    ANALYZE lab4.ext_select_work;

    PERFORM lab4.ext_record_size(
        'select',
        'without_index_nonclustered',
        p_rows,
        'lab4.ext_select_work'
    );
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_measure_select(
    p_index_type text,
    p_rows bigint,
    p_probes integer,
    p_runs integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run           integer;
    v_probe         integer;
    v_key           bigint;
    v_found         bigint;
    v_found_total   bigint;
    v_started_at    timestamp;
    v_elapsed_ms    numeric(18, 6);
BEGIN
    FOR v_run IN 1..p_runs LOOP
        v_found_total := 0;
        v_started_at := clock_timestamp();

        FOR v_probe IN 1..p_probes LOOP
            v_key := (((v_probe::bigint * 104729) + (v_run::bigint * 1009)) % p_rows) + 1;

            EXECUTE
                'SELECT count(*) FROM lab4.ext_select_work WHERE lookup_key = $1'
            INTO v_found
            USING v_key;

            v_found_total := v_found_total + v_found;
        END LOOP;

        v_elapsed_ms := EXTRACT(epoch FROM clock_timestamp() - v_started_at) * 1000.0;

        INSERT INTO lab4.extended_all_sizes_measurements (
            operation_name,
            index_type,
            rows_base,
            batch_size,
            probes,
            run_no,
            total_elapsed_ms,
            elapsed_ms_per_operation,
            affected_rows,
            found_rows,
            trigger_rows
        )
        VALUES (
            'select',
            p_index_type,
            p_rows,
            NULL,
            p_probes,
            v_run,
            v_elapsed_ms,
            v_elapsed_ms / p_probes,
            NULL,
            v_found_total,
            NULL
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_prepare_insert_table(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS lab4.ext_insert_work;

    CREATE TABLE lab4.ext_insert_work (
        id             bigint NOT NULL,
        lookup_id      bigint NOT NULL,
        unique_code    bigint NOT NULL,
        category       integer NOT NULL,
        amount         numeric(12, 2) NOT NULL,
        payload        text NOT NULL
    );

    INSERT INTO lab4.ext_insert_work (id, lookup_id, unique_code, category, amount, payload)
    SELECT
        g,
        lab4.ext_permutation_key(g, p_rows),
        g,
        (g % 1000)::integer,
        ((g % 100000)::numeric / 10.0),
        'payload_' || (g % 100000)::text
    FROM generate_series(1, p_rows) AS s(g);

    ANALYZE lab4.ext_insert_work;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_apply_insert_index(
    p_index_type text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP INDEX IF EXISTS lab4.idx_ext_insert_simple;
    DROP INDEX IF EXISTS lab4.idx_ext_insert_unique;
    DROP INDEX IF EXISTS lab4.idx_ext_insert_expression;
    DROP INDEX IF EXISTS lab4.idx_ext_insert_function;

    IF p_index_type = 'simple_btree' THEN
        CREATE INDEX idx_ext_insert_simple
        ON lab4.ext_insert_work (category);
    ELSIF p_index_type = 'unique_btree' THEN
        CREATE UNIQUE INDEX idx_ext_insert_unique
        ON lab4.ext_insert_work (unique_code);
    ELSIF p_index_type = 'expression_index' THEN
        CREATE INDEX idx_ext_insert_expression
        ON lab4.ext_insert_work ((lower(payload)));
    ELSIF p_index_type = 'function_index' THEN
        CREATE INDEX idx_ext_insert_function
        ON lab4.ext_insert_work (lab4.ext_insert_function_key(payload, category));
    END IF;

    ANALYZE lab4.ext_insert_work;

    PERFORM lab4.ext_record_size(
        'insert',
        p_index_type,
        p_rows,
        'lab4.ext_insert_work'
    );
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_measure_insert_table(
    p_index_type text,
    p_rows bigint,
    p_batch_size integer,
    p_runs integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run           integer;
    v_started_at    timestamp;
    v_elapsed_ms    numeric(18, 6);
    v_affected      bigint;
BEGIN
    FOR v_run IN 1..p_runs LOOP
        v_started_at := clock_timestamp();

        INSERT INTO lab4.ext_insert_work (id, lookup_id, unique_code, category, amount, payload)
        SELECT
            p_rows + g,
            lab4.ext_permutation_key(p_rows + g, p_rows + p_batch_size + 1000),
            p_rows + g,
            ((p_rows + g) % 1000)::integer,
            (((p_rows + g) % 100000)::numeric / 10.0),
            'payload_' || ((p_rows + g) % 100000)::text
        FROM generate_series(1, p_batch_size) AS s(g);

        GET DIAGNOSTICS v_affected = ROW_COUNT;

        v_elapsed_ms := EXTRACT(epoch FROM clock_timestamp() - v_started_at) * 1000.0;

        INSERT INTO lab4.extended_all_sizes_measurements (
            operation_name,
            index_type,
            rows_base,
            batch_size,
            probes,
            run_no,
            total_elapsed_ms,
            elapsed_ms_per_operation,
            affected_rows,
            found_rows,
            trigger_rows
        )
        VALUES (
            'insert',
            p_index_type,
            p_rows,
            p_batch_size,
            NULL,
            v_run,
            v_elapsed_ms,
            v_elapsed_ms / p_batch_size,
            v_affected,
            NULL,
            NULL
        );

        DELETE FROM lab4.ext_insert_work
        WHERE id > p_rows
          AND id <= p_rows + p_batch_size;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_update_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO lab4.extended_update_trigger_audit (
        measurement_id,
        index_type,
        rows_base,
        row_id
    )
    VALUES (
        current_setting('lab4.ext_measurement_id')::bigint,
        current_setting('lab4.ext_index_type'),
        current_setting('lab4.ext_rows_base')::bigint,
        NEW.id
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_prepare_update_table(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS lab4.ext_update_work;

    CREATE TABLE lab4.ext_update_work (
        id             bigint NOT NULL,
        lookup_id      bigint NOT NULL,
        unique_code    bigint NOT NULL,
        category       integer NOT NULL,
        changed_value  integer NOT NULL,
        amount         numeric(12, 2) NOT NULL,
        payload        text NOT NULL
    );

    INSERT INTO lab4.ext_update_work (
        id,
        lookup_id,
        unique_code,
        category,
        changed_value,
        amount,
        payload
    )
    SELECT
        g,
        lab4.ext_permutation_key(g, p_rows),
        g,
        (g % 1000)::integer,
        (g % 10000)::integer,
        ((g % 100000)::numeric / 10.0),
        'payload_' || (g % 100000)::text
    FROM generate_series(1, p_rows) AS s(g);

    CREATE INDEX idx_ext_update_lookup
    ON lab4.ext_update_work (lookup_id);

    CREATE TRIGGER trg_ext_update_work
    AFTER UPDATE ON lab4.ext_update_work
    FOR EACH ROW
    EXECUTE FUNCTION lab4.ext_update_trigger_fn();

    ANALYZE lab4.ext_update_work;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_apply_update_index(
    p_index_type text,
    p_rows bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP INDEX IF EXISTS lab4.idx_ext_update_simple;
    DROP INDEX IF EXISTS lab4.idx_ext_update_unique;
    DROP INDEX IF EXISTS lab4.idx_ext_update_expression;
    DROP INDEX IF EXISTS lab4.idx_ext_update_function;

    IF p_index_type = 'simple_btree' THEN
        CREATE INDEX idx_ext_update_simple
        ON lab4.ext_update_work (changed_value);
    ELSIF p_index_type = 'unique_btree' THEN
        CREATE UNIQUE INDEX idx_ext_update_unique
        ON lab4.ext_update_work (unique_code);
    ELSIF p_index_type = 'expression_index' THEN
        CREATE INDEX idx_ext_update_expression
        ON lab4.ext_update_work (((changed_value + category) % 1000000));
    ELSIF p_index_type = 'function_index' THEN
        CREATE INDEX idx_ext_update_function
        ON lab4.ext_update_work (lab4.ext_update_function_key(changed_value, category));
    END IF;

    ANALYZE lab4.ext_update_work;

    PERFORM lab4.ext_record_size(
        'update',
        p_index_type,
        p_rows,
        'lab4.ext_update_work'
    );
END;
$$;

CREATE OR REPLACE FUNCTION lab4.ext_measure_update_table(
    p_index_type text,
    p_rows bigint,
    p_batch_size integer,
    p_runs integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run              integer;
    v_started_at       timestamp;
    v_elapsed_ms       numeric(18, 6);
    v_affected         bigint;
    v_trigger_rows     bigint;
    v_measurement_id   bigint;
    v_key_start        bigint;
    v_key_end          bigint;
    v_delta            bigint;
BEGIN
    FOR v_run IN 1..p_runs LOOP
        IF p_rows <= p_batch_size THEN
            v_key_start := 1;
        ELSE
            v_key_start := (((v_run::bigint * 104729) % (p_rows - p_batch_size + 1)) + 1);
        END IF;

        v_key_end := v_key_start + p_batch_size - 1;

        INSERT INTO lab4.extended_all_sizes_measurements (
            operation_name,
            index_type,
            rows_base,
            batch_size,
            probes,
            run_no,
            total_elapsed_ms,
            elapsed_ms_per_operation,
            affected_rows,
            found_rows,
            trigger_rows
        )
        VALUES (
            'update',
            p_index_type,
            p_rows,
            p_batch_size,
            NULL,
            v_run,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        )
        RETURNING measurement_id INTO v_measurement_id;

        PERFORM set_config('lab4.ext_measurement_id', v_measurement_id::text, true);
        PERFORM set_config('lab4.ext_index_type', p_index_type, true);
        PERFORM set_config('lab4.ext_rows_base', p_rows::text, true);

        v_started_at := clock_timestamp();

        IF p_index_type = 'unique_btree' THEN
            v_delta := 1000000000000 + (v_run::bigint * 100000000) + p_rows;

            UPDATE lab4.ext_update_work
            SET unique_code = unique_code + v_delta
            WHERE lookup_id BETWEEN v_key_start AND v_key_end;
        ELSE
            UPDATE lab4.ext_update_work
            SET changed_value = changed_value + 1
            WHERE lookup_id BETWEEN v_key_start AND v_key_end;
        END IF;

        GET DIAGNOSTICS v_affected = ROW_COUNT;

        v_elapsed_ms := EXTRACT(epoch FROM clock_timestamp() - v_started_at) * 1000.0;

        SELECT count(*)
        INTO v_trigger_rows
        FROM lab4.extended_update_trigger_audit
        WHERE measurement_id = v_measurement_id;

        UPDATE lab4.extended_all_sizes_measurements
        SET
            total_elapsed_ms = v_elapsed_ms,
            elapsed_ms_per_operation = v_elapsed_ms / p_batch_size,
            affected_rows = v_affected,
            trigger_rows = v_trigger_rows
        WHERE measurement_id = v_measurement_id;
    END LOOP;
END;
$$;

