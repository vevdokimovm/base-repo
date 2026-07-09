# 02-methodology-library — библиотека универсальных методичек

> **Что это.** Общий фонд предметных методичек, гайдов и справочников, перенесённых из
> FINPILOT (донор — приватная репа `personal-finance-dss`, срез v5.25.0, 2026-07-09).
> Решение о переносе и его логика — `../reports/adr/adr_001_methodology_library.md`;
> полная карта «что взято / что пропущено / почему» — `../reports/merges/merge_manifest_v1_6_0.md`.
>
> **Принцип — «all in, отбор потом»** (`18-documentation-philosophy.md` §2): лучше внести всё
> универсальное сразу и убрать лишнее на ревизии, чем выбирать сейчас и потерять. Файлы внесены
> **as-is** (имена и содержимое донора, включая боевые примеры из FINPILOT — они намеренно
> оставлены как живые иллюстрации). Инфраструктура реп сюда НЕ входит — она в `00-infrastructure/`.

## Судьба библиотеки (правило ревизии)

При плановой ревизии (`21-revision-protocol.md`) каждый файл получает один из исходов:
**остаётся** (нужен всем репам как общий фонд) · **переезжает** в тематическую репу из колонки
«кандидат» · **сливается** с существующим доком · **удаляется** (устарел/не пригодился).
До ревизии — ничего не выбрасывать.

## Навигатор

| Файл | Про что | Кандидат-репа при растаскивании |
|---|---|---|
| `architecture_guide.md` | Проектирование архитектуры ПО: слои, компоненты, приёмы | `it-base` |
| `audience_research_guide.md` | Исследование аудитории: методы, протоколы интервью, опросники | `it-base` / `misc-vault` |
| `business_models_guide.md` | Бизнес-модели: типы, выбор, юнит-экономика | `it-base` / `misc-vault` |
| `business_schemas_processes_methodology.md` | Бизнес-схемы и процессы: нотации, как рисовать | `it-base` |
| `color_contrast_accessibility_methodology.md` | Цвет, контраст, доступность UI (WCAG) | `it-base` |
| `cybersecurity_methodology.md` | Кибербезопасность: модели угроз, практики, чек-листы | `it-base` |
| `dev_methodologies_principles.md` | Методологии/принципы разработки (Agile, YAGNI, приоритизация) | `it-base` |
| `development_process_methodology.md` | Процесс разработки: канон ROADMAP+WATCHLOG, task-tracking | остаётся (родня докам 04/19/24) |
| `diagrams_notations_gost_methodology.md` | Диаграммы, нотации, ГОСТы (UML, C4, ER, draw.io-грабли) | `it-base` |
| `expertise_social_promotion_methodology.md` | Заход через экспертность, продвижение в соцсетях | `misc-vault` |
| `incident_process_documentation_methodology.md` | Документирование инцидентов и процессов (расширенная теория) | остаётся (пара к `reports/documentation_methodology.md`) |
| `languages_tools_production_methodology.md` | Языки и инструменты в продакшене IT | `it-base` |
| `market_analysis_reference.md` | Анализ рынка: TAM/SAM/SOM, бенчмарки, источники | `it-base` / `misc-vault` |
| `research_analysis_academic_methodology.md` | Анализ исследований: академический фокус | `edu-base` |
| `research_analysis_business_methodology.md` | Анализ исследований: бизнес-метрики | `it-base` |
| `scientific_article_gost.md` | Научная статья по ГОСТ: структура, оформление, подача | `edu-base` / `academic-portfolio` |
| `software_lifecycle_standard.md` | Стандарт управления жизненным циклом программного комплекса | `it-base` |
| `team_roles_process_methodology.md` | Команда, роли, процесс и контроль задач в IT | `it-base` |
| `naming_convention.md` | Конвенция имён code-репы (файлы, отчёты, миграции) — образец | остаётся (референс для code-реп) |
| `sandbox_runbook.md` | Раннбук песочницы Claude: готовые команды, известные грабли | остаётся (сквозной инструмент) |
| `tool_call_channel_failures.md` | Сбой канала тул-коллов Claude: симптомы и протокол | остаётся (выжимка — `15-gotchas` §14) |
| `engineering_practices.md` | Инженерные практики code-репы: TDD, гейты, DoD — образец | остаётся (референс для code-реп) |
| `test_run_optimization.md` | Что гонять и когда: узкий цикл vs полный прогон тестов | остаётся (референс для code-реп) |

> Шаблоны требований (`requirements_sop*.md`, `srs_guide.md`) и юзабилити-отчёта уехали не сюда,
> а в свои типовые папки — `../reports/requirements/` и `../reports/testing/` (диспетчер `19` §1).
