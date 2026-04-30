\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

SELECT
    employee_name,
    document_number,
    change_date,
    operation_description
FROM document_operations
ORDER BY document_number, change_date;