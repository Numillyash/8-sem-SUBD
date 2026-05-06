\pset pager off
\timing on

SET search_path = lab4, public;
SET jit = off;
SET max_parallel_workers_per_gather = 0;

DROP TABLE IF EXISTS lab4.update_no_lookup_index_measurements;
DROP TABLE IF EXISTS lab4.update_no_lookup_index_work;

CREATE TABLE lab4.update_no_lookup_index_measurements (
    rows_base bigint NOT NULL,
    run_no int NOT NULL,
    batch_size bigint NOT NULL,
    affected_rows bigint NOT NULL,
    elapsed_ms numeric(18,6) NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.fill_update_no_lookup_index_table(p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DROP TABLE IF EXISTS lab4.update_no_lookup_index_work;

    CREATE TABLE lab4.update_no_lookup_index_work (
        row_id bigint NOT NULL,
        lookup_id bigint NOT NULL,
        payload text NOT NULL,
        updated_payload text NOT NULL DEFAULT '',
        filler text NOT NULL
    );

    INSERT INTO lab4.update_no_lookup_index_work (
        row_id,
        lookup_id,
        payload,
        filler
    )
    SELECT
        g AS row_id,
        g AS lookup_id,
        md5(g::text) AS payload,
        repeat('x', 64) AS filler
    FROM generate_series(1, p_rows) AS g;

    ANALYZE lab4.update_no_lookup_index_work;
END;
$$;

CREATE OR REPLACE FUNCTION lab4.measure_update_no_lookup_index(
    p_rows_base bigint,
    p_batch_size bigint,
    p_runs int
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run int;
    v_started_at timestamptz;
    v_finished_at timestamptz;
    v_affected bigint;
    v_from bigint;
    v_to bigint;
BEGIN
    FOR v_run IN 1..p_runs LOOP
        /*
          Берем диапазон ближе к концу таблицы.
          Для таблицы без индекса это заставляет PostgreSQL просмотреть практически всю таблицу.
        */
        v_to := p_rows_base - ((v_run - 1) * p_batch_size);
        v_from := v_to - p_batch_size + 1;

        v_started_at := clock_timestamp();

        UPDATE lab4.update_no_lookup_index_work
        SET updated_payload = md5(payload || ':' || v_run::text)
        WHERE lookup_id BETWEEN v_from AND v_to;

        GET DIAGNOSTICS v_affected = ROW_COUNT;

        v_finished_at := clock_timestamp();

        INSERT INTO lab4.update_no_lookup_index_measurements (
            rows_base,
            run_no,
            batch_size,
            affected_rows,
            elapsed_ms
        )
        VALUES (
            p_rows_base,
            v_run,
            p_batch_size,
            v_affected,
            EXTRACT(EPOCH FROM (v_finished_at - v_started_at)) * 1000
        );
    END LOOP;
END;
$$;

\echo '=== UPDATE without lookup index: dense sizes under 1M ==='

DO $$
DECLARE
    v_rows bigint;
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
        RAISE NOTICE 'UPDATE no lookup index size %', v_rows;

        PERFORM lab4.fill_update_no_lookup_index_table(v_rows);

        PERFORM lab4.measure_update_no_lookup_index(
            v_rows,
            LEAST(1000, v_rows),
            5
        );
    END LOOP;
END $$;

\echo '=== UPDATE no lookup index summary ==='

SELECT
    rows_base,
    count(*) AS runs,
    min(batch_size) AS batch_size_min,
    max(batch_size) AS batch_size_max,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    round(avg(elapsed_ms), 6) AS avg_total_elapsed_ms,
    round(min(elapsed_ms), 6) AS min_total_elapsed_ms,
    round(max(elapsed_ms), 6) AS max_total_elapsed_ms,
    round(stddev_samp(elapsed_ms), 6) AS stddev_total_elapsed_ms,
    round(avg(elapsed_ms / NULLIF(affected_rows, 0)), 9) AS avg_elapsed_ms_per_row
FROM lab4.update_no_lookup_index_measurements
GROUP BY rows_base
ORDER BY rows_base;

\echo '=== EXPLAIN control: UPDATE without lookup index, max size ==='

EXPLAIN (ANALYZE, BUFFERS, TIMING)
UPDATE lab4.update_no_lookup_index_work
SET updated_payload = md5(payload || ':explain')
WHERE lookup_id BETWEEN 499001 AND 500000;

\echo '=== UPDATE without lookup index done ==='
