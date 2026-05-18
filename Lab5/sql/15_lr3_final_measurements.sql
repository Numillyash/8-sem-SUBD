\encoding UTF8
\pset pager off
\timing on

SET jit = off;

DROP TABLE IF EXISTS lr3_optimization_measurements;
DROP TABLE IF EXISTS lr3_optimization_summary;

CREATE TABLE lr3_optimization_measurements
(
    query_name   text NOT NULL,
    stage        text NOT NULL,
    run_number   int  NOT NULL,
    planning_ms  numeric(12, 3) NOT NULL,
    execution_ms numeric(12, 3) NOT NULL,
    measured_at  timestamp NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION lr3_measure_query
(
    p_query_name text,
    p_stage text,
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

            INSERT INTO lr3_optimization_measurements
            (
                query_name,
                stage,
                run_number,
                planning_ms,
                execution_ms
            )
            VALUES
            (
                p_query_name,
                p_stage,
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

DROP INDEX IF EXISTS idx_lr3_q1_secret_employee_partial;
DROP INDEX IF EXISTS idx_lr3_q2_documents_effective_until;
DROP INDEX IF EXISTS idx_lr3_q3_operations_operation_employee_document;
DROP INDEX IF EXISTS idx_lr3_q3_operations_document_employee;
DROP INDEX IF EXISTS idx_lr3_q3_documents_responsible_document;

ANALYZE documents;
ANALYZE document_operations;

SELECT 'STAGE 1: baseline and logical rewrites without optimization indexes' AS stage;

SELECT lr3_measure_query
(
    'Q1',
    'baseline_original',
    $Q$
    SELECT
        d.responsible_employee AS responsible_employee,
        COUNT(*) AS secret_documents_count
    FROM documents d
    WHERE d.secrecy_level = 'секретно'
    GROUP BY d.responsible_employee
    HAVING COUNT(*) > 1
    ORDER BY d.responsible_employee
    $Q$,
    5,
    1
);

SELECT lr3_measure_query
(
    'Q2',
    'baseline_extract',
    $Q$
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until IS NOT NULL
      AND EXTRACT(YEAR FROM d.effective_until)::int = 2025
      AND NOT (EXTRACT(MONTH FROM d.effective_until)::int = ANY(ARRAY[5,6,7]::int[]))
    ORDER BY d.effective_until, d.document_number
    $Q$,
    5,
    1
);

SELECT lr3_measure_query
(
    'Q2',
    'logical_rewrite_ranges',
    $Q$
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until >= DATE '2025-01-01'
      AND d.effective_until <  DATE '2026-01-01'
      AND NOT
      (
          d.effective_until >= DATE '2025-05-01'
          AND d.effective_until <  DATE '2025-08-01'
      )
    ORDER BY d.effective_until, d.document_number
    $Q$,
    5,
    1
);

SELECT lr3_measure_query
(
    'Q3',
    'baseline_double_not_exists',
    $Q$
    SELECT DISTINCT result.employee_name
    FROM
    (
        SELECT DISTINCT op.employee_name
        FROM document_operations op
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM unnest(ARRAY[
                'Создание документа',
                'Проверка документа',
                'Согласование документа'
            ]::text[]) AS possible_operation(operation_description)
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM document_operations op_check
                WHERE op_check.employee_name = op.employee_name
                  AND op_check.document_number = op.document_number
                  AND op_check.operation_description = possible_operation.operation_description
            )
        )

        UNION

        SELECT d.responsible_employee AS employee_name
        FROM documents d
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM document_operations op
            WHERE op.document_number = d.document_number
              AND op.employee_name = d.responsible_employee
        )
    ) AS result
    ORDER BY result.employee_name
    $Q$,
    5,
    1
);

SELECT lr3_measure_query
(
    'Q3',
    'logical_rewrite_group_by_having',
    $Q$
    WITH required_operations AS
    (
        SELECT *
        FROM unnest(ARRAY[
            'Создание документа',
            'Проверка документа',
            'Согласование документа'
        ]::text[]) AS r(operation_description)
    ),
    completed_operation_sets AS
    (
        SELECT
            op.employee_name,
            op.document_number
        FROM document_operations op
        JOIN required_operations r
            ON r.operation_description = op.operation_description
        GROUP BY
            op.employee_name,
            op.document_number
        HAVING COUNT(DISTINCT op.operation_description) =
               (SELECT COUNT(*) FROM required_operations)
    ),
    responsible_without_own_operations AS
    (
        SELECT d.responsible_employee AS employee_name
        FROM documents d
        LEFT JOIN document_operations op
            ON op.document_number = d.document_number
           AND op.employee_name = d.responsible_employee
        WHERE op.document_number IS NULL
    )
    SELECT DISTINCT employee_name
    FROM
    (
        SELECT employee_name
        FROM completed_operation_sets

        UNION

        SELECT employee_name
        FROM responsible_without_own_operations
    ) AS result
    ORDER BY employee_name
    $Q$,
    5,
    1
);

CREATE INDEX idx_lr3_q1_secret_employee_partial
ON documents
(
    responsible_employee
)
WHERE secrecy_level = 'секретно';

CREATE INDEX idx_lr3_q2_documents_effective_until
ON documents
(
    effective_until,
    document_number
)
INCLUDE
(
    responsible_employee
)
WHERE effective_until IS NOT NULL;

CREATE INDEX idx_lr3_q3_operations_operation_employee_document
ON document_operations
(
    operation_description,
    employee_name,
    document_number
);

CREATE INDEX idx_lr3_q3_operations_document_employee
ON document_operations
(
    document_number,
    employee_name
);

CREATE INDEX idx_lr3_q3_documents_responsible_document
ON documents
(
    responsible_employee,
    document_number
);

ANALYZE documents;
ANALYZE document_operations;

SELECT 'STAGE 2: optimized with indexes' AS stage;

SELECT lr3_measure_query
(
    'Q1',
    'optimized_index',
    $Q$
    SELECT
        d.responsible_employee AS responsible_employee,
        COUNT(*) AS secret_documents_count
    FROM documents d
    WHERE d.secrecy_level = 'секретно'
    GROUP BY d.responsible_employee
    HAVING COUNT(*) > 1
    ORDER BY d.responsible_employee
    $Q$,
    5,
    1
);

SELECT lr3_measure_query
(
    'Q2',
    'logical_rewrite_plus_index',
    $Q$
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until >= DATE '2025-01-01'
      AND d.effective_until <  DATE '2026-01-01'
      AND NOT
      (
          d.effective_until >= DATE '2025-05-01'
          AND d.effective_until <  DATE '2025-08-01'
      )
    ORDER BY d.effective_until, d.document_number
    $Q$,
    5,
    1
);

SELECT lr3_measure_query
(
    'Q3',
    'logical_rewrite_plus_indexes',
    $Q$
    WITH required_operations AS
    (
        SELECT *
        FROM unnest(ARRAY[
            'Создание документа',
            'Проверка документа',
            'Согласование документа'
        ]::text[]) AS r(operation_description)
    ),
    completed_operation_sets AS
    (
        SELECT
            op.employee_name,
            op.document_number
        FROM document_operations op
        JOIN required_operations r
            ON r.operation_description = op.operation_description
        GROUP BY
            op.employee_name,
            op.document_number
        HAVING COUNT(DISTINCT op.operation_description) =
               (SELECT COUNT(*) FROM required_operations)
    ),
    responsible_without_own_operations AS
    (
        SELECT d.responsible_employee AS employee_name
        FROM documents d
        LEFT JOIN document_operations op
            ON op.document_number = d.document_number
           AND op.employee_name = d.responsible_employee
        WHERE op.document_number IS NULL
    )
    SELECT DISTINCT employee_name
    FROM
    (
        SELECT employee_name
        FROM completed_operation_sets

        UNION

        SELECT employee_name
        FROM responsible_without_own_operations
    ) AS result
    ORDER BY employee_name
    $Q$,
    5,
    1
);

SELECT
    query_name,
    stage,
    run_number,
    planning_ms,
    execution_ms
FROM lr3_optimization_measurements
ORDER BY
    query_name,
    stage,
    run_number;

CREATE TABLE lr3_optimization_summary AS
SELECT
    query_name,
    stage,
    round(avg(execution_ms), 3) AS avg_execution_ms,
    round(min(execution_ms), 3) AS min_execution_ms,
    round(max(execution_ms), 3) AS max_execution_ms,
    round(stddev_samp(execution_ms), 3) AS stddev_execution_ms
FROM lr3_optimization_measurements
GROUP BY
    query_name,
    stage
ORDER BY
    query_name,
    stage;

SELECT * FROM lr3_optimization_summary;

CREATE TABLE lr3_optimization_comparison AS
WITH s AS
(
    SELECT
        query_name,
        stage,
        avg_execution_ms
    FROM lr3_optimization_summary
)
SELECT
    b.query_name,
    b.stage AS from_stage,
    o.stage AS to_stage,
    b.avg_execution_ms AS from_avg_ms,
    o.avg_execution_ms AS to_avg_ms,
    round(b.avg_execution_ms / o.avg_execution_ms, 3) AS speedup_ratio,
    round((b.avg_execution_ms - o.avg_execution_ms) / b.avg_execution_ms * 100, 2) AS improvement_percent
FROM s b
JOIN s o
    ON o.query_name = b.query_name
WHERE
    (b.query_name = 'Q1' AND b.stage = 'baseline_original' AND o.stage = 'optimized_index')
 OR (b.query_name = 'Q2' AND b.stage = 'baseline_extract' AND o.stage = 'logical_rewrite_ranges')
 OR (b.query_name = 'Q2' AND b.stage = 'baseline_extract' AND o.stage = 'logical_rewrite_plus_index')
 OR (b.query_name = 'Q3' AND b.stage = 'baseline_double_not_exists' AND o.stage = 'logical_rewrite_group_by_having')
 OR (b.query_name = 'Q3' AND b.stage = 'baseline_double_not_exists' AND o.stage = 'logical_rewrite_plus_indexes')
ORDER BY
    b.query_name,
    to_stage;

SELECT * FROM lr3_optimization_comparison;

\copy lr3_optimization_measurements TO 'report/lr3_optimization_measurements_detail.csv' WITH CSV HEADER
\copy lr3_optimization_summary TO 'report/lr3_optimization_summary.csv' WITH CSV HEADER
\copy lr3_optimization_comparison TO 'report/lr3_optimization_comparison.csv' WITH CSV HEADER
