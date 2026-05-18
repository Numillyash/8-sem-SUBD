\pset pager off
\timing on

CREATE SCHEMA IF NOT EXISTS lab4;

DROP VIEW IF EXISTS lab4.v_30_update_index_usage_raw;
DROP VIEW IF EXISTS lab4.v_30_update_index_usage_aggregated;
DROP VIEW IF EXISTS lab4.v_30_update_index_usage_checks;
DROP VIEW IF EXISTS lab4.v_30_update_index_usage_explains;

DROP TABLE IF EXISTS lab4.update_index_usage_measurements;
DROP TABLE IF EXISTS lab4.update_index_usage_explains;
DROP TABLE IF EXISTS lab4.update_index_usage_work;

CREATE TABLE lab4.update_index_usage_measurements
(
    measurement_id bigserial PRIMARY KEY,
    measured_at timestamp NOT NULL DEFAULT clock_timestamp(),
    index_type text NOT NULL,
    mode text NOT NULL,
    rows_base bigint NOT NULL,
    run_no integer NOT NULL,
    affected_rows integer NOT NULL,
    elapsed_ms numeric(18, 6) NOT NULL,
    elapsed_ms_per_row numeric(18, 9) NOT NULL
);

CREATE TABLE lab4.update_index_usage_explains
(
    explain_id bigserial PRIMARY KEY,
    created_at timestamp NOT NULL DEFAULT clock_timestamp(),
    index_type text NOT NULL,
    mode text NOT NULL,
    rows_base bigint NOT NULL,
    explain_plan text NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.update_math_key
(
    p_customer_id integer,
    p_amount_cents integer
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT p_customer_id::bigint * 1000000::bigint + p_amount_cents::bigint;
$$;

CREATE OR REPLACE FUNCTION lab4.prepare_update_index_usage_work(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS lab4.update_index_usage_work;

    CREATE UNLOGGED TABLE lab4.update_index_usage_work AS
    SELECT
        gs::bigint AS id,
        gs::bigint AS search_key,
        gs::bigint AS simple_key,
        gs::bigint AS unique_key,
        0::integer AS customer_id,
        gs::integer AS amount_cents,
        md5(gs::text) || md5((gs * 17)::text) AS payload,
        0::integer AS update_marker
    FROM generate_series(1, p_rows) AS gs;

    ANALYZE lab4.update_index_usage_work;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_index_usage
(
    p_index_type text,
    p_mode text,
    p_rows_base bigint,
    p_run_no integer,
    p_set_sql text,
    p_where_sql text,
    p_from bigint,
    p_to bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_started_at timestamp;
    v_finished_at timestamp;
    v_elapsed_ms numeric(18, 6);
    v_affected_rows integer;
BEGIN
    v_started_at := clock_timestamp();

    EXECUTE format(
        'UPDATE lab4.update_index_usage_work SET %s WHERE %s',
        p_set_sql,
        p_where_sql
    )
    USING p_from, p_to;

    GET DIAGNOSTICS v_affected_rows = ROW_COUNT;

    v_finished_at := clock_timestamp();
    v_elapsed_ms := EXTRACT(EPOCH FROM (v_finished_at - v_started_at)) * 1000.0;

    INSERT INTO lab4.update_index_usage_measurements
    (
        index_type,
        mode,
        rows_base,
        run_no,
        affected_rows,
        elapsed_ms,
        elapsed_ms_per_row
    )
    VALUES
    (
        p_index_type,
        p_mode,
        p_rows_base,
        p_run_no,
        v_affected_rows,
        v_elapsed_ms,
        v_elapsed_ms / NULLIF(v_affected_rows, 0)
    );
END;
$$;

CREATE OR REPLACE FUNCTION lab4.save_update_index_usage_explain
(
    p_index_type text,
    p_mode text,
    p_rows_base bigint,
    p_set_sql text,
    p_where_sql text,
    p_from bigint,
    p_to bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_line text;
    v_plan text := '';
BEGIN
    FOR v_line IN
        EXECUTE format(
            'EXPLAIN (COSTS OFF, FORMAT TEXT)
             UPDATE lab4.update_index_usage_work SET %s WHERE %s',
            p_set_sql,
            p_where_sql
        )
        USING p_from, p_to
    LOOP
        v_plan := v_plan || v_line || E'\n';
    END LOOP;

    INSERT INTO lab4.update_index_usage_explains
    (
        index_type,
        mode,
        rows_base,
        explain_plan
    )
    VALUES
    (
        p_index_type,
        p_mode,
        p_rows_base,
        v_plan
    );
END;
$$;

\echo '=== 30a setup done ==='
