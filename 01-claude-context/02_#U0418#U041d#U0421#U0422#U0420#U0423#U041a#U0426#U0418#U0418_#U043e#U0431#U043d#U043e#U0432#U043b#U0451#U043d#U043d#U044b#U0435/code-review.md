# Pre-Push Checklist

Run through this before every `git push`. No exceptions.

---

## 1. Secrets & Config

- [ ] No hardcoded secrets, passwords, API keys, or DB URLs anywhere in code
- [ ] `.env` is listed in `.gitignore`
- [ ] `.env.example` exists and includes all variables the project needs (with empty values)
- [ ] All new config values loaded via `Settings` — not `os.getenv()` scattered around

## 2. Git Hygiene

- [ ] Run `git diff --staged` and read every changed line before committing
- [ ] No debug leftovers: `print()`, `breakpoint()`, `console.log()`
- [ ] No commented-out code
- [ ] Commit message follows Conventional Commits:

```
feat: add user registration endpoint
fix: handle missing user_id in service
refactor: move SQL queries into repository layer
chore: update requirements.txt
docs: add architecture diagram to README
```

## 3. Code Quality

- [ ] `flake8 app/ --max-line-length=88` passes with zero errors
- [ ] All public classes and methods have Google-style docstrings
- [ ] Type hints on all function signatures
- [ ] No global variables introduced
- [ ] No function longer than 50 lines

## 4. Architecture

- [ ] Business logic lives in `services/` — not in routers or repositories
- [ ] SQL queries live only in `repositories/`
- [ ] New Pydantic models have separate input and output schemas
- [ ] No `SELECT *` in any SQL query

## 5. Functionality

- [ ] Code runs locally without errors
- [ ] All new endpoints tested via Swagger UI (`/docs`) or curl
- [ ] Edge cases handled: empty input, null values, non-existent records
- [ ] Error responses return correct HTTP status codes (404 not 500, 422 not 400, etc.)

## 6. Docker

- [ ] `docker-compose up --build` completes without errors
- [ ] New env variables added to `docker-compose.yml` under `environment:`

## 7. Documentation

- [ ] README updated if setup steps, environment variables, or architecture changed
- [ ] Mermaid diagram updated if component structure changed

---

## Git Workflow (Portfolio Standard)

For any non-trivial change, use a feature branch:

```bash
git checkout -b feat/user-authentication
# ... develop ...
git add -p                     # Stage interactively — review each chunk
git diff --staged              # Read everything before committing
git commit -m "feat: add JWT auth with refresh tokens"
git push origin feat/user-authentication
# Open PR on GitHub → merge → clean history for recruiters to read
```

**Why this matters:** Recruiters look at your commit history. Clean, meaningful commits signal that you work like a professional — not like someone pushing WIP to main.
