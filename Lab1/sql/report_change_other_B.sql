\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

UPDATE document_operations
SET operation_description = 'Попытка изменить чужую операцию'
WHERE employee_name = 'Сотрудник_Д'
  AND document_number = 'DOC-006';