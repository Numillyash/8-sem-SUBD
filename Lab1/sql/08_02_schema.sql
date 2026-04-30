\encoding UTF8
\pset pager off

CREATE TABLE documents
(
    document_number       text PRIMARY KEY,
    document_type         text NOT NULL,
    responsible_employee  text NOT NULL,
    document_content      jsonb NOT NULL,
    internal_department   text NOT NULL,
    effective_from        date NOT NULL,
    effective_until       date,
    secrecy_level         text,

    CONSTRAINT uq_documents_alternative_key UNIQUE
    (
        document_type,
        responsible_employee,
        internal_department,
        effective_from
    ),

    CONSTRAINT chk_documents_dates CHECK
    (
        effective_until IS NULL OR effective_until >= effective_from
    ),

    CONSTRAINT chk_documents_secrecy CHECK
    (
        secrecy_level IS NULL OR secrecy_level IN ('ДСП', 'секретно')
    )
);

CREATE TABLE document_operations
(
    employee_name          text NOT NULL,
    document_number        text NOT NULL REFERENCES documents(document_number)
                           ON UPDATE CASCADE
                           ON DELETE CASCADE,
    change_date            timestamp NOT NULL,
    operation_description  text NOT NULL,

    CONSTRAINT pk_document_operations PRIMARY KEY
    (
        employee_name,
        document_number,
        change_date
    )
);

COMMENT ON TABLE documents IS 'Документы организации: отношение 1 варианта 8';
COMMENT ON TABLE document_operations IS 'Операции с документами: отношение 2 варианта 8';

COMMENT ON COLUMN documents.document_number IS 'Номер документа, первичный ключ';
COMMENT ON COLUMN documents.document_type IS 'Тип документа, часть альтернативного ключа';
COMMENT ON COLUMN documents.responsible_employee IS 'ФИО/идентификатор ответственного, часть альтернативного ключа';
COMMENT ON COLUMN documents.document_content IS 'Содержимое документа в формате JSON';
COMMENT ON COLUMN documents.internal_department IS 'Внутреннее подразделение, часть альтернативного ключа';
COMMENT ON COLUMN documents.effective_from IS 'Дата ввода документа в действие, часть альтернативного ключа';
COMMENT ON COLUMN documents.effective_until IS 'Дата окончания действия документа, если есть';
COMMENT ON COLUMN documents.secrecy_level IS 'Степень секретности, если есть';

COMMENT ON COLUMN document_operations.employee_name IS 'Сотрудник, выполнивший операцию';
COMMENT ON COLUMN document_operations.document_number IS 'Номер документа';
COMMENT ON COLUMN document_operations.change_date IS 'Дата изменения';
COMMENT ON COLUMN document_operations.operation_description IS 'Операция с документом';

SELECT 'Пачка 2: таблицы documents и document_operations созданы' AS result;
