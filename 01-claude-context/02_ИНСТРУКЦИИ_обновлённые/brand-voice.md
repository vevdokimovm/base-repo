# Brand Voice & Communication Standards

## README Language

**Always English.** Target audience: international technical recruiters and developers on GitHub.

## Tone

**Professional but not dry.** Think: senior developer explaining their work to a smart junior — not a corporate memo, not a casual blog post.

- ✅ Clear, direct, confident
- ✅ Shows reasoning behind decisions ("I chose X because Y")
- ✅ Mentions what was learned or what was hard
- ❌ Formal corporate language
- ❌ Over-explaining obvious things
- ❌ Hype / buzzwords without substance ("blazing fast", "powerful solution")

## README Structure (Standard Template)

Every public project README must include in this order:

1. **Project title + one-line description**
2. **Badges** — Python version, license, build status (GitHub Actions)
3. **Why I built this** — personal motivation, problem being solved
4. **Key decisions / what I learned** — architecture tradeoffs, interesting choices
5. **Tech stack** — table or list
6. **Architecture diagram** — Mermaid preferred (renders in GitHub natively)
7. **Quick start** — copy-pasteable commands to run locally
8. **API reference** — link to Swagger (`/docs`) or endpoint table
9. **Status** — e.g. "MVP complete — auth and CRUD working, planning X next"

## Visual Elements

Always include:
- **Badges** via shields.io — Python version, license, last commit, build status
- **Mermaid diagrams** for any project with 3+ components
- **Screenshot or demo GIF** if there's a UI

## Docstring Standard

Format: **Google-style** on all public classes and methods.

```python
def get_user(user_id: int) -> User:
    """Fetch a user by ID from the database.

    Args:
        user_id: The unique identifier of the user.

    Returns:
        User object with all fields populated.

    Raises:
        UserNotFoundError: If no user exists with the given ID.
    """
```

## Commit Messages

Follow **Conventional Commits** always — even on solo projects:

```
feat: add JWT authentication endpoint
fix: resolve null pointer in user service
refactor: extract repository layer from service
chore: pin dependency versions in requirements.txt
docs: update README with architecture diagram
```

## What Claude Should Never Write

- "This project demonstrates..." (passive, weak opener)
- "Feel free to..." (too casual for professional README)
- "Please note that..." (filler phrase)
- Russian in any public-facing content (README, docstrings, comments)
- Nested bullet points more than 2 levels deep
