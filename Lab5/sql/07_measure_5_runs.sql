\encoding UTF8
\pset pager off
\timing on

SET jit = off;

DROP TABLE IF EXISTS lab5_measurements;

CREATE TABLE lab5_measurements
(
    stage        text NOT NULL,
    query_name   text NOT NULL,
    run_number   int  NOT NULL,
    planning_ms  numeric(12, 3) NOT NULL,
    execution_ms numeric(12, 3) NOT NULL,
    measured_at  timestamp NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION lab5_measure_query
(
    p_stage text,
    p_query_name text,
    p_query_sql text,
    p_runs int,
    p_warmups int DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    i int;
    v_plan json;
    v_planning_ms numeric(12, 3);
    v_execution_ms numeric(12, 3);
BEGIN
    FOR i IN 1..p_warmups LOOP
        FOR v_plan IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_query_sql
        LOOP
            NULL;
        END LOOP;
    END LOOP;

    FOR i IN 1..p_runs LOOP
        FOR v_plan IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_query_sql
        LOOP
            v_planning_ms := (v_plan->0->>'Planning Time')::numeric(12, 3);
            v_execution_ms := (v_plan->0->>'Execution Time')::numeric(12, 3);

            INSERT INTO lab5_measurements
            (
                stage,
                query_name,
                run_number,
                planning_ms,
                execution_ms
            )
            VALUES
            (
                p_stage,
                p_query_name,
                i,
                v_planning_ms,
                v_execution_ms
            );
        END LOOP;
    END LOOP;
END;
$$;

DROP INDEX IF EXISTS idx_documents_q1_secret_department_until;
DROP INDEX IF EXISTS idx_operations_q2_employee_date_document;
DROP INDEX IF EXISTS idx_operations_q3_operation_date_document;
DROP INDEX IF EXISTS idx_documents_q3_public_document_department;
DROP INDEX IF EXISTS idx_documents_q2_secret_document_employee_department;

ANALYZE documents;
ANALYZE document_operations;

SELECT 'BASELINE: индексы оптимизации удалены' AS stage;

SELECT lab5_measure_query
(
    'baseline',
    'Q1',
    $Q$
    SELECT
        document_number,
        document_type,
        responsible_employee,
        internal_department,
        effective_from,
        effective_until,
        secrecy_level
    FROM documents
    WHERE internal_department IN ('Подразделение_3', 'Подразделение_7', 'Подразделение_13')
      AND secrecy_level = 'секретно'
      AND effective_until IS NOT NULL
      AND effective_until >= DATE '2024-01-01'
    ORDER BY effective_until, document_number
    $Q$,
    5,
    1
);

SELECT lab5_measure_query
(
    'baseline',
    'Q2',
    $Q$
    SELECT
        d.responsible_employee,
        d.internal_department,
        count(*) AS operations_count
    FROM document_operations AS o
    JOIN documents AS d
        ON d.document_number = o.document_number
    WHERE o.employee_name = 'Сотрудник_В'
      AND o.change_date >= TIMESTAMP '2024-06-01 00:00:00'
      AND o.change_date <  TIMESTAMP '2024-09-01 00:00:00'
      AND d.secrecy_level IS NOT NULL
    GROUP BY
        d.responsible_employee,
        d.internal_department
    ORDER BY
        operations_count DESC,
        d.responsible_employee,
        d.internal_department
    $Q$,
    5,
    1
);

SELECT lab5_measure_query
(
    'baseline',
    'Q3',
    $Q$
    SELECT
        d.internal_department,
        count(*) AS changed_documents
    FROM documents AS d
    WHERE d.secrecy_level IS NULL
      AND EXISTS
      (
          SELECT 1
          FROM document_operations AS o
          WHERE o.document_number = d.document_number
            AND o.operation_description = 'Изменение срока действия'
            AND o.change_date >= TIMESTAMP '2024-01-01 00:00:00'
            AND o.change_date <  TIMESTAMP '2025-01-01 00:00:00'
      )
    GROUP BY
        d.internal_department
    ORDER BY
        changed_documents DESC,
        d.internal_department
    $Q$,
    5,
    1
);

CREATE INDEX idx_documents_q1_secret_department_until
ON documents
(
    secrecy_level,
    internal_department,
    effective_until,
    document_number
)
INCLUDE
(
    document_type,
    responsible_employee
)
WHERE secrecy_level IS NOT NULL
  AND effective_until IS NOT NULL;

CREATE INDEX idx_operations_q2_employee_date_document
ON document_operations
(
    employee_name,
    change_date,
    document_number
);

CREATE INDEX idx_operations_q3_operation_date_document
ON document_operations
(
    operation_description,
    change_date,
    document_number
);

CREATE INDEX idx_documents_q3_public_document_department
ON documents
(
    document_number,
    internal_department
)
WHERE secrecy_level IS NULL;

CREATE INDEX idx_documents_q2_secret_document_employee_department
ON documents
(
    document_number,
    responsible_employee,
    internal_department
)
WHERE secrecy_level IS NOT NULL;

ANALYZE documents;
ANALYZE document_operations;

SELECT 'OPTIMIZED: индексы оптимизации созданы' AS stage;

SELECT lab5_measure_query
(
    'optimized',
    'Q1',
    $Q$
    SELECT
        document_number,
        document_type,
        responsible_employee,
        internal_department,
        effective_from,
        effective_until,
        secrecy_level
    FROM documents
    WHERE internal_department IN ('Подразделение_3', 'Подразделение_7', 'Подразделение_13')
      AND secrecy_level = 'секретно'
      AND effective_until IS NOT NULL
      AND effective_until >= DATE '2024-01-01'
    ORDER BY effective_until, document_number
    $Q$,
    5,
    1
);

SELECT lab5_measure_query
(
    'optimized',
    'Q2',
    $Q$
    SELECT
        d.responsible_employee,
        d.internal_department,
        count(*) AS operations_count
    FROM document_operations AS o
    JOIN documents AS d
        ON d.document_number = o.document_number
    WHERE o.employee_name = 'Сотрудник_В'
      AND o.change_date >= TIMESTAMP '2024-06-01 00:00:00'
      AND o.change_date <  TIMESTAMP '2024-09-01 00:00:00'
      AND d.secrecy_level IS NOT NULL
    GROUP BY
        d.responsible_employee,
        d.internal_department
    ORDER BY
        operations_count DESC,
        d.responsible_employee,
        d.internal_department
    $Q$,
    5,
    1
);

SELECT lab5_measure_query
(
    'optimized',
    'Q3',
    $Q$
    SELECT
        d.internal_department,
        count(*) AS changed_documents
    FROM documents AS d
    WHERE d.secrecy_level IS NULL
      AND EXISTS
      (
          SELECT 1
          FROM document_operations AS o
          WHERE o.document_number = d.document_number
            AND o.operation_description = 'Изменение срока действия'
            AND o.change_date >= TIMESTAMP '2024-01-01 00:00:00'
            AND o.change_date <  TIMESTAMP '2025-01-01 00:00:00'
      )
    GROUP BY
        d.internal_department
    ORDER BY
        changed_documents DESC,
        d.internal_department
    $Q$,
    5,
    1
);

SELECT
    stage,
    query_name,
    run_number,
    planning_ms,
    execution_ms
FROM lab5_measurements
ORDER BY
    query_name,
    stage,
    run_number;

SELECT
    query_name,
    stage,
    round(avg(execution_ms), 3) AS avg_execution_ms,
    round(min(execution_ms), 3) AS min_execution_ms,
    round(max(execution_ms), 3) AS max_execution_ms,
    round(stddev_samp(execution_ms), 3) AS stddev_execution_ms
FROM lab5_measurements
GROUP BY query_name, stage
ORDER BY query_name, stage;

WITH summary AS
(
    SELECT
        query_name,
        stage,
        avg(execution_ms) AS avg_execution_ms
    FROM lab5_measurements
    GROUP BY query_name, stage
),
joined AS
(
    SELECT
        b.query_name,
        b.avg_execution_ms AS baseline_avg_ms,
        o.avg_execution_ms AS optimized_avg_ms
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
    round((baseline_avg_ms - optimized_avg_ms) / baseline_avg_ms * 100, 2) AS improvement_percent
FROM joined
ORDER BY query_name;

\copy lab5_measurements TO 'report/lab5_measurements_detail.csv' WITH CSV HEADER;

\copy (
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
    ORDER BY query_name
) TO 'report/lab5_measurements_summary.csv' WITH CSV HEADER;
