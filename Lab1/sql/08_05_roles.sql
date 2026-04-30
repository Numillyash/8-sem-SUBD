\encoding UTF8
\pset pager off

CREATE ROLE document_employee;

CREATE ROLE "Сотрудник_А" LOGIN PASSWORD 'lab1pass';
CREATE ROLE "Сотрудник_Б" LOGIN PASSWORD 'lab1pass';
CREATE ROLE "Сотрудник_В" LOGIN PASSWORD 'lab1pass';
CREATE ROLE "Сотрудник_Г" LOGIN PASSWORD 'lab1pass';
CREATE ROLE "Сотрудник_Д" LOGIN PASSWORD 'lab1pass';

GRANT document_employee TO
    "Сотрудник_А",
    "Сотрудник_Б",
    "Сотрудник_В",
    "Сотрудник_Г",
    "Сотрудник_Д";

GRANT USAGE ON SCHEMA public TO document_employee;

SELECT 'Пачка 5: роль document_employee и пользователи созданы' AS result;
