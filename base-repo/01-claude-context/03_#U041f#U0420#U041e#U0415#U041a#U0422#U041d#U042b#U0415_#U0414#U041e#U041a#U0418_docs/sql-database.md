# sql-database.md — работа с БД

> Стиль работы с БД, раз ORM-страховки нет и пишется чистый SQL. Конвенции важнее, потому что нет автоматики. Плюс — слабое место и тема на собесе.

---

## 1. Именование
- **Таблицы** — множественное число, snake_case: `users`, `transactions`, `financial_goals`.
- **Колонки** — snake_case: `created_at`, `account_id`, `is_active`.
- **PK** — `id` (SERIAL/BIGSERIAL или UUID).
- **FK** — `<entity>_id`: `user_id`, `account_id`.
- **Индексы** — `ix_<table>_<column>`; уникальные — `uq_<table>_<column>`.
- **Булевы** — с префиксом `is_`/`has_`: `is_active`, `has_debt`.

## 2. Стиль запросов
- SQL-ключевые слова — **UPPER CASE**, идентификаторы — lower.
- Никогда `SELECT *` — только нужные колонки.
- Явные `JOIN ... ON`, не запятые в FROM.
- Параметризация всегда (защита от SQL-инъекций) — плейсхолдеры драйвера, не f-строки.
```sql
SELECT t.id, t.amount, t.date, c.name AS category
FROM transactions AS t
JOIN categories AS c ON c.id = t.category_id
WHERE t.account_id = $1
  AND t.date >= $2
ORDER BY t.date DESC
LIMIT 50;
```

## 3. Индексы — когда ставить
- На **FK-колонки** (почти всегда — ускоряет JOIN).
- На колонки в частых `WHERE`/`ORDER BY` (`date`, `user_id`).
- Составной индекс под частый составной фильтр (порядок колонок = порядок в WHERE).
- **Не** индексировать всё подряд: индекс ускоряет чтение, но замедляет запись и ест место.
- Проверять план: `EXPLAIN ANALYZE <query>` — читать, использует ли индекс (Index Scan vs Seq Scan).

## 4. Типы
- Деньги — `NUMERIC(precision, scale)`, **никогда `FLOAT`/`REAL`** (ошибки округления).
- Время — `TIMESTAMPTZ` (с таймзоной).
- Идентификаторы — `BIGSERIAL` или `UUID`.
- Текст — `TEXT` (в Postgres нет смысла в `VARCHAR(n)` ради длины, кроме явных ограничений).

## 5. Миграции (Alembic)
- **Никогда не править таблицы руками в проде** — только миграции (воспроизводимость, откат, командная работа).
```bash
alembic revision --autogenerate -m "add transactions table"
alembic upgrade head
alembic downgrade -1        # откат на шаг
```
- Каждая миграция — атомарна и осмысленна. Автоген проверять глазами перед применением.
- Булевы дефолты для Postgres: `server_default=sa.false()`.
- В команде/на нескольких машинах — миграции в git, применяются последовательно.

## 6. Прочее
- Пул соединений всегда (не открывать connection на каждый запрос).
- Транзакции — где несколько записей должны быть атомарны.
- N+1 — избегать: один JOIN вместо запроса в цикле.

> Пересекается с `data-model.md`, но фокус другой: тот — *что за данные*, этот — *как с ними работать*.
