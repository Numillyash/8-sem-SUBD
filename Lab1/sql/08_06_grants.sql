\encoding UTF8
\pset pager off

REVOKE ALL ON documents FROM PUBLIC;
REVOKE ALL ON document_operations FROM PUBLIC;

GRANT SELECT ON documents TO document_employee;
GRANT UPDATE (effective_until) ON documents TO document_employee;

GRANT SELECT ON document_operations TO document_employee;
GRANT UPDATE (operation_description) ON document_operations TO document_employee;

SELECT 'Пачка 6: права GRANT выданы' AS result;
