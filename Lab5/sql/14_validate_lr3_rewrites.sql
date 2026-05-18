\encoding UTF8
\pset pager off
\timing on

SET jit = off;

SELECT 'Проверка эквивалентности Q2: original EXCEPT rewritten' AS check_name;

WITH q2_original AS
(
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until IS NOT NULL
      AND EXTRACT(YEAR FROM d.effective_until)::int = 2025
      AND NOT (EXTRACT(MONTH FROM d.effective_until)::int = ANY(ARRAY[5,6,7]::int[]))
),
q2_rewritten AS
(
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until >= DATE '2025-01-01'
      AND d.effective_until <  DATE '2026-01-01'
      AND NOT
      (
          d.effective_until >= DATE '2025-05-01'
          AND d.effective_until <  DATE '2025-08-01'
      )
)
SELECT count(*) AS diff_count
FROM
(
    SELECT * FROM q2_original
    EXCEPT
    SELECT * FROM q2_rewritten
) AS diff;


SELECT 'Проверка эквивалентности Q2: rewritten EXCEPT original' AS check_name;

WITH q2_original AS
(
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until IS NOT NULL
      AND EXTRACT(YEAR FROM d.effective_until)::int = 2025
      AND NOT (EXTRACT(MONTH FROM d.effective_until)::int = ANY(ARRAY[5,6,7]::int[]))
),
q2_rewritten AS
(
    SELECT
        d.document_number,
        d.responsible_employee,
        d.effective_until,
        EXTRACT(MONTH FROM d.effective_until)::int AS effective_until_month
    FROM documents d
    WHERE d.effective_until >= DATE '2025-01-01'
      AND d.effective_until <  DATE '2026-01-01'
      AND NOT
      (
          d.effective_until >= DATE '2025-05-01'
          AND d.effective_until <  DATE '2025-08-01'
      )
)
SELECT count(*) AS diff_count
FROM
(
    SELECT * FROM q2_rewritten
    EXCEPT
    SELECT * FROM q2_original
) AS diff;


SELECT 'Проверка эквивалентности Q3: original EXCEPT rewritten' AS check_name;

WITH q3_original AS
(
    SELECT DISTINCT result.employee_name
    FROM
    (
        SELECT DISTINCT op.employee_name
        FROM document_operations op
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM unnest(ARRAY[
                'Создание документа',
                'Проверка документа',
                'Согласование документа'
            ]::text[]) AS possible_operation(operation_description)
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
),
required_operations AS
(
    SELECT *
    FROM unnest(ARRAY[
        'Создание документа',
        'Проверка документа',
        'Согласование документа'
    ]::text[]) AS r(operation_description)
),
completed_operation_sets AS
(
    SELECT
        op.employee_name,
        op.document_number
    FROM document_operations op
    JOIN required_operations r
        ON r.operation_description = op.operation_description
    GROUP BY
        op.employee_name,
        op.document_number
    HAVING COUNT(DISTINCT op.operation_description) =
           (SELECT COUNT(*) FROM required_operations)
),
responsible_without_own_operations AS
(
    SELECT d.responsible_employee AS employee_name
    FROM documents d
    LEFT JOIN document_operations op
        ON op.document_number = d.document_number
       AND op.employee_name = d.responsible_employee
    WHERE op.document_number IS NULL
),
q3_rewritten AS
(
    SELECT DISTINCT employee_name
    FROM
    (
        SELECT employee_name
        FROM completed_operation_sets

        UNION

        SELECT employee_name
        FROM responsible_without_own_operations
    ) AS result
)
SELECT count(*) AS diff_count
FROM
(
    SELECT * FROM q3_original
    EXCEPT
    SELECT * FROM q3_rewritten
) AS diff;


SELECT 'Проверка эквивалентности Q3: rewritten EXCEPT original' AS check_name;

WITH q3_original AS
(
    SELECT DISTINCT result.employee_name
    FROM
    (
        SELECT DISTINCT op.employee_name
        FROM document_operations op
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM unnest(ARRAY[
                'Создание документа',
                'Проверка документа',
                'Согласование документа'
            ]::text[]) AS possible_operation(operation_description)
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
),
required_operations AS
(
    SELECT *
    FROM unnest(ARRAY[
        'Создание документа',
        'Проверка документа',
        'Согласование документа'
    ]::text[]) AS r(operation_description)
),
completed_operation_sets AS
(
    SELECT
        op.employee_name,
        op.document_number
    FROM document_operations op
    JOIN required_operations r
        ON r.operation_description = op.operation_description
    GROUP BY
        op.employee_name,
        op.document_number
    HAVING COUNT(DISTINCT op.operation_description) =
           (SELECT COUNT(*) FROM required_operations)
),
responsible_without_own_operations AS
(
    SELECT d.responsible_employee AS employee_name
    FROM documents d
    LEFT JOIN document_operations op
        ON op.document_number = d.document_number
       AND op.employee_name = d.responsible_employee
    WHERE op.document_number IS NULL
),
q3_rewritten AS
(
    SELECT DISTINCT employee_name
    FROM
    (
        SELECT employee_name
        FROM completed_operation_sets

        UNION

        SELECT employee_name
        FROM responsible_without_own_operations
    ) AS result
)
SELECT count(*) AS diff_count
FROM
(
    SELECT * FROM q3_rewritten
    EXCEPT
    SELECT * FROM q3_original
) AS diff;
