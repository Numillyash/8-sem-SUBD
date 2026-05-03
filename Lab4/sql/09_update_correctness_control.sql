-- Контроль корректности серии UPDATE для графика обновления одной записи.
-- Запрос выполняется после 08_methodical_completion.sql.
-- Если min/max affected_rows равны 1, каждый UPDATE действительно затронул ровно одну строку.

SELECT
    index_type,
    count(DISTINCT rows_before) AS tested_table_sizes,
    count(*) AS total_update_runs,
    min(affected_rows) AS affected_rows_min,
    max(affected_rows) AS affected_rows_max,
    CASE
        WHEN min(affected_rows) = 1 AND max(affected_rows) = 1
        THEN 'OK: every UPDATE affected exactly one row'
        ELSE 'CHECK: some UPDATE affected unexpected number of rows'
    END AS check_result
FROM lab4.method_series_measurements
WHERE operation_name = 'update_one_random_row'
GROUP BY index_type
ORDER BY
    CASE index_type
        WHEN 'no_index' THEN 1
        WHEN 'simple_btree' THEN 2
        WHEN 'unique_btree' THEN 3
        WHEN 'expression_index' THEN 4
        WHEN 'function_index' THEN 5
        ELSE 6
    END;
