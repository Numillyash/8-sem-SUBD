\encoding UTF8
\pset pager off

DROP TABLE IF EXISTS document_operations CASCADE;
DROP TABLE IF EXISTS documents CASCADE;

DROP TABLE IF EXISTS inventory CASCADE;
DROP TABLE IF EXISTS facility CASCADE;
DROP TABLE IF EXISTS staff CASCADE;

DO $$
DECLARE
    r text;
BEGIN
    FOREACH r IN ARRAY ARRAY[
        'common_staff',
        'material_responsible',
        'facility_responsible',
        'document_employee',
        'Иванов',
        'Иванова',
        'Петров',
        'Петрова',
        'Сидоров',
        'Сидорова',
        'Сотрудник_А',
        'Сотрудник_Б',
        'Сотрудник_В',
        'Сотрудник_Г',
        'Сотрудник_Д'
    ]
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('DROP OWNED BY %I CASCADE', r);
        END IF;
    END LOOP;
END $$;

DROP ROLE IF EXISTS common_staff;
DROP ROLE IF EXISTS material_responsible;
DROP ROLE IF EXISTS facility_responsible;
DROP ROLE IF EXISTS document_employee;

DROP ROLE IF EXISTS "Иванов";
DROP ROLE IF EXISTS "Иванова";
DROP ROLE IF EXISTS "Петров";
DROP ROLE IF EXISTS "Петрова";
DROP ROLE IF EXISTS "Сидоров";
DROP ROLE IF EXISTS "Сидорова";

DROP ROLE IF EXISTS "Сотрудник_А";
DROP ROLE IF EXISTS "Сотрудник_Б";
DROP ROLE IF EXISTS "Сотрудник_В";
DROP ROLE IF EXISTS "Сотрудник_Г";
DROP ROLE IF EXISTS "Сотрудник_Д";

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

SELECT 'Пачка 1: старая схема и старые роли удалены' AS result;
