\encoding UTF8
\pset pager off
\timing on

SET jit = off;

SELECT 'Q1. Выборка секретных действующих документов по подразделениям и сроку действия' AS query_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
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
ORDER BY effective_until, document_number;


SELECT 'Q2. Агрегация операций сотрудника за период с соединением документов' AS query_name;

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


SELECT 'Q3. Поиск несекретных документов, по которым были изменения срока действия' AS query_name;

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
