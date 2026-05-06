# ЛР3 SQLi. Ход выполнения

## Стенд

URL: http://ibks.spbstu.ru:8086/away/d613d6fc-55c3-40d9-a03c-53607ac0c422
UUID: d613d6fc-55c3-40d9-a03c-53607ac0c422
Название лабораторной: Radiant-Wind
Тип сайта: доставка еды
Создана: 04.05.2026 02:06
Запущена: 04.05.2026 02:06
Лимит времени: 3 часа

## Найденные API-ручки

- GET /api/categories
- GET /api/products
- GET /api/products?category=...
- GET /api/products/{article}
- GET /api/products/{article}/reviews
- GET /api/orders
- WebSocket: http://ibks.spbstu.ru:3000/ws

## Наблюдения

- Сайт работает как SPA-приложение и получает данные через JSON API.
- В ответе /api/products возвращаются товары с полями article, category_name, name, price, released, stock, store_name.
- В части ответов category_name и store_name равны null.
- Запросы /api/categories, /api/orders и некоторые запросы к товарам периодически возвращают ошибку PostgreSQL: "sorry, too many clients already".
- Ошибка "too many clients already" похожа на проблему перегрузки/лимита соединений учебного стенда, а не на результат SQL-инъекции.

## Приоритетные точки проверки SQLi

1. Параметр category в GET /api/products?category=...
2. Path-параметр article в GET /api/products/{article}
3. Path-параметр article в GET /api/products/{article}/reviews
4. Возможные параметры авторизации/логина
5. GET /api/orders после авторизации


## Анализ frontend JS

По файлу `js.txt` установлено, что сайт является React SPA-приложением.

Backend API prefix:

- `/away/d613d6fc-55c3-40d9-a03c-53607ac0c422/api`

Найденные frontend routes:

- `/`
- `/login`
- `/profile`
- `/cart`
- `/products/:product_id`

Найденные API endpoints:

- `POST /api/login`
- `POST /api/logout`
- `GET /api/products`
- `GET /api/categories`
- `GET /api/products?category=...`
- `GET /api/products/{product_id}`
- `GET /api/products/{product_id}/reviews`
- `POST /api/products/{product_id}/reviews`
- `POST /api/favorites/check`
- `POST /api/favorites`
- `DELETE /api/favorites/{article}`
- `GET /api/profile`
- `POST /api/profile`
- `GET /api/profile/favorites`
- `GET /api/profile/reviews`
- `GET /api/orders`
- `POST /api/orders`

Особенности авторизации:

- после входа frontend выставляет `localStorage.loggedIn = true`;
- для авторизованных API-запросов используется cookie `user`;
- cookie `user` передается в заголовке `Authorization: Bearer <userCookie>`;
- до входа запросы к `/api/orders` идут с `Authorization: Bearer null`.

Приоритетные точки SQLi после анализа JS:

1. `POST /api/login` — поля `username`, `password`;
2. `GET /api/products?category=...` — строковый параметр `category`;
3. `GET /api/products/{product_id}` — path-параметр товара;
4. `GET/POST /api/products/{product_id}/reviews` — path-параметр товара и текст отзыва;
5. `POST /api/profile` — поле `description`;
6. `POST /api/favorites/check` и `POST /api/favorites` — поле `article`;
7. `POST /api/orders` — массив заказов с `article` и `price`.


## Флаг ibks1

Параметр:
Запрос:
Payload:
Результат:

## Флаг ibks2

Параметр:
Запрос:
Payload:
Результат:

## Флаг ibks3

Параметр:
Запрос:
Payload:
Результат:

## Итоговый ответ

secret_
