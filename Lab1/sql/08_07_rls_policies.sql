\encoding UTF8
\pset pager off

ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents FORCE ROW LEVEL SECURITY;

ALTER TABLE document_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_operations FORCE ROW LEVEL SECURITY;

CREATE POLICY documents_select_policy
ON documents
FOR SELECT
TO document_employee
USING
(
    secrecy_level IS NULL
    OR responsible_employee = current_user
);

CREATE POLICY documents_update_policy
ON documents
FOR UPDATE
TO document_employee
USING
(
    responsible_employee = current_user
)
WITH CHECK
(
    responsible_employee = current_user
);

CREATE POLICY operations_select_policy
ON document_operations
FOR SELECT
TO document_employee
USING
(
    employee_name = current_user
    OR EXISTS
    (
        SELECT 1
        FROM documents d
        WHERE d.document_number = document_operations.document_number
          AND d.responsible_employee = current_user
    )
);

CREATE POLICY operations_update_policy
ON document_operations
FOR UPDATE
TO document_employee
USING
(
    employee_name = current_user
)
WITH CHECK
(
    employee_name = current_user
);

SELECT 'Пачка 7: RLS включен, политики созданы' AS result;
