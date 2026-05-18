\encoding UTF8
\pset pager off
\timing on

SET jit = off;

DROP TABLE IF EXISTS document_operations_part CASCADE;

CREATE TABLE document_operations_part
(
    employee_name          text NOT NULL,
    document_number        text NOT NULL,
    change_date            timestamp NOT NULL,
    operation_description  text NOT NULL
)
PARTITION BY RANGE (change_date);

CREATE TABLE document_operations_part_2024_q1
PARTITION OF document_operations_part
FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE document_operations_part_2024_q2
PARTITION OF document_operations_part
FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE document_operations_part_2024_q3
PARTITION OF document_operations_part
FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE document_operations_part_2024_q4
PARTITION OF document_operations_part
FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

CREATE TABLE document_operations_part_2025_q1
PARTITION OF document_operations_part
FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');

CREATE TABLE document_operations_part_2025_q2
PARTITION OF document_operations_part
FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');

CREATE TABLE document_operations_part_2025_q3
PARTITION OF document_operations_part
FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');

CREATE TABLE document_operations_part_2025_q4
PARTITION OF document_operations_part
FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');

CREATE TABLE document_operations_part_default
PARTITION OF document_operations_part
DEFAULT;

INSERT INTO document_operations_part
(
    employee_name,
    document_number,
    change_date,
    operation_description
)
SELECT
    employee_name,
    document_number,
    change_date,
    operation_description
FROM document_operations;

ANALYZE document_operations_part;
ANALYZE documents;

SELECT 'Размер и распределение секционированной таблицы' AS info;

SELECT
    tableoid::regclass AS partition_name,
    count(*) AS row_count
FROM document_operations_part
GROUP BY tableoid::regclass
ORDER BY 1;


SELECT 'Q2 on partitioned table: date pruning should read only needed partitions' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.responsible_employee,
    d.internal_department,
    count(*) AS operations_count
FROM document_operations_part AS o
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


SELECT 'Q3 on partitioned table: date pruning should read only 2024 partitions' AS test_name;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.internal_department,
    count(*) AS changed_documents
FROM documents AS d
WHERE d.secrecy_level IS NULL
  AND EXISTS
  (
      SELECT 1
      FROM document_operations_part AS o
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
