# Python Backend Code Standards

## Python Version

Python 3.11+ only. Never Python 2 syntax.

## Code Style

| Rule | Standard |
|------|----------|
| Naming | PEP 8 strict — snake_case vars/funcs, PascalCase classes, UPPER_CASE constants |
| Structure | OOP — classes and objects |
| Type hints | Function signatures only (args + return type) |
| Line length | 88 chars max |
| Comments | Minimal — self-documenting code preferred |
| Global vars | Never |
| Secrets | Always via .env — never hardcoded |

## Linting

Currently using **Flake8**. Migration to **Ruff** recommended — it's 10-100× faster and replaces Flake8 + isort + Black in one tool.

```bash
# Run before every commit
flake8 app/ --max-line-length=88
```

## Dependency Management

Keep split by environment:

```
requirements.txt          # Production only
requirements-dev.txt      # Dev tools: flake8, pytest, httpx, etc.
```

Always pin versions:
```
fastapi==0.111.0
asyncpg==0.29.0
pydantic==2.7.0
python-dotenv==1.0.1
```

## Error Handling

Only use `try/except` where failure is likely or critical. Don't wrap everything.

Create custom exceptions for domain errors:

```python
# core/exceptions.py
class UserNotFoundError(Exception):
    """Raised when a user cannot be found by the given ID."""

class DuplicateEmailError(Exception):
    """Raised when registering with an already-existing email."""
```

Map domain exceptions to HTTP responses via FastAPI exception handlers — not inside routers:

```python
@app.exception_handler(UserNotFoundError)
async def user_not_found_handler(request: Request, exc: UserNotFoundError):
    return JSONResponse(status_code=404, content={"detail": "User not found"})
```

## Logging

Use standard `logging` — never `print()` in production code:

```python
import logging

logger = logging.getLogger(__name__)

logger.info("User %s created successfully", user_id)
logger.warning("Retry attempt %d for user %s", attempt, user_id)
logger.error("Failed to fetch user %s: %s", user_id, str(e))
```

Configure logging once in `main.py` or `core/logging.py`.

## Docstrings

**Google-style on all public classes and methods:**

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

Private methods (prefixed with `_`) don't require docstrings unless complex.

## What Claude Should Never Do

- Use Python 2 syntax (`print "x"`, `except Exception, e:`)
- Use `import *`
- Use mutable default arguments (`def f(items=[])`)
- Catch bare `except:` without specifying exception type
- Use `print()` for logging in any non-script code
- Write functions longer than 50 lines — refactor into smaller pieces
- Use `type: ignore` comments without explanation
