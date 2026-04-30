\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

UPDATE documents
SET effective_until = DATE '2026-10-01'
WHERE document_number = 'DOC-006';

SELECT document_number, responsible_employee, effective_until, secrecy_level
FROM documents
WHERE document_number = 'DOC-006';