# Architecture Patterns

## Backend Stack

| Component | Choice |
|-----------|--------|
| Framework | FastAPI |
| DB driver | asyncpg (async) / psycopg2 (sync) |
| Data validation | Pydantic v2 |
| Config | pydantic-settings + .env |
| Migrations | Alembic |
| Containerization | Docker + docker-compose |

## Project Structure (Layered Architecture)

```
project/
├── app/
│   ├── api/
│   │   └── v1/
│   │       └── users.py        # FastAPI routers — HTTP layer only
│   ├── services/
│   │   └── user_service.py     # Business logic
│   ├── repositories/
│   │   └── user_repository.py  # Raw SQL queries only
│   ├── models/
│   │   └── user.py             # Pydantic schemas (input/output)
│   └── core/
│       ├── config.py           # Settings via pydantic-settings
│       ├── database.py         # DB connection pool
│       └── exceptions.py       # Custom exception classes
├── migrations/                 # Alembic migration files
├── tests/
├── .env
├── .env.example
├── .gitignore
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
├── requirements-dev.txt
└── README.md
```

## Layer Responsibilities

**Router (`api/`)** — HTTP only. Parse request, call service, return response. Zero business logic.

**Service (`services/`)** — All business logic. Calls repositories, applies rules, raises domain exceptions.

**Repository (`repositories/`)** — DB access only. Raw SQL via asyncpg/psycopg2. No business logic.

**Models (`models/`)** — Pydantic schemas. Separate schemas for input and output. Never reuse the same schema for both.

## Async Strategy

- Use `async def` for all DB operations and external API calls
- Use `def` for pure CPU-bound logic with no I/O
- Never call blocking I/O inside an `async def` function

## Config Pattern

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

## DB Connection Pattern

```python
# core/database.py — always use connection pooling
import asyncpg
from app.core.config import settings

_pool: asyncpg.Pool | None = None

async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(dsn=settings.DATABASE_URL)
    return _pool
```

## Pydantic Model Pattern

```python
class UserCreate(BaseModel):    # Input — from request body
    email: str
    password: str

class UserResponse(BaseModel):  # Output — returned in response
    id: int
    email: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
```

## What Claude Should Never Do

- Put business logic in routers
- Put SQL queries in services
- Hardcode any config values — always use Settings
- Return raw DB rows — always serialize with Pydantic
- Write `SELECT *` — always select specific columns
- Create a single `models.py` file for everything — split by domain
