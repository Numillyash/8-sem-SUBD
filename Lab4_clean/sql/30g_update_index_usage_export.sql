\pset pager off
\timing on

\echo '=== 30g export update index usage ==='

DROP VIEW IF EXISTS lab4.v_30_update_index_usage_raw;
DROP VIEW IF EXISTS lab4.v_30_update_index_usage_aggregated;
DROP VIEW IF EXISTS lab4.v_30_update_index_usage_checks;
DROP VIEW IF EXISTS lab4.v_30_update_index_usage_explains;

CREATE VIEW lab4.v_30_update_index_usage_raw AS
SELECT *
FROM lab4.update_index_usage_measurements
ORDER BY index_type, mode, rows_base, run_no;

CREATE VIEW lab4.v_30_update_index_usage_aggregated AS
SELECT
    index_type,
    mode,
    rows_base,
    count(*) AS runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    round(avg(elapsed_ms)::numeric, 6) AS avg_total_elapsed_ms,
    round(min(elapsed_ms)::numeric, 6) AS min_total_elapsed_ms,
    round(max(elapsed_ms)::numeric, 6) AS max_total_elapsed_ms,
    round(stddev_samp(elapsed_ms)::numeric, 6) AS stddev_total_elapsed_ms,
    round(avg(elapsed_ms_per_row)::numeric, 9) AS avg_elapsed_ms_per_row
FROM lab4.update_index_usage_measurements
GROUP BY index_type, mode, rows_base
ORDER BY index_type, mode, rows_base;

CREATE VIEW lab4.v_30_update_index_usage_checks AS
SELECT
    index_type,
    mode,
    rows_base,
    count(*) AS runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    CASE
        WHEN count(*) <> 5 THEN 'FAIL: runs must be 5'
        WHEN min(affected_rows) <> 1000 OR max(affected_rows) <> 1000
            THEN 'FAIL: affected_rows must be 1000'
        ELSE 'OK'
    END AS check_result
FROM lab4.update_index_usage_measurements
GROUP BY index_type, mode, rows_base
ORDER BY index_type, mode, rows_base;

CREATE VIEW lab4.v_30_update_index_usage_explains AS
SELECT
    index_type,
    mode,
    rows_base,
    explain_plan
FROM lab4.update_index_usage_explains
ORDER BY index_type, mode, rows_base;

\copy (SELECT * FROM lab4.v_30_update_index_usage_raw) TO 'report/30_update_index_usage_raw.csv' CSV HEADER
\copy (SELECT * FROM lab4.v_30_update_index_usage_aggregated) TO 'report/30_update_index_usage_aggregated.csv' CSV HEADER
\copy (SELECT * FROM lab4.v_30_update_index_usage_checks) TO 'report/30_update_index_usage_checks.csv' CSV HEADER
\copy (SELECT * FROM lab4.v_30_update_index_usage_explains) TO 'report/30_update_index_usage_explains.csv' CSV HEADER

\echo 'exported:'
\echo '  report/30_update_index_usage_raw.csv'
\echo '  report/30_update_index_usage_aggregated.csv'
\echo '  report/30_update_index_usage_checks.csv'
\echo '  report/30_update_index_usage_explains.csv'
