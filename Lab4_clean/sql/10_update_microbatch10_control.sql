\pset pager off
\timing on

SET search_path = lab4, public;
SET jit = off;
SET max_parallel_workers_per_gather = 0;

DROP TABLE IF EXISTS lab4.update_microbatch10_measurements;
DROP TABLE IF EXISTS lab4.update_microbatch10_work;
DROP FUNCTION IF EXISTS lab4.update_microbatch10_function_key(text);
DROP FUNCTION IF EXISTS lab4.fill_update_microbatch10_table(bigint);
DROP FUNCTION IF EXISTS lab4.apply_update_microbatch10_index(text);
DROP FUNCTION IF EXISTS lab4.measure_update_microbatch10(text, bigint, int, int, int);

CREATE TABLE lab4.update_microbatch10_measurements (
    index_type text NOT NULL,
    rows_base bigint NOT NULL,
    run_no int NOT NULL,
    chunk_count int NOT NULL,
    chunk_size int NOT NULL,
    total_affected_rows bigint NOT NULL,
    elapsed_ms numeric(18,6) NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.update_microbatch10_function_key(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT reverse(lower(p_value));
$$;

CREATE OR REPLACE FUNCTION lab4.fill_update_microbatch10_table(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS lab4.update_microbatch10_work;

    CREATE TABLE lab4.update_microbatch10_work (
        row_id bigint NOT NULL,
        lookup_id bigint NOT NULL,
        index_value text NOT NULL,
        unique_value bigint NOT NULL,
        filler text NOT NULL
    );

    INSERT INTO lab4.update_microbatch10_work (
        row_id,
        lookup_id,
        index_value,
        unique_value,
        filler
    )
    SELECT
        g AS row_id,
        g AS lookup_id,
        md5(g::text) AS index_value,
        g AS unique_value,
        repeat('x', 64) AS filler
    FROM generate_series(1, p_rows) AS g;

    ANALYZE lab4.update_microbatch10_work;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.apply_update_microbatch10_index(p_index_type text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP INDEX IF EXISTS lab4.idx_update_microbatch10_lookup;
    DROP INDEX IF EXISTS lab4.idx_update_microbatch10_simple;
    DROP INDEX IF EXISTS lab4.idx_update_microbatch10_unique;
    DROP INDEX IF EXISTS lab4.idx_update_microbatch10_expression;
    DROP INDEX IF EXISTS lab4.idx_update_microbatch10_function;

    IF p_index_type <> 'no_lookup_index' THEN
        CREATE INDEX idx_update_microbatch10_lookup
        ON lab4.update_microbatch10_work (lookup_id);
    END IF;

    IF p_index_type = 'simple_btree' THEN
        CREATE INDEX idx_update_microbatch10_simple
        ON lab4.update_microbatch10_work (index_value);

    ELSIF p_index_type = 'unique_btree' THEN
        CREATE UNIQUE INDEX idx_update_microbatch10_unique
        ON lab4.update_microbatch10_work (unique_value);

    ELSIF p_index_type = 'expression_index' THEN
        CREATE INDEX idx_update_microbatch10_expression
        ON lab4.update_microbatch10_work ((lower(index_value)));

    ELSIF p_index_type = 'function_index' THEN
        CREATE INDEX idx_update_microbatch10_function
        ON lab4.update_microbatch10_work (lab4.update_microbatch10_function_key(index_value));
    END IF;

    ANALYZE lab4.update_microbatch10_work;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_microbatch10(
    p_index_type text,
    p_rows_base bigint,
    p_runs int,
    p_chunk_count int,
    p_chunk_size int
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run int;
    v_chunk int;
    v_started_at timestamptz;
    v_finished_at timestamptz;
    v_from bigint;
    v_to bigint;
    v_affected bigint;
    v_total_affected bigint;
    v_max_start bigint;
BEGIN
    IF p_rows_base < p_chunk_size THEN
        RAISE EXCEPTION 'rows_base must be >= chunk_size';
    END IF;

    v_max_start := p_rows_base - p_chunk_size + 1;

    PERFORM setseed(0.42);

    FOR v_run IN 1..p_runs LOOP
        v_total_affected := 0;
        v_started_at := clock_timestamp();

        FOR v_chunk IN 1..p_chunk_count LOOP
            v_from := floor(random() * v_max_start)::bigint + 1;
            v_to := v_from + p_chunk_size - 1;

            IF p_index_type = 'unique_btree' THEN
                UPDATE lab4.update_microbatch10_work
                SET unique_value = -1 * (lookup_id * 1000000 + v_run * 1000 + v_chunk)
                WHERE lookup_id BETWEEN v_from AND v_to;
            ELSE
                UPDATE lab4.update_microbatch10_work
                SET index_value = md5(lookup_id::text || ':' || v_run::text || ':' || v_chunk::text)
                WHERE lookup_id BETWEEN v_from AND v_to;
            END IF;

            GET DIAGNOSTICS v_affected = ROW_COUNT;
            v_total_affected := v_total_affected + v_affected;
        END LOOP;

        v_finished_at := clock_timestamp();

        INSERT INTO lab4.update_microbatch10_measurements (
            index_type,
            rows_base,
            run_no,
            chunk_count,
            chunk_size,
            total_affected_rows,
            elapsed_ms
        )
        VALUES (
            p_index_type,
            p_rows_base,
            v_run,
            p_chunk_count,
            p_chunk_size,
            v_total_affected,
            EXTRACT(EPOCH FROM (v_finished_at - v_started_at)) * 1000
        );
    END LOOP;
END;
$$;

\echo '=== UPDATE micro-batch 100 x 10 rows ==='

DO $$
DECLARE
    v_rows bigint;
    v_index_type text;
BEGIN
    FOREACH v_rows IN ARRAY ARRAY[
        10::bigint,
        25::bigint,
        50::bigint,
        100::bigint,
        250::bigint,
        500::bigint,
        1000::bigint,
        2500::bigint,
        5000::bigint,
        10000::bigint,
        25000::bigint,
        50000::bigint,
        100000::bigint,
        250000::bigint,
        500000::bigint
    ]
    LOOP
        FOREACH v_index_type IN ARRAY ARRAY[
            'no_lookup_index',
            'no_extra_index',
            'simple_btree',
            'unique_btree',
            'expression_index',
            'function_index'
        ]
        LOOP
            RAISE NOTICE 'UPDATE microbatch10 size %, index %', v_rows, v_index_type;

            PERFORM lab4.fill_update_microbatch10_table(v_rows);
            PERFORM lab4.apply_update_microbatch10_index(v_index_type);
            PERFORM lab4.measure_update_microbatch10(v_index_type, v_rows, 5, 100, 10);

            DROP TABLE IF EXISTS lab4.update_microbatch10_work;
        END LOOP;
    END LOOP;
END $$;

\echo '=== UPDATE micro-batch summary ==='

SELECT
    index_type,
    rows_base,
    count(*) AS runs,
    min(chunk_count) AS chunk_count_min,
    max(chunk_count) AS chunk_count_max,
    min(chunk_size) AS chunk_size_min,
    max(chunk_size) AS chunk_size_max,
    min(total_affected_rows) AS affected_min,
    max(total_affected_rows) AS affected_max,
    round(avg(elapsed_ms), 6) AS avg_total_elapsed_ms,
    round(min(elapsed_ms), 6) AS min_total_elapsed_ms,
    round(max(elapsed_ms), 6) AS max_total_elapsed_ms,
    round(stddev_samp(elapsed_ms), 6) AS stddev_total_elapsed_ms,
    round(avg(elapsed_ms / NULLIF(total_affected_rows, 0)), 9) AS avg_elapsed_ms_per_row
FROM lab4.update_microbatch10_measurements
GROUP BY index_type, rows_base
ORDER BY rows_base, index_type;

\echo '=== UPDATE micro-batch affected rows check ==='

SELECT
    index_type,
    rows_base,
    min(total_affected_rows) AS affected_min,
    max(total_affected_rows) AS affected_max,
    CASE
        WHEN min(total_affected_rows) = 1000
         AND max(total_affected_rows) = 1000
        THEN 'OK'
        ELSE 'FAIL'
    END AS check_result
FROM lab4.update_microbatch10_measurements
GROUP BY index_type, rows_base
ORDER BY rows_base, index_type;

\echo '=== EXPLAIN no_lookup_index control ==='

SELECT lab4.fill_update_microbatch10_table(500000);

EXPLAIN (ANALYZE, BUFFERS, TIMING)
UPDATE lab4.update_microbatch10_work
SET index_value = md5(lookup_id::text || ':explain')
WHERE lookup_id BETWEEN 499991 AND 500000;

DROP TABLE IF EXISTS lab4.update_microbatch10_work;

\echo '=== UPDATE micro-batch done ==='
