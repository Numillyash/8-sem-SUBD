\pset pager off
\timing on

\echo '=== ЛР-4. Шаг 1: проверка окружения и размеров баз данных ==='

SELECT
    version() AS postgres_version;

SELECT
    current_database() AS current_database,
    current_user AS current_user;

SHOW server_version;
SHOW block_size;
SHOW data_directory;

\echo '=== Размеры баз данных на сервере ==='

SELECT
    d.datname AS database_name,
    pg_database_size(d.datname) AS database_bytes,
    pg_size_pretty(pg_database_size(d.datname)) AS database_size,
    d.datistemplate AS is_template
FROM pg_database d
ORDER BY pg_database_size(d.datname) DESC;

\echo '=== Контроль важных настроек PostgreSQL ==='

SELECT
    name,
    setting,
    unit
FROM pg_settings
WHERE name IN
(
    'block_size',
    'data_directory',
    'server_version',
    'shared_buffers',
    'max_connections'
)
ORDER BY name;
