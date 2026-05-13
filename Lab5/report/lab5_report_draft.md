# ОТЧЕТ ПО ЛАБОРАТОРНОЙ РАБОТЕ №5

**Тема:** «Оптимизация запросов и производительность»  
**Дисциплина:** «Системы управления базами данных»  
**СУБД:** PostgreSQL 16  
**Среда выполнения:** WSL Ubuntu, Docker, psql  
**База данных:** `subd_lab5`  
**Контейнер:** `subd_lab5_postgres`  
**Порт:** `25432`

---

# 1. Цель работы

Цель лабораторной работы — получение навыков повышения производительности запросов, оптимизации их выполнения и анализа планов запросов в СУБД.

В ходе работы исследовались планы выполнения SQL-запросов к базе данных, разработанной в лабораторной работе №1. Для каждого запроса были получены исходные планы выполнения, определены узкие места, предложены и созданы индексы, после чего были повторно сняты планы выполнения и произведено сравнение времени выполнения до и после оптимизации.

---

# 2. Формулировка задания

Работа выполняется над базой данных, разработанной при выполнении лабораторной работы №1. Для оптимизации используются запросы к данным согласно варианту предметной области.

В рамках работы необходимо:

1. Заполнить тестовую базу данных не менее чем 10000 записями в каждом отношении.
2. Ознакомиться с инструментарием PostgreSQL для просмотра планов выполнения запросов.
3. Для каждого выбранного запроса:
   - привести SQL-код запроса;
   - получить исходный физический план выполнения;
   - зафиксировать время выполнения запроса;
   - определить узкие места в плане выполнения.
4. Создать необходимые индексы, исходя из структуры запросов и характеристик данных.
5. Повторно получить планы выполнения после оптимизации.
6. Зафиксировать изменения в планах выполнения и новое время выполнения.
7. Сравнить результаты до и после оптимизации.
8. Сделать выводы о влиянии индексов и структуры запроса на производительность.

---

# 3. Описание используемой базы данных

Лабораторная работа выполнялась над базой данных, разработанной в лабораторной работе №1 для варианта №8. Предметная область связана с хранением документов организации и журнала операций с ними.

В базе данных использовались два отношения:

- `documents` — таблица документов организации;
- `document_operations` — журнал операций с документами.

Таблица `documents` содержит сведения о документах: номер документа, тип документа, ответственного сотрудника, содержимое документа, внутреннее подразделение, дату ввода документа в действие, дату окончания действия и степень секретности.

Таблица `document_operations` содержит сведения об операциях с документами: сотрудника, номер документа, дату изменения и описание операции.

## 3.1. Схема таблицы documents

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

## 3.2. Схема таблицы document_operations

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

Связь между таблицами реализована по полю `document_number`. Таблица `document_operations` содержит внешний ключ на таблицу `documents`, что исключает возможность добавления операции для несуществующего документа.

---

# 4. Подготовка тестовых данных

Для проведения эксперимента база данных была заполнена синтетическими тестовыми данными. Заполнение выполнялось средствами PostgreSQL с использованием `generate_series`, массивов значений и функций формирования дат.

В таблицу `documents` было добавлено 100000 записей. В таблицу `document_operations` было добавлено 300000 записей. Для каждого документа было сгенерировано по три операции.

Проверка количества записей:

    SELECT
        'documents' AS relation_name,
        count(*) AS row_count
    FROM documents
    UNION ALL
    SELECT
        'document_operations' AS relation_name,
        count(*) AS row_count
    FROM document_operations;

Результат:

    relation_name         | row_count
    ----------------------+----------
    documents             | 100000
    document_operations   | 300000

Размеры таблиц после заполнения:

    relation_name         | table_size | total_size_with_indexes
    ----------------------+------------+-------------------------
    document_operations   | 34 MB      | 58 MB
    documents             | 33 MB      | 54 MB

После заполнения таблиц выполнялись команды:

    ANALYZE documents;
    ANALYZE document_operations;

Они необходимы для обновления статистики PostgreSQL. Статистика используется оптимизатором запросов при выборе плана выполнения.

---

# 5. Инструменты анализа производительности

Для анализа планов выполнения использовалась команда `EXPLAIN ANALYZE` с дополнительными параметрами:

    EXPLAIN (ANALYZE, BUFFERS, VERBOSE)

Параметр `ANALYZE` позволяет выполнить запрос фактически и получить реальное время выполнения операций. Параметр `BUFFERS` показывает использование буферов PostgreSQL. Параметр `VERBOSE` выводит расширенную информацию о плане.

Для уменьшения влияния JIT-компиляции на малых временных интервалах перед измерениями использовалась команда:

    SET jit = off;

Для каждого запроса измерения выполнялись в двух состояниях:

- до оптимизации;
- после создания индексов.

Для каждого состояния выполнялось 5 измерений. Перед серией измерений выполнялся один прогревочный запуск.

---

# 6. Запрос Q1

## 6.1. Назначение запроса

Запрос Q1 выбирает секретные действующие документы из нескольких подразделений. Запрос использует фильтрацию по подразделению, степени секретности и сроку действия документа, а также сортировку результата по дате окончания действия и номеру документа.

## 6.2. SQL-код запроса

    SELECT
        document_number,
        document_type,
        responsible_employee,
        internal_department,
        effective_from,
        effective_until,
        secrecy_level
    FROM documents
    WHERE internal_department IN ('Подразделение_3', 'Подразделение_7', 'Подразделение_13')
      AND secrecy_level = 'секретно'
      AND effective_until IS NOT NULL
      AND effective_until >= DATE '2024-01-01'
    ORDER BY effective_until, document_number;

## 6.3. Исходный план выполнения

В исходном плане использовалось последовательное сканирование таблицы `documents`:

    Seq Scan on public.documents
    Rows Removed by Filter: 97940
    Execution Time: 26.670 ms

Полный исходный план был сохранен в файле:

    logs/04_baseline_plans.log

Фрагмент исходного плана:

    Sort
      Sort Key: documents.effective_until, documents.document_number
      -> Seq Scan on public.documents
           Filter: effective_until IS NOT NULL
                   AND effective_until >= DATE '2024-01-01'
                   AND secrecy_level = 'секретно'
                   AND internal_department IN (...)

Основная проблема исходного плана заключалась в полном просмотре таблицы `documents`. PostgreSQL читал все 100000 строк и только затем применял условия фильтрации. Из 100000 строк фильтром было отброшено 97940 строк, то есть результирующая выборка составляла небольшую часть таблицы.

## 6.4. Индекс для оптимизации Q1

Для оптимизации был создан частичный составной индекс:

    CREATE INDEX idx_documents_q1_secret_department_until
    ON documents
    (
        secrecy_level,
        internal_department,
        effective_until,
        document_number
    )
    INCLUDE
    (
        document_type,
        responsible_employee
    )
    WHERE secrecy_level IS NOT NULL
      AND effective_until IS NOT NULL;

Индекс построен по атрибутам, которые используются в условиях фильтрации: `secrecy_level`, `internal_department` и `effective_until`. Поле `document_number` добавлено для поддержки сортировки и дополнительной идентификации строк. Использование `INCLUDE` позволяет хранить дополнительные атрибуты в индексе без включения их в ключ индекса.

Индекс является частичным, так как создается только для строк, у которых степень секретности и дата окончания действия не равны `NULL`. Это соответствует условиям запроса и уменьшает размер индекса.

## 6.5. План после оптимизации

После создания индекса план изменился:

    Bitmap Index Scan on idx_documents_q1_secret_department_until
    Bitmap Heap Scan on public.documents
    Execution Time: 8.878 ms

Фрагмент оптимизированного плана:

    Bitmap Heap Scan on public.documents
      Recheck Cond: secrecy_level = 'секретно'
                    AND internal_department IN (...)
                    AND effective_until >= DATE '2024-01-01'
      -> Bitmap Index Scan on idx_documents_q1_secret_department_until
           Index Cond: secrecy_level = 'секретно'
                       AND internal_department IN (...)
                       AND effective_until >= DATE '2024-01-01'

PostgreSQL стал использовать индекс для предварительного поиска подходящих строк. Вместо полного просмотра таблицы выполняется поиск по индексу, после чего СУБД обращается только к нужным страницам таблицы.

## 6.6. Результаты измерений Q1

Среднее время выполнения Q1 уменьшилось с 11.494 ms до 2.335 ms.

    Показатель                        Значение
    --------------------------------  --------
    Среднее время до оптимизации       11.494 ms
    Среднее время после оптимизации    2.335 ms
    Коэффициент ускорения              4.923
    Снижение времени выполнения        79.69 %

Наибольший эффект оптимизации был получен именно для Q1, поскольку условия запроса обладают высокой селективностью и хорошо соответствуют созданному индексу.

---

# 7. Запрос Q2

## 7.1. Назначение запроса

Запрос Q2 выполняет соединение журнала операций с таблицей документов и считает количество операций сотрудника за заданный период по ответственным сотрудникам и подразделениям.

## 7.2. SQL-код запроса

    SELECT
        d.responsible_employee,
        d.internal_department,
        count(*) AS operations_count
    FROM document_operations AS o
    JOIN documents AS d
        ON d.document_number = o.document_number
    WHERE o.employee_name = 'Сотрудник_В'
      AND o.change_date >= TIMESTAMP '2024-06-01 00:00:00'
      AND o.change_date <  TIMESTAMP '2024-09-01 00:00:00'
      AND d.secrecy_level IS NOT NULL
    GROUP BY
        d.responsible_employee,
        d.internal_department
    ORDER BY
        operations_count DESC,
        d.responsible_employee,
        d.internal_department;

## 7.3. Исходный план выполнения

В исходном плане использовались параллельные последовательные сканирования таблиц `document_operations` и `documents`:

    Parallel Seq Scan on public.document_operations
    Parallel Seq Scan on public.documents
    Parallel Hash Join
    Execution Time: 34.391 ms

Фрагмент исходного плана:

    Parallel Hash Join
      Hash Cond: d.document_number = o.document_number
      -> Parallel Seq Scan on public.documents d
           Filter: d.secrecy_level IS NOT NULL
      -> Parallel Hash
           -> Parallel Seq Scan on public.document_operations o
                Filter: employee_name = 'Сотрудник_В'
                        AND change_date >= ...
                        AND change_date < ...

Основное узкое место заключалось в чтении большого объема строк из таблицы `document_operations`. Фильтр по сотруднику и диапазону дат применялся после последовательного чтения значительной части таблицы.

## 7.4. Индексы для оптимизации Q2

Для оптимизации были созданы индексы:

    CREATE INDEX idx_operations_q2_employee_date_document
    ON document_operations
    (
        employee_name,
        change_date,
        document_number
    );

    CREATE INDEX idx_documents_q2_secret_document_employee_department
    ON documents
    (
        document_number,
        responsible_employee,
        internal_department
    )
    WHERE secrecy_level IS NOT NULL;

Первый индекс соответствует условиям фильтрации по таблице `document_operations`: сотрудник, диапазон дат и номер документа для соединения.

Второй индекс является частичным и содержит только документы со степенью секретности. Он используется для соединения с таблицей операций и получения атрибутов `responsible_employee` и `internal_department`.

## 7.5. План после оптимизации

После создания индексов план изменился:

    Index Only Scan using idx_operations_q2_employee_date_document
    Index Only Scan using idx_documents_q2_secret_document_employee_department
    Hash Join
    Execution Time: 28.945 ms

Фрагмент оптимизированного плана:

    Hash Join
      Hash Cond: d.document_number = o.document_number
      -> Index Only Scan using idx_documents_q2_secret_document_employee_department on documents d
      -> Hash
           -> Index Only Scan using idx_operations_q2_employee_date_document on document_operations o
                Index Cond: employee_name = 'Сотрудник_В'
                            AND change_date >= ...
                            AND change_date < ...

PostgreSQL стал использовать индексное чтение. В плане появилась операция `Index Only Scan`, что означает возможность получить необходимые данные из индекса без обращения к строкам таблицы.

Операция `Hash Join` сохранилась, так как запрос требует соединения двух таблиц. Также в плане остались операции агрегации и сортировки, поскольку запрос считает количество операций и упорядочивает результат.

## 7.6. Результаты измерений Q2

Среднее время выполнения Q2 уменьшилось с 21.446 ms до 10.519 ms.

    Показатель                        Значение
    --------------------------------  --------
    Среднее время до оптимизации       21.446 ms
    Среднее время после оптимизации    10.519 ms
    Коэффициент ускорения              2.039
    Снижение времени выполнения        50.95 %

Ускорение Q2 оказалось меньше, чем у Q1, поскольку запрос помимо фильтрации выполняет соединение, группировку и сортировку.

---

# 8. Запрос Q3

## 8.1. Назначение запроса

Запрос Q3 определяет количество несекретных документов по подразделениям, для которых в журнале операций есть операция изменения срока действия за заданный период.

Запрос использует условие `EXISTS`, то есть проверяет наличие хотя бы одной связанной записи в таблице `document_operations`.

## 8.2. SQL-код запроса

    SELECT
        d.internal_department,
        count(*) AS changed_documents
    FROM documents AS d
    WHERE d.secrecy_level IS NULL
      AND EXISTS
      (
          SELECT 1
          FROM document_operations AS o
          WHERE o.document_number = d.document_number
            AND o.operation_description = 'Изменение срока действия'
            AND o.change_date >= TIMESTAMP '2024-01-01 00:00:00'
            AND o.change_date <  TIMESTAMP '2025-01-01 00:00:00'
      )
    GROUP BY
        d.internal_department
    ORDER BY
        changed_documents DESC,
        d.internal_department;

## 8.3. Исходный план выполнения

В исходном плане использовались параллельные последовательные сканирования и полусоединение:

    Parallel Seq Scan on public.documents
    Parallel Seq Scan on public.document_operations
    Parallel Hash Semi Join
    Execution Time: 49.575 ms

Фрагмент исходного плана:

    Parallel Hash Semi Join
      Hash Cond: d.document_number = o.document_number
      -> Parallel Seq Scan on public.documents d
           Filter: d.secrecy_level IS NULL
      -> Parallel Hash
           -> Parallel Seq Scan on public.document_operations o
                Filter: operation_description = 'Изменение срока действия'
                        AND change_date >= ...
                        AND change_date < ...

Узким местом являлось последовательное чтение таблицы `document_operations`, где фильтр по описанию операции и диапазону дат применялся после просмотра большого числа строк. Таблица `documents` также сканировалась для отбора несекретных документов.

## 8.4. Индексы для оптимизации Q3

Для оптимизации были созданы индексы:

    CREATE INDEX idx_operations_q3_operation_date_document
    ON document_operations
    (
        operation_description,
        change_date,
        document_number
    );

    CREATE INDEX idx_documents_q3_public_document_department
    ON documents
    (
        document_number,
        internal_department
    )
    WHERE secrecy_level IS NULL;

Первый индекс соответствует фильтру по описанию операции и диапазону дат в таблице `document_operations`. Поле `document_number` включено в индекс для соединения с таблицей документов.

Второй индекс является частичным и содержит только несекретные документы. Он соответствует условию `d.secrecy_level IS NULL`.

## 8.5. План после оптимизации

После создания индексов план изменился:

    Index Only Scan using idx_operations_q3_operation_date_document
    Index Only Scan using idx_documents_q3_public_document_department
    Hash Semi Join
    Execution Time: 39.098 ms

Фрагмент оптимизированного плана:

    Hash Semi Join
      Hash Cond: d.document_number = o.document_number
      -> Index Only Scan using idx_documents_q3_public_document_department on documents d
      -> Hash
           -> Index Only Scan using idx_operations_q3_operation_date_document on document_operations o
                Index Cond: operation_description = 'Изменение срока действия'
                            AND change_date >= ...
                            AND change_date < ...

Операция `Hash Semi Join` соответствует семантике условия `EXISTS`: для каждого документа проверяется наличие хотя бы одной подходящей операции.

## 8.6. Результаты измерений Q3

Среднее время выполнения Q3 уменьшилось с 40.708 ms до 19.614 ms.

    Показатель                        Значение
    --------------------------------  --------
    Среднее время до оптимизации       40.708 ms
    Среднее время после оптимизации    19.614 ms
    Коэффициент ускорения              2.075
    Снижение времени выполнения        51.82 %

Ускорение Q3 связано с тем, что PostgreSQL перестал выполнять полное последовательное чтение таблиц и стал использовать частичные и составные индексы. Однако итоговая стоимость запроса остается заметной из-за необходимости полусоединения, группировки и сортировки.

---

# 9. Сводные результаты измерений

Измерения выполнялись по 5 запусков для каждого запроса до и после оптимизации. Результаты были сохранены в файлы:

    report/lab5_measurements_detail.csv
    report/lab5_measurements_summary.csv

Сводная таблица результатов:

    Запрос | До оптимизации, ms | После оптимизации, ms | Ускорение | Улучшение, %
    -------|--------------------|-----------------------|-----------|-------------
    Q1     | 11.494             | 2.335                 | 4.923     | 79.69
    Q2     | 21.446             | 10.519                | 2.039     | 50.95
    Q3     | 40.708             | 19.614                | 2.075     | 51.82

Наибольшее ускорение было получено для запроса Q1. Это связано с тем, что запрос имеет сравнительно высокую селективность и условия фильтрации хорошо соответствуют созданному индексу.

Для Q2 и Q3 ускорение составило примерно два раза. В этих запросах индексы также сократили объем чтения данных, однако итоговое время выполнения дополнительно определяется стоимостью соединения, группировки и сортировки.

---

# 10. Графическое представление результатов

В ходе работы были построены графики по результатам измерений.

Рисунок 1 — сравнение среднего времени выполнения запросов до и после оптимизации.

    charts/lab5_avg_execution_time.png

Рисунок 2 — коэффициент ускорения запросов после добавления индексов.

    charts/lab5_speedup_ratio.png

Рисунок 3 — процентное снижение времени выполнения.

    charts/lab5_improvement_percent.png

Рисунок 4 — стабильность времени выполнения запроса Q1 по пяти запускам.

    charts/lab5_q1_runs.png

Рисунок 5 — стабильность времени выполнения запроса Q2 по пяти запускам.

    charts/lab5_q2_runs.png

Рисунок 6 — стабильность времени выполнения запроса Q3 по пяти запускам.

    charts/lab5_q3_runs.png

Графики подтверждают снижение времени выполнения всех трех запросов после создания индексов. На графике среднего времени видно, что время выполнения Q1 снизилось наиболее существенно. На графиках стабильности видно, что после оптимизации время выполнения не только уменьшилось, но и стало более стабильным, особенно для Q2 и Q3.

---

# 11. Общий вывод

В ходе лабораторной работы были исследованы методы оптимизации запросов в PostgreSQL на примере базы данных документов организации. Для эксперимента была подготовлена тестовая база данных объемом 100000 документов и 300000 операций с документами.

Для трех SQL-запросов были получены исходные планы выполнения с помощью `EXPLAIN ANALYZE`. В исходных планах были обнаружены операции последовательного сканирования таблиц `documents` и `document_operations`. Такие операции приводили к чтению большого количества строк и последующему отбрасыванию значительной части данных по условиям фильтрации.

Для оптимизации были созданы составные и частичные индексы, соответствующие условиям фильтрации, соединения и структуре данных. После добавления индексов планы выполнения изменились: PostgreSQL начал использовать `Bitmap Index Scan`, `Bitmap Heap Scan` и `Index Only Scan`.

В результате оптимизации среднее время выполнения всех запросов уменьшилось:

- Q1 был ускорен в 4.923 раза;
- Q2 был ускорен в 2.039 раза;
- Q3 был ускорен в 2.075 раза.

Наибольший эффект был получен для запроса с высокой селективностью и простым отбором строк из одной таблицы. Для запросов с соединениями, группировкой и сортировкой эффект от индексации также оказался значительным, но менее выраженным, поскольку часть стоимости выполнения связана не только с поиском строк, но и с обработкой промежуточного результата.

Таким образом, в работе было показано, что анализ планов выполнения позволяет выявлять узкие места запросов, а правильно подобранные индексы позволяют существенно повысить производительность операций выборки. При этом выбор индекса должен учитывать не только отдельные поля таблиц, но и реальные условия фильтрации, селективность данных, порядок соединения таблиц и необходимость дополнительных операций, таких как группировка и сортировка.

---

# 12. Список использованных источников

1. Практикум по построению защищенных баз данных: учебное пособие / М. А. Потапова, Е. А. Зубков, Д. А. Мокин, Д. Овсян, Н. А. Сикарев. — СПб.: ПОЛИТЕХ-ПРЕСС, 2023.
2. PostgreSQL Documentation. EXPLAIN — show the execution plan of a statement.
3. PostgreSQL Documentation. Indexes.
4. PostgreSQL Documentation. Partial Indexes.
5. PostgreSQL Documentation. Index-Only Scans and Covering Indexes.

---

# Приложение А. Использованные файлы

Основные SQL-скрипты:

    sql/00_reset.sql
    sql/01_schema.sql
    sql/02_fill_test_data.sql
    sql/03_check_counts.sql
    sql/04_baseline_plans.sql
    sql/05_create_indexes.sql
    sql/06_optimized_plans.sql
    sql/07_measure_5_runs.sql
    sql/08_export_measurements.sql

Основные логи:

    logs/03_check_counts.log
    logs/04_baseline_plans.log
    logs/05_create_indexes.log
    logs/06_optimized_plans.log
    logs/07_measure_5_runs.log
    logs/08_export_measurements.log

Файлы результатов:

    report/lab5_measurements_detail.csv
    report/lab5_measurements_summary.csv

Графики:

    charts/lab5_avg_execution_time.png
    charts/lab5_speedup_ratio.png
    charts/lab5_improvement_percent.png
    charts/lab5_q1_runs.png
    charts/lab5_q2_runs.png
    charts/lab5_q3_runs.png
