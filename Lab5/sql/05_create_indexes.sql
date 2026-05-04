\encoding UTF8
\pset pager off
\timing on

CREATE INDEX IF NOT EXISTS idx_documents_q1_secret_department_until
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

CREATE INDEX IF NOT EXISTS idx_operations_q2_employee_date_document
ON document_operations
(
    employee_name,
    change_date,
    document_number
);

CREATE INDEX IF NOT EXISTS idx_operations_q3_operation_date_document
ON document_operations
(
    operation_description,
    change_date,
    document_number
);

CREATE INDEX IF NOT EXISTS idx_documents_q3_public_document_department
ON documents
(
    document_number,
    internal_department
)
WHERE secrecy_level IS NULL;

CREATE INDEX IF NOT EXISTS idx_documents_q2_secret_document_employee_department
ON documents
(
    document_number,
    responsible_employee,
    internal_department
)
WHERE secrecy_level IS NOT NULL;

ANALYZE documents;
ANALYZE document_operations;

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename IN ('documents', 'document_operations')
ORDER BY tablename, indexname;
