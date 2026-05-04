\encoding UTF8
\pset pager off
\timing on

TRUNCATE TABLE document_operations, documents RESTART IDENTITY CASCADE;

BEGIN;

SET LOCAL synchronous_commit = off;

INSERT INTO documents
(
    document_number,
    document_type,
    responsible_employee,
    document_content,
    internal_department,
    effective_from,
    effective_until,
    secrecy_level
)
SELECT
    'DOC-' || lpad(g::text, 7, '0') AS document_number,

    (ARRAY[
        'Регламент',
        'План реагирования',
        'Инструкция',
        'Модель угроз',
        'Служебная записка'
    ])[((g * 7 + g / 11) % 5) + 1] AS document_type,

    (ARRAY[
        'Сотрудник_А',
        'Сотрудник_Б',
        'Сотрудник_В',
        'Сотрудник_Г',
        'Сотрудник_Д'
    ])[((g * 3 + g / 17) % 5) + 1] AS responsible_employee,

    jsonb_build_object
    (
        'title', 'Тестовый документ ' || g,
        'version', ((g * 13) % 10) + 1,
        'summary', 'Синтетические данные для ЛР5',
        'risk_level', ((g * 19 + g / 23) % 4) + 1,
        'has_personal_data', (g % 7 = 0)
    ) AS document_content,

    'Подразделение_' || (((g * 13 + g / 29) % 20) + 1) AS internal_department,

    DATE '2020-01-01' + g::int AS effective_from,

    CASE
        WHEN g % 17 = 0 THEN NULL
        ELSE DATE '2020-01-01' + g::int + (((g * 31) % 730) + 30)
    END AS effective_until,

    CASE
        WHEN ((g * 17 + g / 7) % 10) IN (0, 1) THEN 'ДСП'
        WHEN ((g * 17 + g / 7) % 10) = 2 THEN 'секретно'
        ELSE NULL
    END AS secrecy_level
FROM generate_series(1, 100000) AS g;

INSERT INTO document_operations
(
    employee_name,
    document_number,
    change_date,
    operation_description
)
SELECT
    (ARRAY[
        'Сотрудник_А',
        'Сотрудник_Б',
        'Сотрудник_В',
        'Сотрудник_Г',
        'Сотрудник_Д'
    ])[((g + opn * 7 + g / 13) % 5) + 1] AS employee_name,

    'DOC-' || lpad(g::text, 7, '0') AS document_number,

    timestamp '2024-01-01 00:00:00'
        + make_interval(days => ((g * 37 + opn * 11) % 730))
        + make_interval(secs => ((g * 97 + opn * 997) % 86400)) AS change_date,

    (ARRAY[
        'Создание документа',
        'Проверка документа',
        'Согласование документа',
        'Изменение срока действия',
        'Регистрация операции'
    ])[((g + opn * 3 + g / 19) % 5) + 1] AS operation_description
FROM generate_series(1, 100000) AS g
CROSS JOIN generate_series(1, 3) AS opn;

COMMIT;

ANALYZE documents;
ANALYZE document_operations;

SELECT 'ЛР5: тестовые данные добавлены с улучшенным распределением' AS result;
