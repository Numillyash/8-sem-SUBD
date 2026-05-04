\encoding UTF8
\pset pager off
\timing on

DROP TABLE IF EXISTS lab5_measurements_summary;

CREATE TABLE lab5_measurements_summary AS
WITH summary AS
(
    SELECT
        query_name,
        stage,
        avg(execution_ms) AS avg_execution_ms,
        min(execution_ms) AS min_execution_ms,
        max(execution_ms) AS max_execution_ms,
        stddev_samp(execution_ms) AS stddev_execution_ms
    FROM lab5_measurements
    GROUP BY query_name, stage
),
joined AS
(
    SELECT
        b.query_name,
        b.avg_execution_ms AS baseline_avg_ms,
        o.avg_execution_ms AS optimized_avg_ms,
        b.min_execution_ms AS baseline_min_ms,
        b.max_execution_ms AS baseline_max_ms,
        o.min_execution_ms AS optimized_min_ms,
        o.max_execution_ms AS optimized_max_ms,
        b.stddev_execution_ms AS baseline_stddev_ms,
        o.stddev_execution_ms AS optimized_stddev_ms
    FROM summary b
    JOIN summary o
        ON o.query_name = b.query_name
    WHERE b.stage = 'baseline'
      AND o.stage = 'optimized'
)
SELECT
    query_name,
    round(baseline_avg_ms, 3) AS baseline_avg_ms,
    round(optimized_avg_ms, 3) AS optimized_avg_ms,
    round(baseline_avg_ms / optimized_avg_ms, 3) AS speedup_ratio,
    round((baseline_avg_ms - optimized_avg_ms) / baseline_avg_ms * 100, 2) AS improvement_percent,
    round(baseline_min_ms, 3) AS baseline_min_ms,
    round(baseline_max_ms, 3) AS baseline_max_ms,
    round(optimized_min_ms, 3) AS optimized_min_ms,
    round(optimized_max_ms, 3) AS optimized_max_ms,
    round(baseline_stddev_ms, 3) AS baseline_stddev_ms,
    round(optimized_stddev_ms, 3) AS optimized_stddev_ms
FROM joined
ORDER BY query_name;

SELECT * FROM lab5_measurements_summary;

\copy lab5_measurements TO 'report/lab5_measurements_detail.csv' WITH CSV HEADER
\copy lab5_measurements_summary TO 'report/lab5_measurements_summary.csv' WITH CSV HEADER
