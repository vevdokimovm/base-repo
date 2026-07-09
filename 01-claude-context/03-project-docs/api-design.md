# api-design.md — REST-конвенции проекта

> Единый стандарт API: именование эндпоинтов, версионирование, формат ошибок, статус-коды. Закрывает пробел «знаю термин REST, но не стандартизирую в коде».

---

## 1. Версионирование и структура URL
- Префикс версии: **`/api/v1/`**.
- Ресурсы — существительные во **множественном числе**, kebab-case не нужен (snake через путь):
```
GET    /api/v1/accounts
POST   /api/v1/accounts
GET    /api/v1/accounts/{account_id}
PATCH  /api/v1/accounts/{account_id}
DELETE /api/v1/accounts/{account_id}
GET    /api/v1/accounts/{account_id}/transactions
```
- Никаких глаголов в путях (`/getAccounts` ❌). Действие несёт HTTP-метод.

## 2. HTTP-методы
| Метод | Назначение | Идемпотентность |
|-------|-----------|-----------------|
| GET | получить | да |
| POST | создать | нет |
| PUT | заменить целиком | да |
| PATCH | частично обновить | нет (обычно) |
| DELETE | удалить | да |

## 3. Статус-коды (когда какой)
- `200 OK` — успешный GET/PATCH/PUT.
- `201 Created` — успешный POST (создан ресурс). Возвращать созданный объект.
- `204 No Content` — успешный DELETE без тела.
- `400 Bad Request` — некорректный запрос (не прошёл базовую проверку).
- `401 Unauthorized` — нет/невалидная аутентификация.
- `403 Forbidden` — аутентифицирован, но нет прав.
- `404 Not Found` — ресурс не найден.
- `422 Unprocessable Entity` — валидация Pydantic не прошла (FastAPI отдаёт сам).
- `500 Internal Server Error` — необработанная ошибка (не отдавать детали наружу).

## 4. Единый формат ошибки
```json
{
  "detail": "human-readable message",
  "code": "ACCOUNT_NOT_FOUND"
}
```
Доменные исключения → FastAPI exception handlers → этот формат. Никаких stack trace в ответе.

## 5. Пагинация, фильтрация, сортировка
```
GET /api/v1/transactions?limit=50&offset=0&sort=-date&category_id=3
```
- `limit`/`offset` (дефолт limit=50, max 200).
- Сортировка: `sort=field` (asc) / `sort=-field` (desc).
- Ответ списка — с метаданными:
```json
{ "items": [...], "total": 128, "limit": 50, "offset": 0 }
```

## 6. Схемы (Pydantic)
- Раздельные `*Create` (вход) и `*Response` (выход). Никогда одна схема на оба.
- Не возвращать чувствительные поля (`password_hash`) — их нет в `*Response`.

## 7. Прочее
- Все ответы — JSON, `Content-Type: application/json`.
- Даты — ISO 8601 (`2026-07-08T12:00:00Z`).
- Денежные суммы — строкой или integer-минорными единицами, не float.
- Документация — авто через Swagger (`/docs`), поддерживать актуальной.

> Можно держать отдельным файлом или секцией в `architecture.md` — по сути одно.
