#!/usr/bin/env bash
# =============================================================================
# publish.sh — универсальный автопуш версии: bump -> commit -> tag -> push ->
#              GitHub Release с описанием из CHANGELOG.md. Одна команда.
#
# Часть base-repo (templates/). Скопируй в корень репы. Правила и объяснение —
# 00-infrastructure/18-versioning-and-releases.md.
#
# Запуск (macOS/zsh — как принято в проекте):
#     zsh ~/Downloads/publish.sh --minor
#     zsh ~/Downloads/publish.sh --version 1.4.2
#     zsh ~/Downloads/publish.sh --patch --asset dist/repo_v1_4_2.zip
#     zsh ~/Downloads/publish.sh --patch --dry-run
#
# Идемпотентно: если тег vX.Y.Z уже есть — остановится, не наплодит дублей.
# Совместимо с bash и zsh. Сетевые шаги (push, gh) — с ретраями под РФ-таймауты.
# =============================================================================

set -u  # неопределённая переменная = ошибка. -e НЕ ставим: сами разбираем коды.

# ------------------------------------------------------------------ КОНФИГ ----
VERSION_FILE="${VERSION_FILE:-VERSION}"          # источник правды по версии
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}" # откуда берём описание релиза
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

Версия (одно из):
  --version X.Y.Z     явно задать версию
  --major | --minor | --patch   поднять от текущей в VERSION
  (без флага версии)  взять то, что уже в VERSION

Опции:
  --prerelease        пометить релиз как pre-release (или версия вида X.Y.Z-rcN)
  --asset PATH        приложить файл к GitHub Release (можно повторять)
  --no-release        только тег+пуш, без создания GitHub Release
  --dry-run           показать, что будет сделано, НИЧЕГО не меняя
  --help              эта справка

Переменные окружения: VERSION_FILE, CHANGELOG_FILE, REMOTE, MAIN_BRANCH,
                      TAG_PREFIX, RETRIES, RETRY_SLEEP, PY
USAGE
}

# ------------------------------------------------------------ ПАРСИНГ АРГ ----
BUMP=""; SET_VERSION=""; PRERELEASE=0; NO_RELEASE=0; DRY=0
ASSETS=""   # список ассетов через перевод строки (zsh/bash-safe, без массивов)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) SET_VERSION="${2:-}"; shift 2 ;;
    --major)   BUMP="major"; shift ;;
    --minor)   BUMP="minor"; shift ;;
    --patch)   BUMP="patch"; shift ;;
    --prerelease) PRERELEASE=1; shift ;;
    --asset)   ASSETS="${ASSETS}${2:-}"$'\n'; shift 2 ;;
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

# ------------------------------------------------ ИДЕМПОТЕНТНОСТЬ (тег есть?) -
# Проверяем по РЕЗУЛЬТАТУ вывода, а не по коду выхода (PIT-001/002).
LOCAL_TAG="$(git tag --list "$TAG")"
REMOTE_TAG="$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG" 2>/dev/null)"
if [ -n "$LOCAL_TAG" ] || [ -n "$REMOTE_TAG" ]; then
  die "тег $TAG уже существует (локально:'${LOCAL_TAG}' remote:$([ -n "$REMOTE_TAG" ] && echo да || echo нет)). Выпущенное не переписываем — подними версию."
fi

# ------------------------------------------- ОПИСАНИЕ РЕЛИЗА ИЗ CHANGELOG -----
# Python вытягивает секцию '## [VERSION]' в temp-файл (--notes-file), чтобы
# кириллица/тире не бились в shell-пайпе.
NOTES_FILE="$(mktemp -t publish_notes.XXXXXX)"
trap 'rm -f "$NOTES_FILE"' EXIT

extract_notes() {
  "$PY" - "$CHANGELOG_FILE" "$VERSION" > "$NOTES_FILE" <<'PYEOF'
import sys, re, io
path, version = sys.argv[1], sys.argv[2]
try:
    text = io.open(path, encoding="utf-8").read()
except FileNotFoundError:
    print(f"Release {version}")
    sys.exit(0)
lines = text.splitlines()
# ищем заголовок секции версии: ## [X.Y.Z] ...  (или ## X.Y.Z ...)
pat = re.compile(r'^\s{0,3}##\s+\[?' + re.escape(version) + r'\]?')
start = None
for i, ln in enumerate(lines):
    if pat.match(ln):
        start = i + 1
        break
if start is None:
    print(f"Release {version}")
    sys.exit(0)
# до следующего '## ' — конец секции
end = len(lines)
for j in range(start, len(lines)):
    if re.match(r'^\s{0,3}##\s+', lines[j]):
        end = j
        break
body = "\n".join(lines[start:end]).strip()
print(body if body else f"Release {version}")
PYEOF
}
extract_notes
NOTES_PREVIEW="$(head -8 "$NOTES_FILE")"
info "Описание релиза (из $CHANGELOG_FILE, первые строки):"
printf '%s\n' "$NOTES_PREVIEW" | sed 's/^/    /'

# ------------------------------------------------------------- DRY-RUN --------
if [ "$DRY" -eq 1 ]; then
  c_ylw "--- DRY-RUN: ничего не меняю. Что было бы сделано: ---"
  echo "  1) echo $VERSION > $VERSION_FILE"
  echo "  2) git add -A && git commit -m 'release: $TAG'"
  echo "  3) git tag -a $TAG -F <notes>"
  echo "  4) git push $REMOTE $MAIN_BRANCH  (ретраи: $RETRIES)"
  echo "  5) git push $REMOTE $TAG          (ретраи: $RETRIES)"
  if [ "$NO_RELEASE" -eq 0 ]; then
    echo "  6) gh release create $TAG --notes-file <notes>$([ "$PRERELEASE" -eq 1 ] && echo ' --prerelease')"
    printf '%s' "$ASSETS" | while IFS= read -r a; do [ -n "$a" ] && echo "       + asset: $a"; done
  fi
  ok "DRY-RUN завершён."
  exit 0
fi

# --------------------------------------------------- ЗАПИСЬ ВЕРСИИ + КОММИТ ---
printf '%s\n' "$VERSION" > "$VERSION_FILE"
git add -A
if git diff --cached --quiet; then
  info "нет изменений для коммита — версия и так актуальна, продолжаю к тегу"
else
  git commit -m "release: $TAG" || die "commit не удался"
  ok "коммит release: $TAG"
fi

# --------------------------------------------------------- АННОТИРОВАННЫЙ ТЕГ -
git tag -a "$TAG" -F "$NOTES_FILE" || die "не смог создать тег $TAG"
ok "тег $TAG создан"

# ------------------------------------------------------------- ПУШ (ретраи) --
push_branch() { git push "$REMOTE" "$MAIN_BRANCH"; }
push_tag()    { git push "$REMOTE" "$TAG"; }

retry "push ветки" push_branch || die "не удалось запушить ветку после $RETRIES попыток"
ok "ветка $MAIN_BRANCH запушена"
retry "push тега" push_tag || die "не удалось запушить тег после $RETRIES попыток"
ok "тег $TAG запушен"

# ------------------------------------------------------ GITHUB RELEASE --------
if [ "$NO_RELEASE" -eq 1 ]; then
  ok "--no-release: релиз не создаём. Тег на месте."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  c_ylw "gh (GitHub CLI) не установлен — тег запушен, релиз создай вручную:"
  echo "    gh release create $TAG --notes-file <файл>"
  echo "    или на GitHub: Releases -> Draft new release -> выбрать тег $TAG"
  c_ylw "Описание уже готово в CHANGELOG (секция $VERSION)."
  exit 0
fi
if ! gh auth status >/dev/null 2>&1; then
  c_ylw "gh есть, но не залогинен (gh auth login). Тег запушен; релиз создашь после логина:"
  echo "    gh release create $TAG --notes-file <файл>"
  exit 0
fi

# существующий релиз? проверяем через temp-файл (прямой пайп в обработку конфликтует по stdin)
GH_VIEW_OUT="$(mktemp -t gh_view.XXXXXX)"
gh release view "$TAG" >"$GH_VIEW_OUT" 2>/dev/null
if [ -s "$GH_VIEW_OUT" ]; then
  c_ylw "Release $TAG уже существует на GitHub — пропускаю создание."
  rm -f "$GH_VIEW_OUT"; exit 0
fi
rm -f "$GH_VIEW_OUT"

# сборка команды создания релиза
gh_create() {
  set -- release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE"
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

if retry "gh release create" gh_create; then
  ok "GitHub Release $TAG создан (описание из $CHANGELOG_FILE)"
  gh release view "$TAG" --web >/dev/null 2>&1 || true
else
  c_red "релиз не создался после $RETRIES попыток, но ТЕГ уже запушен."
  echo "  Доделай вручную: gh release create $TAG --notes-file <файл>"
  exit 1
fi

ok "Готово: $TAG выпущен (версия + коммит + тег + пуш + Release)."
