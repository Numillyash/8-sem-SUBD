\encoding UTF8
\pset pager off

\echo '=== Версия PostgreSQL ==='
SELECT version();

\echo '=== Текущая база и пользователь ==='
SELECT current_database(), current_user;

\echo '=== Таблицы варианта 8 ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

\echo '=== Роли варианта 8 ==='
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

\echo '=== Членство пользователей в роли document_employee ==='
SELECT
    member_role.rolname AS user_name,
    parent_role.rolname AS granted_role
FROM pg_auth_members m
JOIN pg_roles parent_role ON parent_role.oid = m.roleid
JOIN pg_roles member_role ON member_role.oid = m.member
WHERE parent_role.rolname = 'document_employee'
ORDER BY user_name;

\echo '=== Политики RLS ==='
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename IN ('documents', 'document_operations')
ORDER BY tablename, policyname;

\echo '=== Табличные права ==='
SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('documents', 'document_operations')
  AND grantee = 'document_employee'
ORDER BY table_name, privilege_type;

\echo '=== Столбцовые права ==='
SELECT
    grantee,
    table_name,
    column_name,
    privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name IN ('documents', 'document_operations')
  AND grantee = 'document_employee'
ORDER BY table_name, column_name, privilege_type;
