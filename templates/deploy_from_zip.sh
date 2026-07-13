#!/usr/bin/env bash
# =============================================================================
# deploy_from_zip.sh — УНИВЕРСАЛЬНЫЙ деплой любой репы системы из архива:
#     распаковка -> маркеры корня -> клон -> чистая замена дерева -> push ->
#     тег + GitHub Release (через publish.sh из самого дерева).
#
# Часть base-repo (templates/). Пара к publish.sh:
#   publish.sh       — работает ВНУТРИ клона (версия -> тег -> релиз);
#   deploy_from_zip.sh — работает СНАРУЖИ (архив от Claude -> запушенная репа),
#                        publish.sh вызывает сам. Аналог FINPILOT-публикатора.
#
# ЗАПУСК (macOS/zsh):
#   zsh ~/Downloads/deploy_from_zip.sh ~/Downloads/<repo>-vX_Y_Z.zip
#   SHA=<sha256>              — сверить архив перед работой (рекомендую: Claude даёт sha в чате)
#   ALSO_PUBLISH="1.5.0 ..."  — после релиза доделать старые версии (заполнить
#                               заглушечные описания/ассеты; идемпотентно, publish.sh v2)
#   OWNER=vevdokimovm · REPO_URL=... · BRANCH=main · MSG=... — переопределяемы
#
# ОТКУДА БЕРУТСЯ ИМЯ И ВЕРСИЯ:
#   обёртка архива `<repo>-vX_Y_Z/` (конвенция упаковки, 15-gotchas §2) и/или файл
#   VERSION в корне дерева. Есть оба -> обязаны совпадать, иначе стоп. Нет ни
#   одного источника версии -> только push, без тега/релиза (с предупреждением).
#
# ЗАЩИТЫ (те же, что в push_base_repo.sh + publish.sh):
#   sha256-сверка по запросу · разворот обёртки (PIT-007) · ДЕСТРУКТИВ ТОЛЬКО
#   ПОСЛЕ МАРКЕРОВ корня · чистка-кроме-.git (PIT-004) · add -A -f (PIT-006) ·
#   автопроверка: файлов в коммите == файлов в дереве (PIT-006/007/008) ·
#   ретраи под РФ-TLS · абсолютные пути · на падении рабочая папка сохраняется.
# =============================================================================

set -u

OWNER="${OWNER:-vevdokimovm}"
BRANCH="${BRANCH:-main}"
RETRIES="${RETRIES:-5}"; RETRY_SLEEP="${RETRY_SLEEP:-4}"
MIN_FILES="${MIN_FILES:-5}"   # порог «дерево похоже на репу»

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }
die(){ red "ОШИБКА: $*"; [ -n "${WORK:-}" ] && red "Рабочая папка сохранена для разбора: $WORK"; exit 1; }
retry(){ d="$1"; shift; a=1; s="$RETRY_SLEEP"
  while [ "$a" -le "$RETRIES" ]; do "$@" && return 0
    ylw "  попытка $a/$RETRIES ($d) не удалась — жду ${s}s (вероятно TLS-таймаут к GitHub)"
    sleep "$s"; a=$((a+1)); s=$((s*2)); done; return 1; }

usage(){ cat <<'USAGE'
Использование: zsh deploy_from_zip.sh <путь-к-архиву.zip>
Пример:        zsh ~/Downloads/deploy_from_zip.sh ~/Downloads/base-repo-v1_7_0.zip
Переменные:    SHA= sha256 архива · ALSO_PUBLISH="1.5.0" · OWNER/REPO_URL/BRANCH/MSG
USAGE
exit 1; }

ZIP="${1:-}"; [ -n "$ZIP" ] || usage
[ -f "$ZIP" ] || die "архив не найден: $ZIP"
command -v git >/dev/null 2>&1 || die "git не найден"
HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1
[ "$HAVE_GH" -eq 1 ] || ylw "⚠ gh не найден: пуш/тег пройдут, Release-шаг напечатает ручные команды"

# --- ШАГ 1: целостность архива -------------------------------------------------
GOT_SHA="$(/usr/bin/shasum -a 256 "$ZIP" | /usr/bin/awk '{print $1}')"
if [ -n "${SHA:-}" ]; then
  [ "$GOT_SHA" = "$SHA" ] || die "sha256 не совпал (архив побился при скачивании — перекачай):
  ожидал $SHA
  получил $GOT_SHA"
  grn "✓ sha256 совпал — доставка архива подтверждена"
else
  ylw "→ sha256 архива: $GOT_SHA (SHA= не задан — сверь глазами с чатом)"
fi

# --- ШАГ 2: распаковка, обёртка, имя/версия, маркеры ----------------------------
WORK="$HOME/Downloads/repo_deploy_$(date +%Y%m%d_%H%M%S)"
/bin/mkdir -p "$WORK" || die "mkdir $WORK"
ylw "→ распаковываю в $WORK/src"
/usr/bin/unzip -oq "$ZIP" -d "$WORK/src" </dev/null || die "unzip не удался"

SRC="$WORK/src"; WRAP=""
n_all=$(ls -A "$SRC" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
n_dir=$(/usr/bin/find "$SRC" -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l | /usr/bin/tr -d ' ')
if [ "$n_all" = "1" ] && [ "$n_dir" = "1" ]; then WRAP="$(ls -A "$SRC")"; SRC="$SRC/$WRAP"; fi  # PIT-007

# имя репы и версия: из обёртки `<repo>-vX_Y_Z` / `<repo>_vX_Y_Z` ...
NAME_FROM_WRAP=""; VER_FROM_WRAP=""
if [ -n "$WRAP" ]; then
  parsed="$(printf '%s' "$WRAP" | /usr/bin/sed -nE 's/^(.+)[-_]v([0-9]+)_([0-9]+)_([0-9]+)$/\1 \2.\3.\4/p')"
  if [ -n "$parsed" ]; then NAME_FROM_WRAP="${parsed%% *}"; VER_FROM_WRAP="${parsed#* }"; fi
fi
# ... и/или из файла VERSION в дереве
VER_FROM_FILE=""
[ -f "$SRC/VERSION" ] && VER_FROM_FILE="$(/usr/bin/tr -d ' \n' < "$SRC/VERSION")"

if [ -n "$VER_FROM_WRAP" ] && [ -n "$VER_FROM_FILE" ] && [ "$VER_FROM_WRAP" != "$VER_FROM_FILE" ]; then
  die "версия в обёртке ($VER_FROM_WRAP) != VERSION в дереве ($VER_FROM_FILE) — не тот архив или битая упаковка"
fi
VER="${VER_FROM_FILE:-$VER_FROM_WRAP}"
REPO_NAME="${REPO_NAME:-${NAME_FROM_WRAP:-$(basename "$ZIP" .zip)}}"
REPO_URL="${REPO_URL:-https://github.com/$OWNER/$REPO_NAME.git}"

# деструктив дальше — только после опознания корня (15-gotchas §2)
[ -f "$SRC/README.md" ] || die "корень не опознан: нет README.md в $SRC — обёртка/архив кривые"
SRC_N=$(/usr/bin/find "$SRC" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$SRC_N" -ge "$MIN_FILES" ] || die "в дереве всего $SRC_N файлов (< $MIN_FILES) — не похоже на репу"
grn "✓ корень опознан: репа '$REPO_NAME', версия '${VER:-<нет — только push>}', файлов: $SRC_N"
ylw "→ цель: $REPO_URL ($BRANCH)"

# --- ШАГ 3: клон -> чистая замена -> commit -> push -----------------------------
ylw "→ клонирую $REPO_URL"
retry "git clone" git clone "$REPO_URL" "$WORK/repo" || die "не удалось клонировать после $RETRIES попыток"
cd "$WORK/repo" || die "cd в клон"
git checkout -B "$BRANCH" >/dev/null 2>&1 || true

ylw "→ чистая замена дерева (кроме .git)   # чистка ≠ долив, PIT-004"
/usr/bin/find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec /bin/rm -rf {} +
/bin/cp -a "$SRC/." .
/usr/bin/find . -name '.DS_Store' -delete 2>/dev/null || true
/usr/bin/find . -name '__MACOSX' -type d -exec /bin/rm -rf {} + 2>/dev/null || true

git add -A -f   # PIT-006
if git diff --cached --quiet; then
  ylw "→ дерево на GitHub уже актуально — коммит не нужен"
else
  git config user.name  >/dev/null 2>&1 || git config user.name  "$OWNER"
  git config user.email >/dev/null 2>&1 || git config user.email "$OWNER@users.noreply.github.com"
  COMMIT_MSG="${MSG:-release: ${VER:+v$VER — }$REPO_NAME tree sync}"
  git commit -m "$COMMIT_MSG" || die "commit не удался"
  grn "✓ коммит: $COMMIT_MSG"
  push(){ git push -u origin "$BRANCH"; }
  retry "git push" push || die "не удалось запушить после $RETRIES попыток (проверь токен/доступ)"
  grn "✓ запушено"
fi

# автопроверка: коммит == дерево (равенство, не «больше нуля»)
TREE_N=$(/usr/bin/find . -path ./.git -prune -o -type f -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')
GIT_N=$(git ls-tree -r --name-only HEAD | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$GIT_N" = "$TREE_N" ] || die "автопроверка: в коммите $GIT_N файлов, в дереве $TREE_N — что-то съелось (PIT-006/007)"
grn "✓ автопроверка: в коммите $GIT_N файлов (== дереву)"

# --- ШАГ 4: тег + Release через publish.sh из самого дерева ---------------------
PUB=""
[ -f "./templates/publish.sh" ] && PUB="./templates/publish.sh"
[ -z "$PUB" ] && [ -f "./publish.sh" ] && PUB="./publish.sh"

if [ -z "$VER" ]; then
  ylw "⚠ версия не определена (нет VERSION и версии в обёртке) — тег/релиз пропущены. Пуш выполнен."
elif [ -z "$PUB" ]; then
  ylw "⚠ publish.sh не найден в дереве — тег/релиз вручную:"
  echo "    git tag -a v$VER -m 'v$VER' && git push origin v$VER"
  echo "    gh release create v$VER --notes-file <файл-с-секцией-CHANGELOG>"
else
  ylw "→ выпускаю v$VER: zsh $PUB --version $VER --auto-asset"
  zsh "$PUB" --version "$VER" --auto-asset || die "publish v$VER не завершился — клон цел: $WORK/repo; перезапуск той же команды безопасен (режим доделки)"
  grn "✓ v$VER: тег + Release готовы"
  for extra in ${ALSO_PUBLISH:-}; do
    ylw "→ доделка v$extra: zsh $PUB --version $extra --auto-asset"
    zsh "$PUB" --version "$extra" --auto-asset || die "доделка v$extra не завершилась — перезапуск безопасен"
    grn "✓ v$extra доделана (осмысленное описание не перезаписывалось)"
  done
fi

# --- ИТОГ ------------------------------------------------------------------------
echo ""
grn "ГОТОВО: $REPO_NAME ($BRANCH), файлов: $GIT_N${VER:+, версия v$VER}"
[ "$HAVE_GH" -eq 1 ] && gh release list --limit 3 2>/dev/null || true
cd "$HOME" && /bin/rm -rf "$WORK"
grn "✓ рабочая папка убрана"
