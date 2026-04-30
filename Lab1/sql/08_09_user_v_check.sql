\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

\echo '=== Разрешенный SELECT documents ==='
\echo 'Ожидается: все несекретные документы + секретный DOC-006, где Сотрудник_В ответственный'
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

\echo '=== Разрешенный UPDATE effective_until своего документа DOC-006 ==='
UPDATE documents
SET effective_until = DATE '2026-06-01'
WHERE document_number = 'DOC-006';

SELECT document_number, responsible_employee, effective_until, secrecy_level
FROM documents
WHERE document_number = 'DOC-006';

\echo '=== Попытка UPDATE чужого документа DOC-001 ==='
\echo 'Ожидается: UPDATE 0'
UPDATE documents
SET effective_until = DATE '2026-01-01'
WHERE document_number = 'DOC-001';

\echo '=== Попытка изменить secrecy_level ==='
\echo 'Ожидается: ERROR permission denied'
UPDATE documents
SET secrecy_level = 'секретно'
WHERE document_number = 'DOC-006';

\echo '=== Разрешенный SELECT document_operations ==='
\echo 'Ожидается: свои операции + операции по документам, где Сотрудник_В ответственный'
SELECT
    employee_name,
    document_number,
    change_date,
    operation_description
FROM document_operations
ORDER BY document_number, change_date;

\echo '=== Разрешенный UPDATE своей операции ==='
UPDATE document_operations
SET operation_description = 'Регистрация входящей операции, уточнено'
WHERE employee_name = current_user
  AND document_number = 'DOC-002';

SELECT employee_name, document_number, operation_description
FROM document_operations
WHERE employee_name = current_user
  AND document_number = 'DOC-002';

\echo '=== Попытка изменить чужую операцию по своему документу DOC-006 ==='
\echo 'Ожидается: UPDATE 0'
UPDATE document_operations
SET operation_description = 'Попытка изменить чужую операцию'
WHERE employee_name = 'Сотрудник_Д'
  AND document_number = 'DOC-006';

\echo '=== Попытка изменить дату операции ==='
\echo 'Ожидается: ERROR permission denied'
UPDATE document_operations
SET change_date = TIMESTAMP '2024-06-03 10:00:00'
WHERE employee_name = current_user
  AND document_number = 'DOC-002';
