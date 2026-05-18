\encoding UTF8
\pset pager off
\timing on

SET jit = off;

DROP MATERIALIZED VIEW IF EXISTS mv_employee_document_month_operations;
DROP MATERIALIZED VIEW IF EXISTS mv_changed_documents_year;

CREATE MATERIALIZED VIEW mv_employee_document_month_operations AS
SELECT
    employee_name,
    date_trunc('month', change_date)::date AS month_start,
    document_number,
    count(*) AS operation_count
FROM document_operations
GROUP BY
    employee_name,
    date_trunc('month', change_date)::date,
    document_number;

CREATE MATERIALIZED VIEW mv_changed_documents_year AS
SELECT
    date_trunc('year', change_date)::date AS year_start,
    document_number,
    count(*) AS changed_operations_count
FROM document_operations
WHERE operation_description = 'Изменение срока действия'
GROUP BY
    date_trunc('year', change_date)::date,
    document_number;

ANALYZE mv_employee_document_month_operations;
ANALYZE mv_changed_documents_year;

SELECT 'Размеры материализованных представлений' AS info;

SELECT
    'mv_employee_document_month_operations' AS relation_name,
    count(*) AS row_count
FROM mv_employee_document_month_operations
UNION ALL
SELECT
    'mv_changed_documents_year' AS relation_name,
    count(*) AS row_count
FROM mv_changed_documents_year;


SELECT 'Q2 using materialized monthly operation counts' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.responsible_employee,
    d.internal_department,
    sum(m.operation_count) AS operations_count
FROM mv_employee_document_month_operations AS m
JOIN documents AS d
    ON d.document_number = m.document_number
WHERE m.employee_name = 'Сотрудник_В'
  AND m.month_start >= DATE '2024-06-01'
  AND m.month_start <  DATE '2024-09-01'
  AND d.secrecy_level IS NOT NULL
GROUP BY
    d.responsible_employee,
    d.internal_department
ORDER BY
    operations_count DESC,
    d.responsible_employee,
    d.internal_department;


SELECT 'Q3 using materialized changed-document set' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.internal_department,
    count(*) AS changed_documents
FROM documents AS d
JOIN mv_changed_documents_year AS m
    ON m.document_number = d.document_number
WHERE d.secrecy_level IS NULL
  AND m.year_start = DATE '2024-01-01'
GROUP BY
    d.internal_department
ORDER BY
    changed_documents DESC,
    d.internal_department;
