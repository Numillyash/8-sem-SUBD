\encoding UTF8
\pset pager off

\echo '=== Текущий пользователь ==='
SELECT current_user;

UPDATE documents
SET secrecy_level = 'секретно'
WHERE document_number = 'DOC-006';
