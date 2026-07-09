# project-setup.md — день первый нового проекта

> Не правила стиля, а **процедура**: что сделать в первый час нового backend-проекта, чтобы стартовать одинаково чисто. Операционализирует все остальные стандарты. Кладётся в `docs/`.

---

## Чеклист старта (по порядку)

1. **Репозиторий и структура папок** (слоёная архитектура):
```
project/
├── app/
│   ├── api/v1/            # роутеры — только HTTP
│   ├── services/          # бизнес-логика
│   ├── repositories/      # доступ к БД (raw SQL / ORM)
│   ├── models/            # Pydantic-схемы (раздельно in/out)
│   └── core/
│       ├── config.py      # Settings (pydantic-settings)
│       ├── database.py    # пул соединений
│       └── exceptions.py  # кастомные исключения
├── migrations/            # Alembic
├── tests/
├── docs/
├── .env.example
├── .gitignore
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
├── requirements-dev.txt
└── README.md
```

2. **`.env.example`** — сразу, со всеми переменными (пустые значения). `.env` — в `.gitignore`.
```
DATABASE_URL=
SECRET_KEY=
DEBUG=False
```

3. **`.gitignore`** — под стек (Python cache, venv, IDE, `.env`, macOS-артефакты).

4. **`requirements.txt` / `requirements-dev.txt`** — split, версии пинить:
```
# requirements.txt
fastapi==0.111.0
uvicorn==0.30.0
pydantic==2.7.0
pydantic-settings==2.3.0
python-dotenv==1.0.1
# requirements-dev.txt
flake8==7.1.0
pytest==8.2.0
httpx==0.27.0
```

5. **Пустой FastAPI + healthcheck + подключение к БД**:
```python
# app/main.py
from fastapi import FastAPI
app = FastAPI(title="project")

@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
```

6. **`docker-compose.yml`** — сервис приложения + БД (Postgres):
```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports: ["5432:5432"]
  app:
    build: .
    env_file: .env
    ports: ["8000:8000"]
    depends_on: [db]
```

7. **Alembic** — инициализировать сразу (`alembic init migrations`), настроить `env.py` на `DATABASE_URL` из Settings.

8. **CI-workflow** (`.github/workflows/ci.yml`) — базовый: install → flake8 → pytest.

9. **Скелет README** — по шаблону `brand-voice.md` (заголовок, бейджи, Why I built this, tech stack, quick start, status). На английском.

10. **Первый коммит осмысленный:**
```bash
git init -b main
git add .
git commit -m "feat: initial project scaffold (structure, config, healthcheck, docker, CI)"
git remote add origin https://github.com/vevdokimovm/<repo>.git
git push -u origin main
```

---

## Проверка «готов стартовать»
- [ ] `docker-compose up --build` поднимается без ошибок
- [ ] `/health` отвечает
- [ ] подключение к БД работает
- [ ] flake8 и pytest проходят в CI
- [ ] README + `.env.example` на месте
