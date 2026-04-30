\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

SELECT
    document_number,
    document_type,
    responsible_employee,
    internal_department,
    effective_from,
    effective_until,
    secrecy_level
FROM documents
ORDER BY document_number;
