# Мёрж-манифест v1.6.0 — порт механики и знаний из FINPILOT в base-repo

- **Донор:** приватная репа `personal-finance-dss` (FINPILOT), срез **v5.25.0** (2026-07-09).
- **Приёмник:** `base-repo` v1.5.0 → **v1.6.0**. Вахта M.
- **Задача владельца:** сверить base-repo с механикой FINPILOT (документирование, автоматизация,
  структура, организация), внести недостающее по принципу «all in, отбор потом», добавить
  присланный `publish.sh`, пройтись по списку тезисов владельца (§4).

## 1. Что внесено

| Что | Куда | Происхождение |
|---|---|---|
| `publish.sh` **v2** (идемпотентная доделка, авто-поиск CHANGELOG, fail-loud, `--clobber`; `--auto-asset` сохранён) | `templates/publish.sh` (замена v1) | прислан владельцем |
| Runnable-гейт ревизии (ссылки/`#Uxxxx`/размеры/пустые папки) | `scripts/revision_check.py` (новая папка `scripts/`) | идея — FINPILOT `tools/revision/revision_check.py`, код написан заново под knowledge-репы |
| Протокол живого роадмапа + указатель «СЛЕДУЮЩАЯ ЗАДАЧА» | `00-infrastructure/30-roadmap-protocol.md` | адаптация FINPILOT `roadmap_methodology.md` (Часть I обобщена, Часть II генерализована) |
| Шаблон роадмапа | `templates/ROADMAP_TEMPLATE.md` | новый, по протоколу 30 |
| Библиотека универсальных методичек, 23 файла as-is | `02-methodology-library/` + README-навигатор | FINPILOT `knowledge/guides/` (18) + `docs/` (5); решение — ADR-001 |
| SOP требований ×2 + гайд SRS | `reports/requirements/` | FINPILOT `knowledge/guides/templates/` |
| Шаблон юзабилити-отчёта | `reports/testing/` | там же |
| Инцидент INC-PUBLISH-STUB-NOTES (пустой релиз v1.5.0) | `reports/incidents/` + строка в реестре | обнаружен этим батчем |
| Разделы: доставка файлов из Claude · сбой канала тул-коллов · упаковка архивов с обёрткой | `15-gotchas-claude-git.md` §2/§14/§15 | уроки FINPILOT PIT-009(доставка)/PIT-004/INC-FWD-BUILD-WIPEOUT |
| Строки «Ситуация-репорт» и «Эксперимент» в диспетчере | `19-reporting-system.md` §1 | синк с `reports/report_types.md` (расхождение таблиц) |
| Триггеры: указатель роадмапа · запуск гейта · доставка | `08-automation-triggers.md` | по новым докам |

## 2. Что НЕ внесено (и почему — чтобы не переоткрывать)

| Донор (FINPILOT) | Причина пропуска |
|---|---|
| `knowledge_capture_protocol.md`, `volume_compression_methodology.md`, `writing_guides_methodology.md`, `fork_merge_methodology.md`, `repo_revision_methodology.md`, `session_continuity` | уже портированы ранее = доки `20 / 06 / 07 / 22 / 21 / 23` |
| `documentation_methodology.md` (docs/) | уже в `reports/documentation_methodology.md` (md5 расходится с донором из-за прежней адаптации — содержательно тот же док) |
| `claude_infrastructure_methodology.md` | зона покрыта доками `02/13/14/16/26/27/29`; дублировать вредно |
| `roadmap_methodology.md` как файл | вошёл адаптацией в `30`, копия был бы дубль |
| `financial_recommendation_benchmarks.md`, `onboarding/glossary/QA/SLO/api_contract/backup_restore/pdn_data_map/mirror_publishing_guide` и прочие `docs/` продукта | продукт-специфика FINPILOT, не универсалии |
| FINPILOT `tools/` (portrait_testing, timewarp, survey_analysis…) | инструменты продукта; универсальная идея (runnable-гейт) перенесена кодом `scripts/revision_check.py` |

## 3. Решения адаптации

1. **Библиотека, а не `00-infrastructure/`** — предметные знания отделены от правил игры (ADR-001).
2. Файлы библиотеки — **as-is, с FINPILOT-примерами**: боевые примеры ценнее стерильности;
   генерализация — на ревизии при растаскивании.
3. `revision_check.py` написан заново (донорский гейт проверяет docs↔code продукта — счётчики
   таблиц/миграций/OpenAPI, сюда неприменимо). Общая философия сохранена: живое проверяем,
   замороженное пропускаем, exit 0/1, allowlist.
4. Шаблоны требований/юзабилити уехали в свои типовые папки `reports/`, а не в библиотеку —
   у них уже есть дом по диспетчеру `19`.

## 4. Сверка с тезисами владельца (постановка задачи)

| Тезис | Статус в base-repo |
|---|---|
| Система автоматических репортов по триггерам | было (`19`+`20`+`reports/`), дополнено строками ситуаций/экспериментов в `19` §1 |
| В каждой репе WATCHLOG + подробный changelog | было: протоколы `04`/`24`, шаблоны `03`/`CHANGELOG_TEMPLATE`, шаг 3 START-HERE |
| Слово «репорт/методичка/…» = сразу подробный `.md` | было: `18` §3 + строка в `08` |
| Папки под каждый вид репорта, логично сгруппированные | было (`reports/<тип>/`), дополнено реальными шаблонами requirements/testing |
| Философия и правила, выведенные в FINPILOT | было (`18`), дополнено: роадмап `30`, доставка/упаковка/тул-коллы в `15` |
| Информация про 4 аккаунта | было: `04` + `WATCHLOG §1` + `18` §7 |
| «Больше = лучше», любовь к шаблонам/автоматике | было: `18` §2/§8; принцип применён этим же батчем (all in) |
| Алгоритм ревизий и мёржей | было (`21`/`22`); ревизия теперь ещё и **исполняемая** (`scripts/revision_check.py`) |
| ВСЕ методички/гайды/шаблоны — all in | сделано: `02-methodology-library/` (23) + шаблоны в `reports/` (4); пропуски обоснованы в §2 |
| Добавить присланный скрипт | сделано: `templates/publish.sh` v2 |

## 5. Гейты приёмки батча

`bash -n templates/publish.sh` чисто · `python3 -m py_compile scripts/revision_check.py` чисто ·
`python3 scripts/revision_check.py` по самой репе = CLEAN (после починки найденного им же
класса плейсхолдеров в шаблонах — гейт догфудится) · окно `WATCHLOG §3` = 10 · версия/летопись/журнал
синхронны.
