\encoding UTF8
\pset pager off

\echo 'Проверка количества данных'

SELECT 'documents' AS table_name, COUNT(*) AS rows_count FROM documents
UNION ALL
SELECT 'document_operations' AS table_name, COUNT(*) AS rows_count FROM document_operations;

\echo 'Проверка документов по степени секретности'

SELECT
    COALESCE(secrecy_level, 'несекретный') AS secrecy_level,
    COUNT(*) AS documents_count
FROM documents
GROUP BY COALESCE(secrecy_level, 'несекретный')
ORDER BY secrecy_level;

\echo 'Проверка количества операций по документам'

SELECT
    document_number,
    COUNT(*) AS operations_count,
    COUNT(DISTINCT operation_description) AS distinct_operation_types
FROM document_operations
GROUP BY document_number
ORDER BY document_number;
