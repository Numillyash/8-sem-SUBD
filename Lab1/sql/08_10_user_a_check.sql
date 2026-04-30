\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

\echo '=== Документы, доступные Сотруднику_А ==='
SELECT
    document_number,
    document_type,
    responsible_employee,
    secrecy_level
FROM documents
ORDER BY document_number;

\echo '=== Операции, доступные Сотруднику_А ==='
SELECT
    employee_name,
    document_number,
    change_date,
    operation_description
FROM document_operations
ORDER BY document_number, change_date;
