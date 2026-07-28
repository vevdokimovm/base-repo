#!/usr/bin/env bash
# =============================================================================
# publish.sh — универсальный автопуш версии: bump -> commit -> tag -> push ->
#              GitHub Release с описанием из CHANGELOG.md. Одна команда.
#
# Часть base-repo (templates/). Скопируй в корень репы. Правила и объяснение —
# 00-infrastructure/25-versioning-and-releases.md.
#
# Запуск (macOS/zsh — как принято в проекте):
#     zsh ~/Downloads/publish.sh --minor
#     zsh ~/Downloads/publish.sh --version 1.4.2
#     zsh ~/Downloads/publish.sh --patch --asset dist/repo_v1_4_2.zip
#     zsh ~/Downloads/publish.sh --patch --dry-run
#
# ИДЕМПОТЕНТНОСТЬ + ДОДЕЛКА (перезапуск безопасен):
#   Если тег vX.Y.Z уже существует, скрипт НЕ падает и НЕ переписывает
#   выпущенное, а переходит в режим доделки: пропускает bump/commit/tag,
#   и доводит до конца только недостающие шаги —
#     - тег не запушен            -> пушит тег;
#     - релиза нет                -> создаёт релиз (заголовок + описание из CHANGELOG);
#     - релиз есть, но описание-
#       заглушка ("Release X.Y.Z")-> заполняет описание из CHANGELOG (gh release edit);
#     - заголовок голый "vX.Y.Z"  -> ставит человеческий заголовок;
#     - ассет не приложен         -> докидывает недостающие ассеты (существующие не трогает);
#     - всё уже на месте          -> сообщает и выходит с кодом 0.
#   Осмысленное (не-заглушечное) описание релиза НИКОГДА не перезаписывается:
#   тег и релиз — замороженные (21-revision-protocol.md). Ошибся в тексте —
#   правь CHANGELOG и выпускай следующую версию, либо редактируй руками осознанно.
#
# CHANGELOG ищется по кандидатам (первый существующий):
#   $CHANGELOG_FILE -> CHANGELOG.md -> 00-infrastructure/CHANGELOG.md -> docs/CHANGELOG.md
#   (сначала относительно текущей папки, затем относительно корня git-репы).
#   Если секция версии не найдена — скрипт ГРОМКО предупреждает (раньше молча
#   подставлял заглушку — так v1.5.0 base-repo и уехала пустой).
#
# Заголовок релиза строится из заголовка секции CHANGELOG:
#   "## [1.5.0] — 2026-07-09 — Суть релиза (MINOR)"
#     -> title: "<repo> v1.5.0 — Суть релиза"   (дата и маркер (MAJOR|MINOR|PATCH) отрезаются)
#
# Совместимо с bash и zsh. Сетевые шаги (push, gh) — с ретраями под РФ-таймауты.
# =============================================================================

set -u  # неопределённая переменная = ошибка. -e НЕ ставим: сами разбираем коды.

# ------------------------------------------------------------------ КОНФИГ ----
VERSION_FILE="${VERSION_FILE:-VERSION}"          # источник правды по версии
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}" # первый кандидат; дальше — авто-поиск
REMOTE="${REMOTE:-origin}"                        # git remote
MAIN_BRANCH="${MAIN_BRANCH:-}"                    # пусто = текущая ветка
TAG_PREFIX="${TAG_PREFIX:-v}"                     # тег = v1.4.2
RETRIES="${RETRIES:-5}"                           # попыток на сетевой шаг
RETRY_SLEEP="${RETRY_SLEEP:-4}"                   # старт бэк-оффа, сек
PY="${PY:-python3}"                               # интерпретатор для парсинга

# --------------------------------------------------------------- УТИЛИТЫ -----
c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
die()    { c_red "ОШИБКА: $*"; exit 1; }
info()   { c_ylw "→ $*"; }
ok()     { c_grn "✓ $*"; }

# Ретрай сетевого шага: retry <описание> <команда...>
retry() {
  desc="$1"; shift
  attempt=1; sleep_for="$RETRY_SLEEP"
  while [ "$attempt" -le "$RETRIES" ]; do
    if "$@"; then
      return 0
    fi
    c_ylw "  попытка $attempt/$RETRIES ($desc) не удалась — жду ${sleep_for}s (вероятно TLS-таймаут к GitHub)"
    sleep "$sleep_for"
    attempt=$((attempt + 1))
    sleep_for=$((sleep_for * 2))   # экспоненциальный бэк-офф
  done
  return 1
}

usage() {
  cat <<'USAGE'
publish.sh — автопуш версии (bump -> commit -> tag -> push -> GitHub Release)

Перезапуск безопасен: если тег уже есть, скрипт ничего не переписывает,
а доделывает недостающее (пуш тега, релиз, описание-заглушку, ассеты).

Версия (одно из):
  --version X.Y.Z     явно задать версию
  --major | --minor | --patch   поднять от текущей в VERSION
  (без флага версии)  взять то, что уже в VERSION

Опции:
  --prerelease        пометить релиз как pre-release (или версия вида X.Y.Z-rcN)
  --asset PATH        приложить файл к GitHub Release (можно повторять)
  --auto-asset        собрать и приложить zip-снапшот тега (git archive) — архив байт-в-байт равен дереву тега
  --no-release        только тег+пуш, без создания GitHub Release
  --dry-run           показать, что будет сделано, НИЧЕГО не меняя
  --help              эта справка

Переменные окружения: VERSION_FILE, CHANGELOG_FILE, REMOTE, MAIN_BRANCH,
                      TAG_PREFIX, RETRIES, RETRY_SLEEP, PY
USAGE
}

# ------------------------------------------------------------ ПАРСИНГ АРГ ----
BUMP=""; SET_VERSION=""; PRERELEASE=0; NO_RELEASE=0; DRY=0; AUTO_ASSET=0
ASSETS=""   # список ассетов через перевод строки (zsh/bash-safe, без массивов)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) SET_VERSION="${2:-}"; shift 2 ;;
    --major)   BUMP="major"; shift ;;
    --minor)   BUMP="minor"; shift ;;
    --patch)   BUMP="patch"; shift ;;
    --prerelease) PRERELEASE=1; shift ;;
    --asset)   ASSETS="${ASSETS}${2:-}"$'\n'; shift 2 ;;
    --auto-asset) AUTO_ASSET=1; shift ;;
    --no-release) NO_RELEASE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "неизвестный аргумент: $1 (см. --help)" ;;
  esac
done

# --------------------------------------------------- ПРЕДПОЛЁТНЫЕ ПРОВЕРКИ ----
command -v git >/dev/null 2>&1 || die "git не найден"
command -v "$PY" >/dev/null 2>&1 || die "$PY не найден (нужен для парсинга CHANGELOG)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "не git-репозиторий"

[ -n "$MAIN_BRANCH" ] || MAIN_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --------------------------------------------------------- ОПРЕДЕЛЕНИЕ ВЕРСИИ -
read_current() {
  if [ -f "$VERSION_FILE" ]; then
    tr -d ' \t\r\n' < "$VERSION_FILE"
  else
    echo ""
  fi
}

bump_version() {
  # $1 = текущая X.Y.Z, $2 = major|minor|patch
  cur="$1"; kind="$2"
  [ -n "$cur" ] || cur="0.0.0"
  # разбор через python — надёжнее shell по краям
  "$PY" - "$cur" "$kind" <<'PYEOF'
import sys, re
cur, kind = sys.argv[1], sys.argv[2]
m = re.match(r'^(\d+)\.(\d+)\.(\d+)', cur)
if not m:
    sys.stderr.write("VERSION не в формате X.Y.Z: %r\n" % cur); sys.exit(2)
major, minor, patch = (int(x) for x in m.groups())
if kind == "major": major, minor, patch = major + 1, 0, 0
elif kind == "minor": minor, patch = minor + 1, 0
elif kind == "patch": patch += 1
print(f"{major}.{minor}.{patch}")
PYEOF
}

CURRENT="$(read_current)"
if [ -n "$SET_VERSION" ]; then
  VERSION="$SET_VERSION"
elif [ -n "$BUMP" ]; then
  VERSION="$(bump_version "$CURRENT" "$BUMP")" || die "не смог поднять версию"
else
  VERSION="$CURRENT"
fi
[ -n "$VERSION" ] || die "версия не задана: используй --version X.Y.Z или --patch/--minor/--major (VERSION пуст)"

# валидация формата (X.Y.Z с опц. -суффиксом)
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' \
  || die "версия '$VERSION' не по SemVer (ожидается X.Y.Z или X.Y.Z-rcN)"

TAG="${TAG_PREFIX}${VERSION}"
# pre-release, если есть дефис-суффикс
case "$VERSION" in *-*) PRERELEASE=1 ;; esac

info "Версия: ${CURRENT:-<нет>} -> ${VERSION}   Тег: ${TAG}   Ветка: ${MAIN_BRANCH}"

# --------------------------------------- ТЕГ УЖЕ ЕСТЬ? -> РЕЖИМ ДОДЕЛКИ -------
# Проверяем по РЕЗУЛЬТАТУ вывода, а не по коду выхода (PIT-001/002).
# Раньше существующий тег был фаталом; теперь это вход в режим доделки:
# выпущенное не трогаем, недостающее доводим до конца.
LOCAL_TAG="$(git tag --list "$TAG")"
REMOTE_TAG_PEELED="$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG^{}" 2>/dev/null | awk '{print $1}')"
REMOTE_TAG_PLAIN="$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG" 2>/dev/null | awk 'NR==1{print $1}')"
REMOTE_TAG_SHA="${REMOTE_TAG_PEELED:-$REMOTE_TAG_PLAIN}"

RESUME=0
if [ -n "$LOCAL_TAG" ] || [ -n "$REMOTE_TAG_SHA" ]; then
  RESUME=1
  # если тег есть и там и там — коммиты обязаны совпадать, иначе руками
  if [ -n "$LOCAL_TAG" ] && [ -n "$REMOTE_TAG_SHA" ]; then
    LOCAL_TAG_SHA="$(git rev-parse "$TAG^{commit}" 2>/dev/null || echo '')"
    if [ -n "$LOCAL_TAG_SHA" ] && [ "$LOCAL_TAG_SHA" != "$REMOTE_TAG_SHA" ]; then
      die "тег $TAG локально ($LOCAL_TAG_SHA) и на remote ($REMOTE_TAG_SHA) указывает на РАЗНЫЕ коммиты — разбери руками, силой ничего не двигаю"
    fi
  fi
  info "тег $TAG уже существует (локально:$([ -n "$LOCAL_TAG" ] && echo да || echo нет) remote:$([ -n "$REMOTE_TAG_SHA" ] && echo да || echo нет)) — режим ДОДЕЛКИ: bump/commit/tag пропускаю, довожу недостающее"
fi

# ------------------------------------------- ПОИСК CHANGELOG ПО КАНДИДАТАМ ----
# Урок v1.5.0 base-repo: CHANGELOG лежал в 00-infrastructure/, скрипт искал в
# корне, молча подставил заглушку "Release 1.5.0" — релиз уехал пустым.
find_changelog() {
  for cand in \
    "$CHANGELOG_FILE" \
    "CHANGELOG.md" \
    "00-infrastructure/CHANGELOG.md" \
    "docs/CHANGELOG.md" \
    "$GIT_ROOT/CHANGELOG.md" \
    "$GIT_ROOT/00-infrastructure/CHANGELOG.md" \
    "$GIT_ROOT/docs/CHANGELOG.md"
  do
    if [ -n "$cand" ] && [ -f "$cand" ]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

CHANGELOG_FOUND="$(find_changelog || true)"

# ------------------------------------------- ОПИСАНИЕ РЕЛИЗА ИЗ CHANGELOG -----
# Python вытягивает секцию '## [VERSION]' в temp-файл (--notes-file), чтобы
# кириллица/тире не бились в shell-пайпе. Тем же проходом берём СУТЬ версии из
# заголовка секции — для человеческого заголовка релиза.
NOTES_FILE="$(mktemp -t publish_notes.XXXXXX)"
TITLE_FILE="$(mktemp -t publish_title.XXXXXX)"
TMP_FILES="$NOTES_FILE $TITLE_FILE"
cleanup_tmp() { rm -f $TMP_FILES; }
trap cleanup_tmp EXIT

# печатает FOUND (секция найдена) или STUB (нет файла/секции — в notes заглушка)
extract_notes() {
  "$PY" - "${CHANGELOG_FOUND:-__NO_CHANGELOG__}" "$VERSION" "$NOTES_FILE" "$TITLE_FILE" <<'PYEOF'
import sys, re, io
path, version, notes_path, title_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def write(p, s):
    with io.open(p, "w", encoding="utf-8") as f:
        f.write(s)

try:
    text = io.open(path, encoding="utf-8").read()
except (FileNotFoundError, IsADirectoryError, OSError):
    write(notes_path, f"Release {version}")
    write(title_path, "")
    print("STUB")
    sys.exit(0)

lines = text.splitlines()
# ищем заголовок секции версии: ## [X.Y.Z] ...  (или ## X.Y.Z ...)
pat = re.compile(r'^\s{0,3}##\s+\[?' + re.escape(version) + r'\]?')
start = None
heading = ""
for i, ln in enumerate(lines):
    if pat.match(ln):
        start = i + 1
        heading = ln
        break
if start is None:
    write(notes_path, f"Release {version}")
    write(title_path, "")
    print("STUB")
    sys.exit(0)

# до следующего '## ' — конец секции
end = len(lines)
for j in range(start, len(lines)):
    if re.match(r'^\s{0,3}##\s+', lines[j]):
        end = j
        break
body = "\n".join(lines[start:end]).strip()
write(notes_path, body if body else f"Release {version}")

# суть из заголовка: "## [1.5.0] — 2026-07-09 — Суть (MINOR)" -> "Суть"
essence = re.sub(r'^\s{0,3}##\s+\[?' + re.escape(version) + r'\]?\s*', '', heading)
essence = re.sub(r'^[\s\u2014\u2013:\-]+', '', essence)                  # разделители после версии
essence = re.sub(r'^\d{4}-\d{2}-\d{2}\s*', '', essence)                   # дата
essence = re.sub(r'^[\s\u2014\u2013:\-]+', '', essence)                  # разделители после даты
essence = re.sub(r'\s*\((MAJOR|MINOR|PATCH)\)\s*$', '', essence, flags=re.I)  # маркер бампа
write(title_path, essence.strip())
print("FOUND" if body else "STUB")
PYEOF
}
NOTES_STATUS="$(extract_notes)" || die "парсер CHANGELOG упал"

if [ "$NOTES_STATUS" = "FOUND" ]; then
  info "Описание релиза (из ${CHANGELOG_FOUND}, первые строки):"
  head -8 "$NOTES_FILE" | awk '{print "    " $0}'
else
  if [ -n "$CHANGELOG_FOUND" ]; then
    c_ylw "⚠ секция [$VERSION] НЕ найдена в ${CHANGELOG_FOUND} — описанием будет заглушка 'Release $VERSION'."
  else
    c_ylw "⚠ CHANGELOG не найден ни по одному кандидату (CHANGELOG.md, 00-infrastructure/, docs/) — описанием будет заглушка."
  fi
  c_ylw "  Правило: сначала CHANGELOG, потом publish (25-versioning-and-releases.md §5)."
fi

# --------------------------------------------- ЗАГОЛОВОК РЕЛИЗА ---------------
# "<repo> vX.Y.Z — Суть" ; без сути — "<repo> vX.Y.Z" ; крайний случай — голый тег.
REPO_NAME="$(basename "$(git remote get-url "$REMOTE" 2>/dev/null || echo '')" .git)"
[ -n "$REPO_NAME" ] && [ "$REPO_NAME" != "." ] || REPO_NAME="$(basename "$GIT_ROOT")"
ESSENCE="$(cat "$TITLE_FILE" 2>/dev/null || echo '')"
if [ -n "$ESSENCE" ]; then
  RELEASE_TITLE="${REPO_NAME} ${TAG} — ${ESSENCE}"
elif [ -n "$REPO_NAME" ]; then
  RELEASE_TITLE="${REPO_NAME} ${TAG}"
else
  RELEASE_TITLE="$TAG"
fi
info "Заголовок релиза: $RELEASE_TITLE"

# ------------------------------------------------------------- DRY-RUN --------
if [ "$DRY" -eq 1 ]; then
  c_ylw "--- DRY-RUN: ничего не меняю. Что было бы сделано: ---"
  if [ "$RESUME" -eq 1 ]; then
    echo "  (режим ДОДЕЛКИ: тег $TAG уже есть — bump/commit/tag пропускаются)"
    [ -n "$LOCAL_TAG" ] && [ -z "$REMOTE_TAG_SHA" ] && echo "  - git push $REMOTE $TAG  (тег ещё не на remote)"
    [ -z "$LOCAL_TAG" ] && [ -n "$REMOTE_TAG_SHA" ] && echo "  - git fetch $REMOTE tag $TAG  (тега нет локально — нужен для git archive)"
    if [ "$NO_RELEASE" -eq 0 ]; then
      echo "  - релиза нет -> gh release create $TAG --title '$RELEASE_TITLE' --notes-file <notes>"
      echo "  - релиз есть, описание-заглушка -> gh release edit $TAG --title ... --notes-file <notes>"
      echo "  - недостающие ассеты -> gh release upload $TAG <files>  (существующие не трогаются)"
      [ "$AUTO_ASSET" -eq 1 ] && echo "       + auto-asset: git archive -> ${REPO_NAME}-$TAG.zip (если такого имени нет в релизе)"
    fi
  else
    echo "  1) echo $VERSION > $VERSION_FILE"
    echo "  2) git add -A && git commit -m 'release: $TAG'"
    echo "  3) git tag -a $TAG -F <notes>"
    echo "  4) git push $REMOTE $MAIN_BRANCH  (ретраи: $RETRIES)"
    echo "  5) git push $REMOTE $TAG          (ретраи: $RETRIES)"
    if [ "$NO_RELEASE" -eq 0 ]; then
      echo "  6) gh release create $TAG --title '$RELEASE_TITLE' --notes-file <notes>$([ "$PRERELEASE" -eq 1 ] && echo ' --prerelease')"
      [ "$AUTO_ASSET" -eq 1 ] && echo "       + auto-asset: git archive -> ${REPO_NAME}-$TAG.zip"
      printf '%s' "$ASSETS" | while IFS= read -r a; do [ -n "$a" ] && echo "       + asset: $a"; done
    fi
  fi
  ok "DRY-RUN завершён."
  exit 0
fi

# --------------------------------------------------- ЗАПИСЬ ВЕРСИИ + КОММИТ ---
# В режиме доделки дерево НЕ трогаем: содержимое версии заморожено тегом.
if [ "$RESUME" -eq 0 ]; then
  printf '%s\n' "$VERSION" > "$VERSION_FILE"
  git add -A
  if git diff --cached --quiet; then
    info "нет изменений для коммита — версия и так актуальна, продолжаю к тегу"
  else
    git commit -m "release: $TAG" || die "commit не удался"
    ok "коммит release: $TAG"
  fi

  # ------------------------------------------------------- АННОТИРОВАННЫЙ ТЕГ -
  git tag -a "$TAG" -F "$NOTES_FILE" || die "не смог создать тег $TAG"
  ok "тег $TAG создан"
  LOCAL_TAG="$TAG"
else
  info "режим доделки: VERSION/commit/tag не трогаю"
  # тег есть только на remote — подтягиваем локально (нужен для git archive)
  if [ -z "$LOCAL_TAG" ] && [ -n "$REMOTE_TAG_SHA" ]; then
    fetch_tag() { git fetch "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"; }
    retry "fetch тега" fetch_tag || c_ylw "не смог подтянуть тег локально — auto-asset может не собраться"
    LOCAL_TAG="$(git tag --list "$TAG")"
  fi
fi

# ------------------------------------------------------------- ПУШ (ретраи) --
push_branch() { git push "$REMOTE" "$MAIN_BRANCH"; }
push_tag()    { git push "$REMOTE" "$TAG"; }

if retry "push ветки" push_branch; then
  ok "ветка $MAIN_BRANCH запушена"
else
  if [ "$RESUME" -eq 1 ]; then
    c_ylw "⚠ ветка не запушилась (возможно, разошлась) — в режиме доделки это не блокер, продолжаю к релизу"
  else
    die "не удалось запушить ветку после $RETRIES попыток"
  fi
fi

if [ -n "$REMOTE_TAG_SHA" ]; then
  info "тег $TAG уже на remote — пуш тега пропускаю"
else
  retry "push тега" push_tag || die "не удалось запушить тег после $RETRIES попыток"
  ok "тег $TAG запушен"
fi

# --------------------------------------------- АВТО-АССЕТ ИЗ ДЕРЕВА ТЕГА ------
# (--auto-asset) zip-снапшот через git archive: байт-в-байт равен дереву тега,
# не может разойтись с релизом (урок FINPILOT: единый формат артефакта).
if [ "$AUTO_ASSET" -eq 1 ]; then
  AUTO_ZIP="$(mktemp -d)/${REPO_NAME}-${TAG}.zip"
  if git archive --format=zip -o "$AUTO_ZIP" "$TAG" 2>/dev/null; then
    ASSETS="${ASSETS}${AUTO_ZIP}"$'\n'
    ok "auto-asset собран: ${REPO_NAME}-${TAG}.zip"
  else
    c_ylw "не смог собрать auto-asset (git archive) — релиз пойдёт без архива"
  fi
fi

# ------------------------------------------------------ GITHUB RELEASE --------
if [ "$NO_RELEASE" -eq 1 ]; then
  ok "--no-release: релиз не создаём. Тег на месте."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  c_ylw "gh (GitHub CLI) не установлен — тег запушен, релиз создай вручную:"
  echo "    gh release create $TAG --title \"$RELEASE_TITLE\" --notes-file <файл>"
  echo "    или на GitHub: Releases -> Draft new release -> выбрать тег $TAG"
  c_ylw "Описание уже готово в CHANGELOG (секция $VERSION). Перезапуск этого скрипта после установки gh доделает релиз сам."
  exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
  c_ylw "gh есть, но не залогинен (gh auth login). Тег запушен; перезапуск скрипта после логина доделает релиз сам."
  exit 0
fi

# --- существует ли релиз? (вывод в temp-файл: прямой пайп конфликтует по stdin)
# 'not found' в stderr = релиза нет; иной сбой = сеть, ретраим.
GH_BODY_FILE="$(mktemp -t gh_body.XXXXXX)"
GH_ERR_FILE="$(mktemp -t gh_err.XXXXXX)"
TMP_FILES="$TMP_FILES $GH_BODY_FILE $GH_ERR_FILE"

RELEASE_STATE=""   # absent | present
view_release() { gh release view "$TAG" --json body -q .body >"$GH_BODY_FILE" 2>"$GH_ERR_FILE"; }
probe_release() {
  if view_release; then RELEASE_STATE="present"; return 0; fi
  if grep -qi "not found" "$GH_ERR_FILE"; then RELEASE_STATE="absent"; return 0; fi
  return 1  # сетевой/иной сбой — на ретрай
}
retry "gh release view" probe_release || die "не смог проверить существование релиза $TAG (см. вывод gh выше)"

# --- сборка команды создания релиза ---
gh_create() {
  set -- release create "$TAG" --title "$RELEASE_TITLE" --notes-file "$NOTES_FILE"
  [ "$PRERELEASE" -eq 1 ] && set -- "$@" --prerelease
  # ассеты
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    [ -f "$a" ] || { c_ylw "  ассет не найден, пропускаю: $a"; continue; }
    set -- "$@" "$a"
  done <<EOF
$(printf '%s' "$ASSETS")
EOF
  gh "$@"
}

if [ "$RELEASE_STATE" = "absent" ]; then
  # ------------------------------------------------ СОЗДАНИЕ РЕЛИЗА ----------
  if retry "gh release create" gh_create; then
    ok "GitHub Release $TAG создан: '$RELEASE_TITLE' (описание из ${CHANGELOG_FOUND:-CHANGELOG})"
    gh release view "$TAG" --web >/dev/null 2>&1 || true
  else
    c_red "релиз не создался после $RETRIES попыток, но ТЕГ уже запушен."
    echo "  Просто перезапусти этот скрипт позже — он доделает релиз (режим доделки)."
    exit 1
  fi
else
  # ------------------------------------------- ДОДЕЛКА СУЩЕСТВУЮЩЕГО РЕЛИЗА --
  info "Release $TAG уже существует — проверяю, что доделать"

  # тело-заглушка? ("", "Release X.Y.Z", "vX.Y.Z")
  BODY_TRIM="$("$PY" -c 'import sys,io; print(io.open(sys.argv[1],encoding="utf-8").read().strip())' "$GH_BODY_FILE" 2>/dev/null || echo '')"
  BODY_IS_STUB=0
  if [ -z "$BODY_TRIM" ] || [ "$BODY_TRIM" = "Release $VERSION" ] || [ "$BODY_TRIM" = "$TAG" ]; then
    BODY_IS_STUB=1
  fi

  # заголовок голый? (равен тегу/версии или пуст)
  GH_NAME_FILE="$(mktemp -t gh_name.XXXXXX)"; TMP_FILES="$TMP_FILES $GH_NAME_FILE"
  view_name() { gh release view "$TAG" --json name -q .name >"$GH_NAME_FILE" 2>/dev/null; }
  retry "gh release view (name)" view_name || : > "$GH_NAME_FILE"
  NAME_TRIM="$(tr -d '\r\n' < "$GH_NAME_FILE")"
  NAME_IS_BARE=0
  if [ -z "$NAME_TRIM" ] || [ "$NAME_TRIM" = "$TAG" ] || [ "$NAME_TRIM" = "$VERSION" ] || [ "$NAME_TRIM" = "Release $VERSION" ]; then
    NAME_IS_BARE=1
  fi

  EDIT_NOTES=0; EDIT_TITLE=0
  if [ "$BODY_IS_STUB" -eq 1 ]; then
    if [ "$NOTES_STATUS" = "FOUND" ]; then
      EDIT_NOTES=1
    else
      c_ylw "⚠ описание релиза — заглушка, но и в CHANGELOG секции [$VERSION] нет: чинить нечем. Допиши CHANGELOG и перезапусти."
    fi
  else
    info "описание релиза уже осмысленное — НЕ трогаю (замороженный релиз, 21-revision-protocol.md)"
    if [ "$NOTES_STATUS" = "FOUND" ]; then
      NOTES_TRIM="$("$PY" -c 'import sys,io; print(io.open(sys.argv[1],encoding="utf-8").read().strip())' "$NOTES_FILE")"
      [ "$NOTES_TRIM" != "$BODY_TRIM" ] && c_ylw "  (описание на GitHub отличается от CHANGELOG — если это не осознанная правка, редактируй руками: gh release edit $TAG --notes-file <файл>)"
    fi
  fi
  [ "$NAME_IS_BARE" -eq 1 ] && [ "$RELEASE_TITLE" != "$TAG" ] && EDIT_TITLE=1

  if [ "$EDIT_NOTES" -eq 1 ] || [ "$EDIT_TITLE" -eq 1 ]; then
    gh_edit() {
      set -- release edit "$TAG"
      [ "$EDIT_TITLE" -eq 1 ] && set -- "$@" --title "$RELEASE_TITLE"
      [ "$EDIT_NOTES" -eq 1 ] && set -- "$@" --notes-file "$NOTES_FILE"
      gh "$@"
    }
    if retry "gh release edit" gh_edit; then
      [ "$EDIT_NOTES" -eq 1 ] && ok "описание релиза заполнено из ${CHANGELOG_FOUND:-CHANGELOG} (была заглушка)"
      [ "$EDIT_TITLE" -eq 1 ] && ok "заголовок релиза обновлён: '$RELEASE_TITLE'"
    else
      c_red "gh release edit не прошёл после $RETRIES попыток — перезапусти скрипт позже, он доделает."
      exit 1
    fi
  fi

  # --- недостающие ассеты (существующие имена не трогаем, --clobber не используем)
  GH_ASSETS_FILE="$(mktemp -t gh_assets.XXXXXX)"; TMP_FILES="$TMP_FILES $GH_ASSETS_FILE"
  view_assets() { gh release view "$TAG" --json assets -q '.assets[].name' >"$GH_ASSETS_FILE" 2>/dev/null; }
  retry "gh release view (assets)" view_assets || : > "$GH_ASSETS_FILE"

  MISSING_UPLOADED=0
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    [ -f "$a" ] || { c_ylw "  ассет не найден на диске, пропускаю: $a"; continue; }
    A_NAME="$(basename "$a")"
    if grep -qxF "$A_NAME" "$GH_ASSETS_FILE"; then
      info "ассет уже в релизе, пропускаю: $A_NAME"
    else
      upload_one() { gh release upload "$TAG" "$a"; }
      if retry "gh release upload $A_NAME" upload_one; then
        ok "ассет докинут: $A_NAME"
        MISSING_UPLOADED=$((MISSING_UPLOADED + 1))
      else
        c_red "не смог загрузить ассет $A_NAME после $RETRIES попыток — перезапусти скрипт, он докинет."
        exit 1
      fi
    fi
  done <<EOF
$(printf '%s' "$ASSETS")
EOF

  if [ "$EDIT_NOTES" -eq 0 ] && [ "$EDIT_TITLE" -eq 0 ] && [ "$MISSING_UPLOADED" -eq 0 ]; then
    ok "всё уже на месте: тег, релиз, описание, ассеты. Ничего не делал."
  fi
fi

ok "Готово: $TAG выпущен (версия + коммит + тег + пуш + Release). Перезапуск безопасен — доделает недостающее."
