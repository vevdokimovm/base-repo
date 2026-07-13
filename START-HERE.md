# START HERE — `base-repo`, базовый класс для всех knowledge-реп

> 🔴 **Claude: перед любым действием — [`00-CLAUDE-STOP.md`](00-CLAUDE-STOP.md).**
> Обрыв канала tool-call (`court` + сырой `<invoke>`) — самая частая поломка процесса,
> и она управляется поведением. Прочитать до первого вызова инструмента.

> `base-repo` — это **базовый класс** твоей системы репозиториев (в терминах ООП):
> один источник истины для правил, нейминга, стандартов и протоколов. Все тематические
> репы (`academic-portfolio`, `it-base`, `truth-seeking`, `edu-base`, …) **наследуют**
> эти правила и при необходимости переопределяют под себя. Меняешь правило один раз
> здесь — а не в 10 репах.
>
> Здесь же живёт **`repos-map.md`** — карта всех твоих репозиториев (какая репа за что
> отвечает). Её законное место — в репе-про-репы.

## Что это

`base-repo` — отдельная репа-родитель. Содержит: инфраструктурную документацию
(`00-infrastructure/`), шаблоны (`templates/`) и карту реп (`repos-map.md`). Репы у
тебя разные по теме, но **инфраструктура у всех одна** — она описана здесь, а не
дублируется по репам.

Ключевая идея (базовый класс):
- **base-repo** задаёт дефолтное поведение — как называть, как хранить, как сжимать, как вести журнал.
- **Тематическая репа** наследует это и добавляет своё (контент + при нужде свои уточнения правил).
- **Одно изменение правила** в base-repo → применяется ко всем (перечитал и следуешь), а не правишь 10 копий.

Ключевой принцип всего кита (он же — главная боль, которую он лечит):

> **База знаний ценна не объёмом, а актуальностью, отсутствием дублей, обобщённостью
> и лёгкостью. Большой сырой файл → тезисный `.md` с полной сутью и логикой. Всё, что
> генерируется или дублируется — вон. Всё, что читается один раз — в тезис.**

## Как применить к репе (5 шагов)

1. Распакуй кит в корень репы. Появятся `00-infrastructure/` (документация-правила),
   `templates/` (шаблоны) и `reports/` (система отчётности: шаблоны, гайды, реестры, папки по типам).
2. Возьми `templates/REPO_README_TEMPLATE.md` → заполни под конкретную репу →
   положи как корневой `README.md`. Возьми `templates/gitignore.template` → `.gitignore`.
3. Возьми `00-infrastructure/03-watchlog-template.md` → скопируй в `00-infrastructure/WATCHLOG.md`,
   впиши текущее состояние репы (аккаунты V/J/M/S уже прописаны). Возьми
   `templates/CHANGELOG_TEMPLATE.md` → `CHANGELOG.md` — подробная append-only летопись
   (`24-changelog-protocol.md`). Журнал + changelog — разные инструменты (снимок «где мы» vs история).
   Если у репы есть направление на несколько этапов — возьми `templates/ROADMAP_TEMPLATE.md` →
   `ROADMAP.md` с указателем «СЛЕДУЮЩАЯ ЗАДАЧА» (`30-roadmap-protocol.md`).
4. Прочитай `00-infrastructure/README.md` (карта правил, порядок чтения) и
   `00-infrastructure/18-documentation-philosophy.md` (дух: «больше = лучше», слово = триггер на
   `.md`). Система отчётности — `19`–`24` + `reports/README.md`.
5. Первый этап работы с уже загруженной репой — **ревизия по правилам** (`21-revision-protocol.md`),
   механику открывает гейт `python3 scripts/revision_check.py` (битые ссылки, `#Uxxxx`, размеры);
   дальше смысловые оси: `06-volume-compression.md` (тяжёлое → `.md`) + `05-knowledge-base-rules.md`
   (дубли/устаревшее/обобщение). Дальше — веди по журналу, changelog и триггерам; отчёты по событиям
   создавай автоматически (`19`, `20`).
6. Выпуск версий (когда репе нужны релизы): скопируй `templates/publish.sh` в корень, задай `VERSION`
   (а весь путь «архив от Claude → запушенная репа с тегом и Release» закрывает одна команда
   `zsh templates/deploy_from_zip.sh <zip>` — `25` §3)
   и веди `CHANGELOG.md`. Релиз — одной командой: `zsh publish.sh --minor` (или `--patch`/`--major`/
   `--version X.Y.Z`) → бамп → коммит → тег → пуш → GitHub Release с описанием из `CHANGELOG`. Правила
   — `00-infrastructure/25-versioning-and-releases.md`.

## Карта base-repo

| Путь | Что внутри |
|---|---|
| `START-HERE.md` | Этот файл — вход и порядок применения |
| `repos-map.md` | **Карта всех репозиториев** — какая репа за что отвечает |
| `00-infrastructure/README.md` | Навигатор инфраструктуры: карта правил, порядок чтения |
| `00-infrastructure/01-repo-standard.md` | Стандарт репы: нейминг (00/01), блоки, README, публикация HTTPS |
| `00-infrastructure/02-claude-workflow.md` | Работа с Claude: поверхности, лимиты файлов, RAG, модель/effort, триггеры |
| `00-infrastructure/03-watchlog-template.md` | Шаблон журнала на N аккаунтов (копируется в `WATCHLOG.md`) |
| `00-infrastructure/04-watchlog-protocol.md` | Как вести журнал и передавать контекст между аккаунтами/сессиями |
| `00-infrastructure/05-knowledge-base-rules.md` | Правила ведения: актуальность, без дублей, обобщённость, лёгкость, жизненный цикл |
| `00-infrastructure/06-volume-compression.md` | Протокол сжатия больших файлов в тезисные `.md` |
| `00-infrastructure/07-writing-methodology.md` | Как писать методички, справочники, правила |
| `00-infrastructure/08-automation-triggers.md` | Триггеры «событие → действие» + советы |
| `00-infrastructure/09-template-repository.md` | Как заводить новые репы из `base-repo` («Use this template») |
| `00-infrastructure/10-git-reference.md` | Git: устройство, лимиты GitHub, команды, разбор проблем |
| `00-infrastructure/11-slimming-practicum.md` | Практикум кампании по репе: сжатие + архив → рабочий инструмент |
| `00-infrastructure/12-case-academic-portfolio.md` | Боевой кейс academic-portfolio: полный разбор кампании |
| `00-infrastructure/13-github-limits-and-rendering.md` | Точные лимиты GitHub, рендеринг форматов, подводные камни |
| `00-infrastructure/14-claude-usage-and-limits.md` | Лимиты Claude: токены, сессии, недельные, модели |
| `00-infrastructure/15-gotchas-claude-git.md` | Сквозные грабли Claude+Git, приватность, мультиаккаунт |
| `00-infrastructure/16-limits-empirical-estimate.md` | Эмпирическая оценка лимитов Claude (живая гипотеза) |
| `00-infrastructure/17-interview-to-file-methodology.md` | Контекстные файлы/методички через структурированное интервью |
| `00-infrastructure/18-documentation-philosophy.md` | **Философия документирования: «больше = лучше», слово = триггер, теория в доках, 4 аккаунта** |
| `00-infrastructure/19-reporting-system.md` | Диспетчер отчётов: триггер → тип → шаблон → папка → реестр |
| `00-infrastructure/20-knowledge-capture-protocol.md` | Автофиксация знаний по 7 триггерам (T1–T7) |
| `00-infrastructure/21-revision-protocol.md` | Ревизия всего в репе: живое vs замороженное, оси |
| `00-infrastructure/22-merge-protocol.md` | Слияние/форк линий между аккаунтами |
| `00-infrastructure/23-session-continuity.md` | Чекпоинт-дисциплина + несколько аккаунтов |
| `00-infrastructure/24-changelog-protocol.md` | Подробный `CHANGELOG`: полная история сделанного |
| `00-infrastructure/25-versioning-and-releases.md` | Версии/теги/релизы + автопуш одной командой |
| `00-infrastructure/26-claude-modes-cowork-vs-project.md` | Поверхности Claude: Chat / Project / Cowork / Code |
| `00-infrastructure/27-claude-memory-and-instructions.md` | Слои памяти и инструкций Claude (методичка) |
| `00-infrastructure/28-empirical-experiment-methodology.md` | Система-экспериментатор: реверс-инжиниринг неизвестных количеств |
| `00-infrastructure/29-claude-in-practice.md` | Claude на практике: рабочие паттерны, шишки, дисциплина сессий |
| `00-infrastructure/31-media-and-photo-storage.md` | Фото/видео вне git: 3-2-1, диск + копия, каталог в репе |
| `00-infrastructure/32-git-hooks-and-secret-scanning.md` | Хук против секретов и тяжёлых файлов; что делать при утечке токена |
| `00-infrastructure/33-token-budget-and-modes.md` | Бюджет токенов и режимы чтения A–E (замерено, не из документации) |
| `00-CLAUDE-STOP.md` | 🔴 **Вход для Claude:** обрыв канала tool-call + секреты. Читать первым |
| `.githooks/pre-commit` | Хук: не пускает в коммит секреты, тяжёлые бинарники, `.zip`/`.docx` |
| `01-claude-context/` | **Единый кит контекста** для всех аккаунтов Claude (вход — `00-navigator.md`) |
| `reports/README.md` | **Дом системы отчётности** — шаблоны, гайды, реестры, папки по типам (+ рубрика `situations/`, эксперименты `experiments/`) |
| `templates/REPO_README_TEMPLATE.md` | Шаблон корневого README репы |
| `templates/gitignore.template` | Базовый `.gitignore` |
| `templates/CHANGELOG_TEMPLATE.md` | Шаблон подробного `CHANGELOG` |
| `templates/publish.sh` | Скрипт автопуша версии (bump → commit → tag → push → GitHub Release) |
| `templates/deploy_from_zip.sh` | Архив от Claude → клон → чистая замена дерева → push (+ тег и Release) |
| `templates/deploy_all.sh` | **Все репы одной командой**: прогон `deploy_from_zip.sh` по папке архивов |
| `VERSION` | Текущая версия репы (источник правды для `publish.sh`) |

## Отличие от FINPILOT

FINPILOT — рабочий софт (код, тесты, CI). Здесь — **базы знаний**: кода нет, гейтов нет,
цель другая. Поэтому из FINPILOT взято только то, что относится к инфраструктуре знаний:
нейминг, журнал, работа с Claude, сжатие в `.md`, правила чистоты, дисциплина непрерывности.
Журнал живёт **в самой репе** (`00-infrastructure/WATCHLOG.md`) и коммитится — одна копия,
без архивов.

---

*Все репы приватные и сугубо личные. Единственное железное исключение при загрузке —
секреты (пароли, ключи, токены, данные карт): их не грузим никогда, даже в приватную репу.*
