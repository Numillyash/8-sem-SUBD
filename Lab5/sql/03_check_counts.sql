\encoding UTF8
\pset pager off
\timing on

SELECT
    'documents' AS relation_name,
    count(*) AS row_count
FROM documents
UNION ALL
SELECT
    'document_operations' AS relation_name,
    count(*) AS row_count
FROM document_operations;

SELECT
    relname AS relation_name,
    pg_size_pretty(pg_relation_size(oid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size_with_indexes
FROM pg_class
WHERE relname IN ('documents', 'document_operations')
ORDER BY relname;

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename IN ('documents', 'document_operations')
ORDER BY tablename, indexname;

SELECT
    internal_department,
    secrecy_level,
    count(*) AS count_documents
FROM documents
GROUP BY internal_department, secrecy_level
ORDER BY internal_department, secrecy_level NULLS FIRST
LIMIT 30;
