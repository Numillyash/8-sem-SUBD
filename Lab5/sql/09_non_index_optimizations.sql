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

ANALYZE documents;
ANALYZE document_operations;

SELECT 'Q2 original without optimization indexes' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
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
    d.internal_department;


SELECT 'Q2 rewritten: filter and aggregate operations before join' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH filtered_operations AS
(
    SELECT
        o.document_number,
        count(*) AS operation_count
    FROM document_operations AS o
    WHERE o.employee_name = 'Сотрудник_В'
      AND o.change_date >= TIMESTAMP '2024-06-01 00:00:00'
      AND o.change_date <  TIMESTAMP '2024-09-01 00:00:00'
    GROUP BY
        o.document_number
)
SELECT
    d.responsible_employee,
    d.internal_department,
    sum(fo.operation_count) AS operations_count
FROM filtered_operations AS fo
JOIN documents AS d
    ON d.document_number = fo.document_number
WHERE d.secrecy_level IS NOT NULL
GROUP BY
    d.responsible_employee,
    d.internal_department
ORDER BY
    operations_count DESC,
    d.responsible_employee,
    d.internal_department;


SELECT 'Q3 original without optimization indexes' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
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
    d.internal_department;


SELECT 'Q3 rewritten: explicit set of changed documents before join' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH changed_documents AS MATERIALIZED
(
    SELECT DISTINCT
        o.document_number
    FROM document_operations AS o
    WHERE o.operation_description = 'Изменение срока действия'
      AND o.change_date >= TIMESTAMP '2024-01-01 00:00:00'
      AND o.change_date <  TIMESTAMP '2025-01-01 00:00:00'
)
SELECT
    d.internal_department,
    count(*) AS changed_documents
FROM documents AS d
JOIN changed_documents AS c
    ON c.document_number = d.document_number
WHERE d.secrecy_level IS NULL
GROUP BY
    d.internal_department
ORDER BY
    changed_documents DESC,
    d.internal_department;

ROLLBACK;

SELECT 'После ROLLBACK оптимизационные индексы должны остаться на месте' AS note;

SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE tablename IN ('documents', 'document_operations')
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
