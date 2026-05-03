\encoding UTF8
\pset pager off

\echo '============================================================'
\echo 'Запрос 1. Ответственные более чем за один секретный документ заданной степени'
\echo 'Параметр: заданная степень секретности = секретно'
\echo '============================================================'

\set given_secrecy_level '''секретно'''

SELECT
    d.responsible_employee AS responsible_employee,
    COUNT(*) AS secret_documents_count
FROM documents d
WHERE d.secrecy_level = :given_secrecy_level
GROUP BY d.responsible_employee
HAVING COUNT(*) > 1
ORDER BY d.responsible_employee;

\echo '============================================================'
\echo 'Запрос 2. Документы, срок окончания действия которых НЕ входит в перечень заданных месяцев'
\echo 'Параметры: год = 2025, месяцы = май, июнь, июль'
\echo '============================================================'

\set given_year 2025
\set given_months 'ARRAY[5,6,7]::int[]'

SELECT
    d.document_number,
    d.responsible_employee,
    d.effective_until,
    EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
FROM documents d
WHERE d.effective_until IS NOT NULL
  AND EXTRACT(YEAR FROM d.effective_until)::int = :given_year
  AND NOT (EXTRACT(MONTH FROM d.effective_until)::int = ANY(:given_months))
ORDER BY d.effective_until, d.document_number;

\echo '============================================================'
\echo 'Запрос 3. Сотрудники, совершившие с каким-либо документом все возможные операции,'
\echo 'или ответственные за документы без собственных операций'
\echo 'Параметр: перечень возможных операций = создание, проверка, согласование'
\echo '============================================================'

\set possible_operations 'ARRAY[''Создание документа'', ''Проверка документа'', ''Согласование документа'']::text[]'

SELECT DISTINCT result.employee_name
FROM
(
    SELECT DISTINCT op.employee_name
    FROM document_operations op
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM unnest(:possible_operations) AS possible_operation(operation_description)
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM document_operations op_check
            WHERE op_check.employee_name = op.employee_name
              AND op_check.document_number = op.document_number
              AND op_check.operation_description = possible_operation.operation_description
        )
    )

    UNION

    SELECT d.responsible_employee AS employee_name
    FROM documents d
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM document_operations op
        WHERE op.document_number = d.document_number
          AND op.employee_name = d.responsible_employee
    )
) AS result
ORDER BY result.employee_name;
