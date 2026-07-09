# СТАНДАРТЫ — код и карьера (Василий)

> Технический свод для рабочих/проектных сессий. Дополняет `КОНТЕКСТ_Василий_ЕДИНЫЙ.md`.
> Грузить, когда пишем код / проектируем / готовимся к собесам. Прозаические пояснения — на русском, всё техническое — на английском (мой стандарт).

---

## 1. Python Backend — стандарты

**Версия:** Python 3.11+ only. Никогда Python 2.

| Rule | Standard |
|------|----------|
| Naming | PEP 8 strict — snake_case vars/funcs, PascalCase classes, UPPER_CASE constants |
| Structure | OOP — classes and objects |
| Type hints | Function signatures only (args + return type) |
| Line length | 88 chars max |
| Comments | Minimal — self-documenting code preferred |
| Global vars | Never |
| Secrets | Always via `.env` — never hardcoded |

**Linting:** сейчас Flake8. Рекомендованная миграция на **Ruff** (10–100× быстрее, заменяет Flake8 + isort + Black одним инструментом).
```bash
flake8 app/ --max-line-length=88   # run before every commit
```

**Зависимости** — split по окружению, версии всегда пинить:
```
requirements.txt        # Production only
requirements-dev.txt    # Dev: flake8, pytest, httpx, etc.
```
```
fastapi==0.111.0
asyncpg==0.29.0
pydantic==2.7.0
python-dotenv==1.0.1
```

**Error handling** — `try/except` только там, где сбой вероятен или критичен. Не оборачивать всё. Доменные ошибки — кастомные исключения, маппинг на HTTP через FastAPI exception handlers (не внутри роутеров):
```python
# core/exceptions.py
class UserNotFoundError(Exception):
    """Raised when a user cannot be found by the given ID."""

class DuplicateEmailError(Exception):
    """Raised when registering with an already-existing email."""
```
```python
@app.exception_handler(UserNotFoundError)
async def user_not_found_handler(request: Request, exc: UserNotFoundError):
    return JSONResponse(status_code=404, content={"detail": "User not found"})
```

**Logging** — стандартный `logging`, никогда `print()` в проде. Конфиг один раз в `main.py` / `core/logging.py`:
```python
import logging
logger = logging.getLogger(__name__)
logger.info("User %s created successfully", user_id)
logger.error("Failed to fetch user %s: %s", user_id, str(e))
```

**Docstrings** — Google-style на всех публичных классах и методах. Приватные (`_`) — только если сложные:
```python
class UserService:
    """Handles all user-related business logic."""

    def create_user(self, data: UserCreate) -> User:
        """Create a new user in the system.

        Args:
            data: Validated user creation payload.

        Returns:
            Newly created User object.

        Raises:
            DuplicateEmailError: If email already exists.
        """
```

**Never do:** Python 2 syntax · `import *` · mutable default args (`def f(items=[])`) · bare `except:` · `print()` для логирования · функции длиннее 50 строк · `type: ignore` без пояснения.

---

## 2. Архитектура

**Стек:**

| Component | Choice |
|-----------|--------|
| Framework | FastAPI |
| DB driver | asyncpg (async) / psycopg2 (sync) |
| Validation | Pydantic v2 |
| Config | pydantic-settings + .env |
| Migrations | Alembic |
| Containerization | Docker + docker-compose |

**Layered structure:**
```
project/
├── app/
│   ├── api/v1/users.py          # FastAPI routers — HTTP layer only
│   ├── services/user_service.py # Business logic
│   ├── repositories/user_repository.py  # Raw SQL only
│   ├── models/user.py           # Pydantic schemas (in/out)
│   └── core/
│       ├── config.py            # Settings via pydantic-settings
│       ├── database.py          # DB connection pool
│       └── exceptions.py        # Custom exceptions
├── migrations/                  # Alembic
├── tests/
├── .env / .env.example / .gitignore
├── docker-compose.yml / Dockerfile
├── requirements.txt / requirements-dev.txt
└── README.md
```

**Ответственность слоёв:** Router — только HTTP (parse → call service → return), ноль бизнес-логики. Service — вся бизнес-логика, вызывает репозитории, кидает доменные исключения. Repository — только доступ к БД (raw SQL), без логики. Models — Pydantic-схемы, **раздельные** для input и output (никогда не переиспользовать одну).

**Async:** `async def` для всех операций БД и внешних API. `def` для чистой CPU-логики без I/O. Никогда не звать блокирующий I/O внутри `async def`.

```python
# core/config.py
from pydantic_settings import BaseSettings
class Settings(BaseSettings):
    DATABASE_URL: str
    SECRET_KEY: str
    DEBUG: bool = False
    class Config:
        env_file = ".env"
settings = Settings()
```
```python
# core/database.py — always pool
import asyncpg
from app.core.config import settings
_pool: asyncpg.Pool | None = None
async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(dsn=settings.DATABASE_URL)
    return _pool
```
```python
class UserCreate(BaseModel):     # Input
    email: str
    password: str
class UserResponse(BaseModel):   # Output
    id: int
    email: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
```

**Never do:** бизнес-логика в роутерах · SQL в сервисах · хардкод конфигов · возврат raw DB rows (всегда сериализовать Pydantic) · `SELECT *` (только конкретные колонки) · один `models.py` на всё (разбивать по доменам).

---

## 3. Frontend — стандарты

Фронтового опыта нет — стек выбирает Claude, дефолт всегда такой:

| Layer | Tool |
|-------|------|
| Framework | React (Vite) |
| Styling | Tailwind CSS |
| Components | shadcn/ui |
| State | React hooks (useState, useReducer) |
| Data fetching | Axios / native fetch |
| Forms | react-hook-form + zod |

**Основной кейс:** CRUD-интерфейсы (формы, таблицы, управление данными).
**Визуал:** минимализм, чисто и просторно; **dark mode по умолчанию**; sans-serif, чёткая иерархия; приглушённая палитра с контрастом где нужно; без декора ради декора.
**Layout:** desktop-first, брейкпоинты Tailwind, min 1024px (деградация до 768px).
**Компоненты:** только функциональные; один компонент на файл; без inline-стилей (только Tailwind); дробить если >150 строк; имена файлов PascalCase (`UserTable.tsx`).
```
src/
├── components/  # Reusable UI
├── pages/       # Route-level
├── hooks/       # Custom hooks
├── services/    # API calls
├── types/       # TS interfaces
└── utils/       # Helpers
```
**Never do:** class-компоненты · inline CSS · хардкод API URL (только env) · компоненты >200 строк без дробления · анимации/декор без запроса · UI-библиотека кроме shadcn/ui без согласования.

---

## 4. Pre-push checklist (перед каждым `git push`)

**Секреты и конфиг:** нет хардкод-секретов нигде · `.env` в `.gitignore` · `.env.example` со всеми переменными (пустые значения) · новые конфиги через `Settings`, не разбросанный `os.getenv()`.
**Git-гигиена:** прочитать `git diff --staged` построчно · нет `print()`/`breakpoint()`/`console.log()` · нет закомментированного кода · сообщение по Conventional Commits.
**Качество:** `flake8 app/ --max-line-length=88` без ошибок · docstrings на всех публичных классах/методах · type hints на сигнатурах · нет глобальных переменных · нет функций >50 строк.
**Архитектура:** логика в `services/` · SQL только в `repositories/` · раздельные in/out схемы · нет `SELECT *`.
**Функциональность:** запускается локально без ошибок · новые эндпоинты проверены через Swagger (`/docs`) или curl · edge-cases (пустой ввод, null, несуществующие записи) · корректные HTTP-коды (404 не 500, 422 не 400).
**Docker:** `docker-compose up --build` без ошибок · новые env в `docker-compose.yml`.
**Docs:** README обновлён если менялись setup/env/архитектура · Mermaid-диаграмма обновлена если менялась структура.

**Git workflow (portfolio standard):** для любого нетривиального изменения — feature-ветка.
```bash
git checkout -b feat/user-authentication
git add -p                 # stage interactively
git diff --staged          # read everything
git commit -m "feat: add JWT auth with refresh tokens"
git push origin feat/user-authentication
# PR on GitHub → merge → clean history for recruiters
```
Рекрутеры смотрят историю коммитов — чистые осмысленные коммиты = сигнал профессионализма.

---

## 5. README и brand voice

**Язык README — всегда английский** (аудитория: международные технические рекрутеры и разработчики). Никакого русского в public-facing (README, docstrings, комментарии).
**Тон:** professional but not dry — senior объясняет свою работу умному junior. ✅ ясно, прямо, с обоснованием решений («I chose X because Y»), с упоминанием что было сложно/что выучил. ❌ корпоративный язык, разжёвывание очевидного, хайп-баззворды («blazing fast», «powerful solution»).

**Структура README (в этом порядке):** (1) заголовок + one-line description · (2) badges (Python version, license, build status) · (3) Why I built this · (4) Key decisions / what I learned · (5) Tech stack · (6) Architecture diagram (Mermaid) · (7) Quick start (copy-paste команды) · (8) API reference (Swagger `/docs` или таблица) · (9) Status.
**Визуал:** badges через shields.io · Mermaid для проектов с 3+ компонентами · скриншот/GIF если есть UI.

**Conventional Commits** — всегда, даже на solo:
```
feat: add JWT authentication endpoint
fix: resolve null pointer in user service
refactor: extract repository layer from service
chore: pin dependency versions in requirements.txt
docs: update README with architecture diagram
```
**Never write:** «This project demonstrates…» · «Feel free to…» · «Please note that…» · русский в public-facing · вложенные bullets глубже 2 уровней.

---

## 6. Поведение Claude при работе с кодом

1. Сначала концепция, потом код.
2. Один лучший вариант — без списка альтернатив (если не просил). Исключение: архитектурные решения → 2–3 варианта с trade-offs.
3. Docstrings на функциях и классах — всегда.
4. В конце кода — предлагать commit message (Conventional Commits).
5. После фичи — предлагать что добавить/обновить в README.
6. Баг/антипаттерн — указывать всегда, без запроса. Чинить только нужное место, не переписывать всё. Коротко: что исправил и почему.
7. После задачи — предлагать следующий логичный шаг + тест-кейсы (pytest).
8. При алгоритмах — объяснять сложность O(n) и почему такой подход.
9. Если код в портфолио — напоминать про README, docstrings, чистоту структуры.
10. Без длинных вступлений перед кодом. Без «Отличный вопрос!».

---

## 7. Interview prep — карта подготовки

**Роль:** Junior Python Backend. Известные форматы: Yandex-style (2× LeetCode Medium за час) · Glowbyte-style (Python internals + SQL + math logic). *(Активировать, когда реально пойду на собеседования — не жёсткий дедлайн.)*

### 🔴 Критично
**1. LeetCode.** Прогрессия Easy → Medium, только Python. Всегда проговаривать подход и Big O до кода. Порядок тем: Arrays & Hashing → Two Pointers → Sliding Window → Binary Search → Linked Lists → Trees (BFS/DFS) → DP (только после остального).
**2. REST API теория (наизусть):** HTTP-методы (GET/POST/PUT/PATCH/DELETE — разница и когда) · коды (200·201·400·401·403·404·422·500) · идемпотентность (GET/PUT/DELETE — да, POST — нет) · statelessness · как это реализует FastAPI.
**3. Python concurrency:** GIL (что, зачем, что предотвращает) · asyncio (I/O-bound, event loop, почему `await` не блокирует) · threading (I/O когда нельзя async) · multiprocessing (CPU-bound, обходит GIL) · конкретный пример выбора каждого.
**4. Alembic migrations:** что такое миграция и чем опасно «поправлю таблицу руками» в проде · `alembic init` / `revision --autogenerate` / `upgrade head` · интеграция в FastAPI + asyncpg. Действие: настроить Alembic в одном проекте.

### 🟡 Важно (нед. 2–3)
**5. SQL сверх базы:** JOIN-ы (INNER/LEFT/RIGHT/FULL OUTER) · subqueries и CTE (`WITH`) · `GROUP BY` + `HAVING` (отличие от `WHERE`) · window functions (`ROW_NUMBER`, `RANK`, `LAG`, `LEAD`) · индексы (B-tree, когда помогают/мешают) · `EXPLAIN ANALYZE`.
**6. Python internals:** decorators (написать с нуля, объяснить `@wraps`) · generators (`yield` vs `return`, ленивость, `next`/`send`) · context managers (`__enter__`/`__exit__`, `contextlib`) · comprehensions · `*args`/`**kwargs` · dunder-методы · mutable vs immutable.

### 🟢 Хорошо иметь (нед. 4+)
**7. FastAPI internals:** DI через `Depends` · middleware · background tasks · lifespan events · Pydantic v2 под капотом.
**8. Soft skills:** «tell me about yourself» (90 сек: background → что построил → почему backend → что дальше) · project walkthrough на 2 проекта · «weakness» (реальное + план) · estimation-вопросы (assumptions → calc → sanity check).

**Уже силён:** OOP (4 столпа с примерами) · Docker (Dockerfile + compose сам) · FastAPI (реальные проекты) · Pydantic (раздельные схемы) · GitHub Actions (базовый CI) · Google-style docstrings.

**Pre-application checklist:** 2+ LeetCode Medium/день ≥2 недели · REST без заметок · asyncio/threading/multiprocessing с примерами · Alembic в одном проекте · все репы: English README + `.env.example` + Conventional Commits · «tell me about yourself» < 2 мин.
