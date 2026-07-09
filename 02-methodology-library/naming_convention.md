# Конвенция именования (Naming Convention)

Как называются документы и файлы в репозитории FINPILOT. Цель — чтобы по имени сразу понимать
что это, и чтобы структура читалась с нуля любым, кто открыл репо.

---

## 1. Базовые правила

1. **Язык — английский.** Имена файлов и папок на английском, даже если содержимое на русском.
   (Содержимое — по стилю проекта: русская проза + английский код/термины.)
2. **Регистр — `snake_case`.** Слова строчными, разделены подчёркиванием: `product_philosophy.md`,
   `crud_delete_incident.md`. Никаких пробелов, `CamelCase` или `kebab-case` в именах.
3. **Без префикса `FINPILOT_`.** Репозиторий и так про FINPILOT — префикс избыточен.
   `FINPILOT_cybersecurity_guide.md` → `cybersecurity_guide.md`.
4. **Без эмодзи, кириллицы, спецсимволов** в именах (тире `—`/`–`, скобки, `→`). Только
   `[a-z0-9_]` и расширение. Исключение — **сырьё данных** (напр. выгрузки опроса в `raw/`),
   где имя файла может нести человекочитаемый контекст.
5. **Расширение по сути:** `.md` — документация/тексты (**канон в репо**); `.docx` — экспортные
   документы-артефакты (юр-документы, инструкции для людей) — **у владельца, в репо не коммитятся**
   (источник живёт в `.md`); `.py`/`.sh` — код/скрипты; `.drawio`/`.png`/`.svg`
   — диаграммы и изображения.

---

## 2. Версии в имени

- Версия в имени — только если хранятся **несколько версий одного документа** и это осмысленно:
  суффикс `_vN` (`logo_passport.md` — актуальная, история при необходимости `_v2`).
- **Актуальная версия — без номера** (`logo_passport.md`), исторические — с номером.
  Правило: последняя/актуальная всегда доступна по «чистому» имени.
- Для кода версия в имени не нужна — её несёт `APP_VERSION` и git-теги.

---

## 3. Именование по типам

| Что | Шаблон имени | Пример |
|---|---|---|
| Отчёт-инцидент | `<тема>_incident.md` / `<тема>_incident_postmortem.md` | `postgres_incident_postmortem.md` |
| Расследование | `<тема>_investigation.md` | `browsers_sandbox_investigation.md` |
| ADR | `adr_<NNN>_<тема>.md` | `adr_002_datetime_storage.md` |
| Merge-отчёт | `merge_manifest_<версия>.md` | `merge_manifest_v4_30_2.md` |
| Методичка/руководство | `<тема>_methodology.md` / `<тема>_guide.md` | `cybersecurity_methodology.md` |
| Справочник | `<тема>_reference.md` | `market_analysis_reference.md` |
| Стандарт | `<тема>_standard.md` | `software_lifecycle_standard.md` |
| Шаблон артефакта | `<артефакт>_template.md` / `<артефакт>_guide.md` | `bug_report_template.md`, `srs_guide.md` |
| Юр-документ (RU) | `<документ>.md` (в репо); `.docx`-экспорт — у владельца | `privacy_policy.md` |
| Эталон лого | `logo_reference[_<что>].<ext>` | `logo_reference.png` (1200px; HQ-исходник у владельца) |
| Диаграмма | `<NN>_<тема>[_GOST].drawio` | `04_c4_context.drawio` |

---

## 4. Структура папок (куда что кладём)

- **`app/`** — код приложения. Не для документации.
- **`docs/`** — техническая документация репозитория (про код и разработку):
  `engineering_practices.md`, `math_model_v3_0_0.md`, ADR-навигация, `diagrams/`, и т.п.
  - **`docs/reports/`** — все отчёты, по типам: `adr/`, `incidents/`, `investigations/`, `merges/`.
  - **`docs/diagrams/`** — диаграммы архитектуры и модели (`.drawio` + превью).
- **`knowledge/`** — не-кодовая база знаний проекта:
  `business/` (+ `business/pitch/`, `business/diagrams/`), `survey_auditory/` (+ `raw/`, `results/`),
  `legal/`, `guides/` (+ `guides/templates/`), `product/`, `brand/`, `project_meta/`.
- **`tools/`** — вспомогательные скрипты/программы: `publish/`, `cost_tracker/`, `survey_analysis/`,
  `post_render/`.

---

## 5. Перевод русских имён — примеры

| Было (рус) | Стало |
|---|---|
| `FINPILOT Философия продукта.md` | `product_philosophy.md` |
| `Методичка_по_кибербезопасности.md` | `cybersecurity_methodology.md` |
| `FINPILOT_оценка_бизнес-моделей.md` | `business_models_evaluation.md` |
| `Справочник- анализ рынка ....md` | `market_analysis_reference.md` |
| `Стандарт управления жизненным циклом ....md` | `software_lifecycle_standard.md` |
| `FINPILOT_юридический_разбор.md` | `legal_analysis.md` |

**Принцип перевода:** брать суть документа, а не дословный перевод заголовка. Имя — короткое,
из 2–4 слов, отражает содержание и тип.
