\encoding UTF8
\pset pager off
\timing on

SET jit = off;

BEGIN;

DROP INDEX IF EXISTS idx_documents_q1_secret_department_until;
DROP INDEX IF EXISTS idx_operations_q2_employee_date_document;
DROP INDEX IF EXISTS idx_operations_q3_operation_date_document;
DROP INDEX IF EXISTS idx_documents_q3_public_document_department;
DROP INDEX IF EXISTS idx_documents_q2_secret_document_employee_department;

DROP INDEX IF EXISTS idx_lr3_q1_documents_secrecy_employee;
DROP INDEX IF EXISTS idx_lr3_q1_secret_employee_partial;
DROP INDEX IF EXISTS idx_lr3_q2_documents_effective_until;
DROP INDEX IF EXISTS idx_lr3_q3_operations_operation_employee_document;
DROP INDEX IF EXISTS idx_lr3_q3_operations_document_employee;
DROP INDEX IF EXISTS idx_lr3_q3_documents_responsible_document;

ANALYZE documents;
ANALYZE document_operations;

SELECT 'LR3 Q1 baseline: employees responsible for more than one secret document' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.responsible_employee AS responsible_employee,
    COUNT(*) AS secret_documents_count
FROM documents d
WHERE d.secrecy_level = 'секретно'
GROUP BY d.responsible_employee
HAVING COUNT(*) > 1
ORDER BY d.responsible_employee;


SELECT 'LR3 Q2 baseline: EXTRACT year and month from effective_until' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.document_number,
    d.responsible_employee,
    d.effective_until,
    EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
FROM documents d
WHERE d.effective_until IS NOT NULL
  AND EXTRACT(YEAR FROM d.effective_until)::int = 2025
  AND NOT (EXTRACT(MONTH FROM d.effective_until)::int = ANY(ARRAY[5,6,7]::int[]))
ORDER BY d.effective_until, d.document_number;


SELECT 'LR3 Q2 rewritten: date ranges instead of EXTRACT in WHERE' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
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
ORDER BY d.effective_until, d.document_number;


SELECT 'LR3 Q3 baseline: double NOT EXISTS relational division' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
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
ORDER BY result.employee_name;


SELECT 'LR3 Q3 rewritten: GROUP BY HAVING instead of double NOT EXISTS' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
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
ORDER BY employee_name;

ROLLBACK;
