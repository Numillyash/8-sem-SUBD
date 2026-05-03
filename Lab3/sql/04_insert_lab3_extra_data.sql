\encoding UTF8
\pset pager off

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
VALUES
(
    'DOC-009',
    'План реагирования',
    'Сотрудник_А',
    '{"title": "Дополнительный план реагирования", "version": 1, "summary": "Дополнительный секретный документ для проверки запроса ЛР3"}',
    'Подразделение_1',
    '2024-09-01',
    '2026-09-01',
    'секретно'
),
(
    'DOC-010',
    'Служебная записка',
    'Сотрудник_Г',
    '{"title": "Служебная записка без операций", "version": 1, "summary": "Документ для проверки ответственного без собственных операций"}',
    'Подразделение_4',
    '2024-10-01',
    '2025-10-01',
    NULL
);

INSERT INTO document_operations
(
    employee_name,
    document_number,
    change_date,
    operation_description
)
VALUES
('Сотрудник_А', 'DOC-009', '2024-09-02 10:00:00', 'Создание документа'),
('Сотрудник_А', 'DOC-009', '2024-09-03 11:00:00', 'Проверка документа'),
('Сотрудник_А', 'DOC-009', '2024-09-04 12:00:00', 'Согласование документа');

SELECT 'ЛР3: дополнительные тестовые данные добавлены' AS result;
