\pset pager off
\timing on

SET search_path = lab4, public;
SET jit = off;
SET max_parallel_workers_per_gather = 0;
SET enable_partition_pruning = on;

DROP TABLE IF EXISTS lab4.partition_search_only_measurements;

CREATE TABLE lab4.partition_search_only_measurements (
    test_name text NOT NULL,
    table_name text NOT NULL,
    run_no int NOT NULL,
    rows_found bigint NOT NULL,
    elapsed_ms numeric(18,6) NOT NULL
);

CREATE OR REPLACE FUNCTION lab4.measure_partition_search_only(
    p_test_name text,
    p_table_name text,
    p_date_from date,
    p_date_to date,
    p_runs int
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_run int;
    v_started_at timestamptz;
    v_finished_at timestamptz;
    v_rows_found bigint;
BEGIN
    FOR v_run IN 1..p_runs LOOP
        v_started_at := clock_timestamp();

        EXECUTE format(
            'SELECT count(*) FROM lab4.%I WHERE order_date >= $1 AND order_date < $2',
            p_table_name
        )
        INTO v_rows_found
        USING p_date_from, p_date_to;

        v_finished_at := clock_timestamp();

        INSERT INTO lab4.partition_search_only_measurements (
            test_name,
            table_name,
            run_no,
            rows_found,
            elapsed_ms
        )
        VALUES (
            p_test_name,
            p_table_name,
            v_run,
            v_rows_found,
            EXTRACT(EPOCH FROM (v_finished_at - v_started_at)) * 1000
        );
    END LOOP;
END;
$$;

\echo '=== Search-only measurements: Q1 ==='
SELECT lab4.measure_partition_search_only('q1_search_only', 'orders_plain', DATE '2024-01-01', DATE '2024-04-01', 20);
SELECT lab4.measure_partition_search_only('q1_search_only', 'orders_partitioned', DATE '2024-01-01', DATE '2024-04-01', 20);

\echo '=== Search-only measurements: Q2 ==='
SELECT lab4.measure_partition_search_only('q2_search_only', 'orders_plain', DATE '2024-04-01', DATE '2024-07-01', 20);
SELECT lab4.measure_partition_search_only('q2_search_only', 'orders_partitioned', DATE '2024-04-01', DATE '2024-07-01', 20);

\echo '=== Search-only measurements: Q1+Q2 ==='
SELECT lab4.measure_partition_search_only('q1_q2_search_only', 'orders_plain', DATE '2024-01-01', DATE '2024-07-01', 20);
SELECT lab4.measure_partition_search_only('q1_q2_search_only', 'orders_partitioned', DATE '2024-01-01', DATE '2024-07-01', 20);

\echo '=== Search-only summary ==='
WITH summary AS (
    SELECT
        test_name,
        table_name,
        count(*) AS runs,
        min(rows_found) AS rows_found_min,
        max(rows_found) AS rows_found_max,
        round(avg(elapsed_ms), 3) AS avg_elapsed_ms,
        round(min(elapsed_ms), 3) AS min_elapsed_ms,
        round(max(elapsed_ms), 3) AS max_elapsed_ms,
        round(stddev_samp(elapsed_ms), 3) AS stddev_elapsed_ms
    FROM lab4.partition_search_only_measurements
    GROUP BY test_name, table_name
)
SELECT *
FROM summary
ORDER BY test_name, table_name;

\echo '=== Search-only speedup ==='
WITH summary AS (
    SELECT
        test_name,
        table_name,
        avg(elapsed_ms) AS avg_elapsed_ms
    FROM lab4.partition_search_only_measurements
    GROUP BY test_name, table_name
),
pairs AS (
    SELECT
        p.test_name,
        p.avg_elapsed_ms AS plain_avg_ms,
        q.avg_elapsed_ms AS partitioned_avg_ms,
        p.avg_elapsed_ms / NULLIF(q.avg_elapsed_ms, 0) AS speedup
    FROM summary p
    JOIN summary q ON q.test_name = p.test_name
    WHERE p.table_name = 'orders_plain'
      AND q.table_name = 'orders_partitioned'
)
SELECT
    test_name,
    round(plain_avg_ms, 3) AS plain_avg_ms,
    round(partitioned_avg_ms, 3) AS partitioned_avg_ms,
    round(speedup, 3) AS speedup
FROM pairs
ORDER BY test_name;

\echo '=== Search-only measurements done ==='
