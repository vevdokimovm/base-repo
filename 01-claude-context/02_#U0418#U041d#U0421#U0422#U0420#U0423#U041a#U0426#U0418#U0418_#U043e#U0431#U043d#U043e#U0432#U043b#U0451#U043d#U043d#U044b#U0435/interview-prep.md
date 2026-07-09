# Interview Prep

## Target

**Стратегическая рамка:** подготовка ведёт к **найму под миграцию** (уехать через работу — Скандинавия / Канада? / Япония?). Значит интервью **на английском** + международные форматы (algorithms + system design + behavioral). См. `Миграция_2летний_план.md`.

**Role:** Junior Python Backend Developer
**Timeline:** горизонт 2 года (магистратура + выход на оффер за рубежом); LeetCode и английское техинтервью — критический путь.
**Формат международный:** LeetCode (Easy→Medium), REST/API, system design (junior-уровень), SQL, английский behavioral («tell me about yourself», project walkthrough).
**Формат RU (как запасной сценарий, пока в РФ):** Yandex-style (2× LeetCode Medium за час) · Glowbyte-style (Python internals + SQL + math logic).

---

## Priority Map

### 🔴 Critical — Fix This Week

**1. LeetCode Algorithms**

Zero practice. Yandex-style interviews will eliminate you at the first round without this. Non-negotiable.

- Daily target: 1 problem minimum (Easy → Medium progression)
- Solve in Python only
- Always state the approach and Big O complexity before writing code — interviewers grade the thinking
- Focus topics in order:
  1. Arrays & Hashing
  2. Two Pointers
  3. Sliding Window
  4. Binary Search
  5. Linked Lists
  6. Trees (BFS / DFS)
  7. Dynamic Programming — only after mastering all above

**2. REST API Theory**

You know the term but can't explain it. Asked in 90%+ of backend interviews.

Must know cold:
- HTTP methods: GET / POST / PUT / PATCH / DELETE — difference and when to use each
- Status codes: 200 · 201 · 400 · 401 · 403 · 404 · 422 · 500 — what each means and when to return it
- Idempotency: definition, which methods are idempotent and why (GET, PUT, DELETE — yes; POST — no)
- Statelessness: what it means, why REST requires it
- How FastAPI implements all of this

**3. Python Concurrency**

Confused between asyncio / threading / multiprocessing. This comes up at Glowbyte-type interviews.

Must know:
- **GIL:** what it is, why Python has it, what it prevents
- **asyncio:** for I/O-bound tasks — network, DB calls. Event loop, `async/await`, why `await` doesn't block the loop
- **threading:** I/O-bound when you can't use async. GIL limits CPU parallelism
- **multiprocessing:** CPU-bound tasks only — bypasses GIL by using separate processes
- Be ready to give a concrete example of when you'd choose each

**4. DB Migrations (Alembic)**

You don't know what this is. It's a baseline expectation for any backend role.

Must learn:
- What a migration is and why "just edit the table manually" is dangerous in production
- `alembic init` · `alembic revision --autogenerate -m "add users table"` · `alembic upgrade head`
- How to integrate Alembic into a FastAPI + asyncpg project
- Action: set up Alembic in one existing project this week

---

### 🟡 Important — Week 2–3

**5. SQL Beyond Basics**

You know SELECT/INSERT/UPDATE. You need the next level:

- `JOIN` types: INNER, LEFT, RIGHT, FULL OUTER — when to use each with examples
- Subqueries and CTEs (`WITH` clause)
- `GROUP BY` + `HAVING` — difference from `WHERE`
- Window functions: `ROW_NUMBER()`, `RANK()`, `LAG()`, `LEAD()`
- Indexes: what they are, B-tree structure, when they help and when they slow things down
- `EXPLAIN ANALYZE` — how to read a query execution plan

**6. Python Internals**

Glowbyte asked about this at depth. You need to explain these from scratch:

- **Decorators:** write one from scratch without `functools.wraps`, then explain what `@wraps` does
- **Generators:** `yield` vs `return`, lazy evaluation, memory advantage, `next()`, `send()`
- **Context managers:** `__enter__` / `__exit__`, `contextlib.contextmanager`
- **Comprehensions:** list / dict / set / generator — when to use vs a loop
- **`*args` / `**kwargs`:** how they work, common patterns
- **Dunder methods:** `__init__`, `__str__`, `__repr__`, `__eq__`, `__hash__`, `__len__`
- **Mutable vs immutable:** why `list` is mutable but `tuple` is not, implications for function arguments

---

### 🟢 Good to Have — Week 4+

**7. FastAPI Internals**

- Dependency injection with `Depends` — how the injection tree works
- Middleware — request/response lifecycle
- Background tasks
- Lifespan events (`startup` / `shutdown` handlers)
- How Pydantic v2 validation works under the hood

**8. Soft Skills**

- **"Tell me about yourself"** — prepare a 90-second version: background → what you've built → why backend → what you want next. Practice aloud until it's natural.
- **Project walkthrough:** for 2 portfolio projects — what it does, key technical decision, what you'd do differently now
- **"What's your weakness"** — pick something real with a concrete plan (e.g. "algorithms — I've been solving LeetCode daily for X weeks")
- **Estimation questions (Yandex-style):** "How many red cars in Moscow?" — practice structured thinking: assumptions → calculation → sanity check

---

## Weekly Plan

### Week 1 — Foundation
- LeetCode: 7× Easy (arrays, hashing)
- REST: read RFC / FastAPI docs, write a one-page summary from memory
- Alembic: set up in one existing project, run first migration
- Fix today: add `.env.example` to all repos, switch to Conventional Commits

### Week 2 — SQL + Concurrency
- LeetCode: 5× Easy + 2× Medium (Two Pointers, Sliding Window)
- SQL: write 10 queries using JOINs and GROUP BY against real data
- asyncio: build a small async HTTP client with `httpx`, understand the event loop

### Week 3 — Python Internals
- LeetCode: 5× Medium (Binary Search, Linked Lists)
- Python: write a decorator, a generator, and a context manager from scratch — without looking at docs
- Record yourself answering "tell me about yourself" — listen back and fix weak spots

### Week 4+ — Mock Interviews
- LeetCode: 1× Medium every day, no exceptions
- Practice problems out loud — explain every step as you code
- Do 2–3 mock interviews (use Yandex Contest or ask someone to quiz you)
- Polish 2 portfolio projects — clean commit history, architecture diagrams, English README

---

## What You're Already Strong On

- ✅ OOP — confident, can explain all 4 pillars with Python examples
- ✅ Docker — write Dockerfile and docker-compose yourself
- ✅ FastAPI — building real projects
- ✅ Pydantic — using it correctly with separate input/output schemas
- ✅ GitHub Actions — basic CI already configured
- ✅ Google-style docstrings

---

## Pre-Application Checklist

Before sending your first application:

- [ ] 2+ LeetCode Medium problems solved per day for at least 2 weeks
- [ ] Can explain REST API (methods, status codes, idempotency) without notes
- [ ] Can explain asyncio vs threading vs multiprocessing with examples
- [ ] Alembic set up in at least one project
- [ ] All repos: English README + `.env.example` + Conventional Commits history
- [ ] "Tell me about yourself" answer rehearsed and under 2 minutes
