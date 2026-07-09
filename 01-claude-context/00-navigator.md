# 📁 Единый кит контекста — Василий Евдокимов

> Всё сведено в одну структуру. Актуально: июль 2026. Как разворачивать — см. `how-to-use.md`.

---

## Структура

### Корень
| Файл | Что это |
|------|---------|
| `how-to-use.md` | Куда что грузить (3 слоя). Читать первым. |
| `00-navigator.md` | Этот файл. |
| `bundle-core-profile.md` | Конкатенация: ядро + все профильные блоки. Для обзора/переноса, не для Preferences. |
| `bundle-all.md` | Конкатенация всего (кроме инфра-кита). Архив/обзор, не для Preferences. |

### `00-core/`
| Файл | Что это |
|------|---------|
| `context-vasilii-unified.md` | **Главный файл-источник истины.** Полный. → в Preferences. |
| `context-preferences-edition.md` | Облегчённая версия (7K) на случай лимита. |
| `memory-all-accounts.md` | Сжатая память → в Memory. |
| `memory-export-other-ai.md` | Портируемый профиль для ChatGPT/Gemini и т.п. |
| `standards-code-career.md` | Техсвод (код, архитектура, интервью). |
| `cowork-global-instructions.md` | Слой Cowork Global (Настройки → Cowork): самодостаточное always-on ядро для агентных сессий. |

### `01-blocks/` — глубокие блоки (по контексту)
| Файл | Что это |
|------|---------|
| `migration-2year-plan.md` | 🎯 Приоритет №1. Магистратура + миграция. |
| `health-clinical-portrait.md` | Подробный медблок. |
| `education.md` | Школа → вуз → магистратура. |
| `walk-with-jesus-christ.md` | 🔒 Вера: путь, страсти, вопросы, исповеди. Приватное, вне общего always-on. |
| `personal-appearance-analysis.md` | 🔒 Приватный фреймворк. Вне общего always-on. |

### `02-instructions/` — 14 исходных инструкций, обновлены
Личные: `CLAUDE.md`, `Memory.md`, `Context.md`, `psychology.md`, `tone-of-voice.md`, `my-character.md`, `interview-prep.md`.
Технические: `python-backend.md`, `architecture.md`, `code-review.md`, `frontend-design.md`, `brand-voice.md`, `Skills.md`, `Agents.md`.

### `03-project-docs/` — в `docs/` проекта
`project-setup` · `data-model` · `decisions` (ADR) · `api-design` · `sql-database` · `security` · `learning-log` · `project-brief`.

### Инфраструктура base-repo — в корне репы
Инфра-кит (`START-HERE`, `00-infrastructure/`, `templates/`, `repos-map`) слит с актуальной версией и живёт в **корне `base-repo`** (уровнем выше этого кита). Отдельная папка `04_ИНФРАСТРУКТУРА_base-repo/` внутри кита упразднена — источник правды один.

### `04-chat-analysis/` — анализ поведения по аккаунтам
`Анализ_чатов_ОБЩИЙ` + `_V` / `_S` / `_J` / `_M`.

---

## Что нового в этой версии
- **Вера расширена:** отдельная методичка `walk-with-jesus-christ.md` (обработаны реальные исповеди/страсти/вопросы); в ядре вера подана как **полный коммитмент всей жизни**, а не «просто верю».
- **`self-map` = ещё и личный дневник** (рефлексия) — отмечено везде, где упоминается система репо.
- **Файл `how-to-use.md`** — 3-слойное распределение (Project knowledge / Preferences / Memory).
- **Анализ чатов** — 5 файлов (общий + по аккаунтам): V — база, S — систематизатор, J/M — дев-смены.
- **Две сборки-конкатенации** (ядро+профиль и всё) — на случай нужды в одном файле.
- Полный `КОНТЕКСТ` заканчивается директивной строкой (мой стиль).
