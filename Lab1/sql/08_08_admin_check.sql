\encoding UTF8
\pset pager off

\echo '=== Таблица documents ==='
TABLE documents;

\echo '=== Таблица document_operations ==='
TABLE document_operations;

\echo '=== Роли лабораторной работы ==='
SELECT rolname, rolcanlogin, rolsuper
FROM pg_roles
WHERE rolname IN
(
    'document_employee',
    'Сотрудник_А',
    'Сотрудник_Б',
    'Сотрудник_В',
    'Сотрудник_Г',
    'Сотрудник_Д'
)
ORDER BY rolname;

\echo '=== Политики RLS ==='
SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename IN ('documents', 'document_operations')
ORDER BY tablename, policyname;
