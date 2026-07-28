#!/usr/bin/env bash
# =============================================================================
# deploy_all_versions.sh — БАТЧ-деплой: все версии всех реп из папки за один прогон.
#
# Берёт папку (по умолчанию ~/Downloads), находит ВСЕ версионные архивы, группирует
# их по репозиториям, сортирует по SemVer и публикует историю версий подряд:
#     распаковка -> маркеры корня -> клон -> чистая замена дерева -> коммит -> тег
#     -> push -> GitHub Release с описанием из секции CHANGELOG этой версии.
#
# Пара к deploy_from_zip.sh: тот публикует ОДИН архив, этот — ВСЮ историю сразу
# и сразу по нескольким репам (dota-dossier, exam-kit, что угодно).
#
# ЗАПУСК (macOS/zsh):
#   zsh ~/Downloads/deploy_all_versions.sh
#   zsh ~/Downloads/deploy_all_versions.sh ~/Downloads
#
#   ONLY=dota-dossier   — обработать только эти репы (через пробел)
#   SKIP="base-repo self-map"  — не трогать эти репы вообще
#   BACKFILL=1          — разрешить публикацию версий НИЖЕ старшего существующего тега
#                         (по умолчанию запрещено: скрипт только надбавляет сверху)
#   DRY=1               — показать план и выйти, ничего не менять
#   PRIVATE=0           — создавать публичные репы (по умолчанию приватные)
#   ASSET=0             — НЕ прикладывать zip к релизу (по умолчанию прикладывается
#                         под каноническим именем <repo>-vX.Y.Z.zip)
#   ASSETS_ONLY=1       — ничего не публиковать, только дозалить недостающие ассеты
#                         в уже существующие релизы (для реп, залитых старой версией)
#   OWNER=... BRANCH=... — переопределяемы
#
# ИМЕНА АРХИВОВ (понимает оба варианта):
#   <repo>-vX_Y_Z.zip     — конвенция base-repo
#   <repo>_vX.Y.Z.zip     — конвенция архивов от Claude
#   Версия дополнительно сверяется с файлом VERSION в дереве: расхождение -> стоп.
#
# ЗАЩИТЫ (как в deploy_from_zip.sh):
#   разворот обёртки (PIT-007) · ДЕСТРУКТИВ ТОЛЬКО ПОСЛЕ МАРКЕРОВ корня ·
#   чистка-кроме-.git (PIT-004) · add -A -f (PIT-006) · автопроверка
#   «файлов в коммите == файлов в дереве» · ретраи под РФ-TLS · идемпотентность:
#   существующие теги пропускаются · на падении рабочая папка сохраняется.
# =============================================================================

set -u
# zsh не разбивает $var на слова (в отличие от bash) — циклы ниже используют while-read,
# но на случай запуска через `zsh script.sh` включаем совместимое поведение явно.
if [ -n "${ZSH_VERSION:-}" ]; then setopt shwordsplit 2>/dev/null || true; fi

DIR="${1:-$HOME/Downloads}"
OWNER="${OWNER:-vevdokimovm}"
BRANCH="${BRANCH:-main}"
RETRIES="${RETRIES:-5}"; RETRY_SLEEP="${RETRY_SLEEP:-4}"
MIN_FILES="${MIN_FILES:-5}"
PRIVATE="${PRIVATE:-1}"
ASSET="${ASSET:-1}"
DRY="${DRY:-0}"

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }
bld(){ printf '\033[1m%s\033[0m\n' "$*"; }
die(){ red "ОШИБКА: $*"; [ -n "${WORK:-}" ] && [ -d "${WORK:-}" ] && red "Рабочая папка сохранена: $WORK"; exit 1; }
retry(){ d="$1"; shift; a=1; s="$RETRY_SLEEP"
  while [ "$a" -le "$RETRIES" ]; do "$@" && return 0
    ylw "  попытка $a/$RETRIES ($d) не удалась — жду ${s}s (вероятно TLS-таймаут к GitHub)"
    sleep "$s"; a=$((a+1)); s=$((s*2)); done; return 1; }

command -v git >/dev/null 2>&1 || die "git не найден"
HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1
[ "$HAVE_GH" -eq 1 ] || ylw "⚠ gh не найден: пуш и теги пройдут, релизы придётся создать вручную"
[ -d "$DIR" ] || die "папка не найдена: $DIR"

# --- ШАГ 1: инвентаризация архивов ---------------------------------------------
bld "── Шаг 1. Ищу версионные архивы в $DIR"
INDEX="$(mktemp)"
for z in "$DIR"/*.zip; do
  [ -f "$z" ] || continue
  base="$(basename "$z" .zip)"
  parsed="$(printf '%s' "$base" | /usr/bin/sed -nE 's/^(.+)[-_]v([0-9]+)[._]([0-9]+)[._]([0-9]+)$/\1 \2.\3.\4/p')"
  [ -n "$parsed" ] || continue
  name="${parsed%% *}"; ver="${parsed#* }"
  skip=0
  for sname in ${SKIP:-}; do [ "$name" = "$sname" ] && skip=1; done
  [ "$skip" = "1" ] && continue
  if [ -n "${ONLY:-}" ]; then
    keep=0; for oname in $ONLY; do [ "$name" = "$oname" ] && keep=1; done
    [ "$keep" = "1" ] || continue
  fi
  printf '%s\t%s\t%s\n' "$name" "$ver" "$z" >> "$INDEX"
done
[ -s "$INDEX" ] || die "версионных архивов не найдено (ожидаю <repo>-vX_Y_Z.zip или <repo>_vX.Y.Z.zip)"

REPOLIST="$(mktemp)"
/usr/bin/cut -f1 "$INDEX" | /usr/bin/sort -u > "$REPOLIST"
while IFS= read -r r; do
  [ -n "$r" ] || continue
  n="$(/usr/bin/awk -F'\t' -v r="$r" '$1==r' "$INDEX" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  vers="$(/usr/bin/awk -F'\t' -v r="$r" '$1==r{print $2}' "$INDEX" | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n | /usr/bin/tr '\n' ' ')"
  grn "  $r — версий: $n → $vers"
done < "$REPOLIST"
[ -n "${SKIP:-}" ] && ylw "  пропускаются по SKIP: $SKIP"

if [ "$DRY" = "1" ]; then ylw "DRY=1 — только план, выходим"; /bin/rm -f "$INDEX" "$REPOLIST"; exit 0; fi

WORK="$HOME/Downloads/repo_deploy_all_$(date +%Y%m%d_%H%M%S)"
/bin/mkdir -p "$WORK" || die "mkdir $WORK"

# --- обработка каждой репы ------------------------------------------------------
# --- режим ASSETS_ONLY: дозалить ассеты в существующие релизы ---------------
if [ "${ASSETS_ONLY:-0}" = "1" ]; then
  [ "$HAVE_GH" -eq 1 ] || die "ASSETS_ONLY требует gh"
  while IFS= read -r REPO_NAME; do
    [ -n "$REPO_NAME" ] || continue
    echo ""; bld "══ Ассеты: $REPO_NAME"
    /usr/bin/awk -F'\t' -v r="$REPO_NAME" '$1==r{print $2"\t"$3}' "$INDEX" \
      | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n > "$WORK/assets_$REPO_NAME.txt"
    while IFS="$(printf '\t')" read -r VER ZIP; do
      [ -n "$VER" ] || continue
      if ! gh release view "v$VER" --repo "$OWNER/$REPO_NAME" >/dev/null 2>&1; then
        ylw "  v$VER: релиза нет, пропускаю"; continue
      fi
      ANAME="$REPO_NAME-v$VER.zip"
      if gh release view "v$VER" --repo "$OWNER/$REPO_NAME" --json assets \
           --jq '.assets[].name' 2>/dev/null | /usr/bin/grep -qx "$ANAME"; then
        ylw "  v$VER: ассет уже есть"; continue
      fi
      /bin/cp "$ZIP" "$WORK/$ANAME"
      if gh release upload "v$VER" "$WORK/$ANAME" --repo "$OWNER/$REPO_NAME" --clobber >/dev/null 2>&1; then
        grn "  ✓ v$VER: залит $ANAME"
      else
        red "  ✗ v$VER: не удалось залить ассет"
      fi
      /bin/rm -f "$WORK/$ANAME"
    done < "$WORK/assets_$REPO_NAME.txt"
  done < "$REPOLIST"
  /bin/rm -f "$INDEX" "$REPOLIST"; cd "$HOME" && /bin/rm -rf "$WORK"
  echo ""; grn "✓ дозаливка ассетов завершена"; exit 0
fi

while IFS= read -r REPO_NAME; do
  [ -n "$REPO_NAME" ] || continue
  echo ""; bld "══ Репозиторий: $REPO_NAME"
  REPO_URL="https://github.com/$OWNER/$REPO_NAME.git"

  # ШАГ 2: репа существует?
  if [ "$HAVE_GH" -eq 1 ]; then
    if ! gh repo view "$OWNER/$REPO_NAME" >/dev/null 2>&1; then
      VIS="--private"; [ "$PRIVATE" = "0" ] && VIS="--public"
      ylw "→ репозитория нет, создаю ($VIS)"
      DESC="$(printf '%s' "$REPO_NAME" | /usr/bin/tr -d '\n\r\t')"
      gh repo create "$OWNER/$REPO_NAME" $VIS --description "$DESC" >/dev/null \
        || die "не удалось создать репозиторий $OWNER/$REPO_NAME"
      grn "✓ репозиторий создан"
    fi
  fi

  CLONE="$WORK/$REPO_NAME"
  ylw "→ клонирую $REPO_URL"
  if ! retry "git clone" git clone "$REPO_URL" "$CLONE" 2>/dev/null; then
    ylw "  клон не удался (пустая или новая репа) — инициализирую локально"
    /bin/mkdir -p "$CLONE" && cd "$CLONE" || die "mkdir клона"
    git init -q -b "$BRANCH" || die "git init"
    git remote add origin "$REPO_URL" || die "git remote add"
  fi
  cd "$CLONE" || die "cd $CLONE"
  git checkout -B "$BRANCH" >/dev/null 2>&1 || true
  git config user.name  >/dev/null 2>&1 || git config user.name  "$OWNER"
  git config user.email >/dev/null 2>&1 || git config user.email "$OWNER@users.noreply.github.com"

  EXISTING_TAGS="$(git tag -l 2>/dev/null | /usr/bin/tr '\n' ' ')"
  HIGHEST="$(git tag -l 'v*' 2>/dev/null | /usr/bin/sed 's/^v//' \
             | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n | /usr/bin/tail -1)"
  [ -n "$HIGHEST" ] && ylw "  старший опубликованный тег: v$HIGHEST (ниже него — не трогаю)"
  NOTES_DIR="$WORK/notes_$REPO_NAME"; /bin/mkdir -p "$NOTES_DIR"
  PUBLISHED=""

  # ШАГ 3: версии по возрастанию
  VERLIST="$WORK/vers_$REPO_NAME.txt"
  /usr/bin/awk -F'\t' -v r="$REPO_NAME" '$1==r{print $2}' "$INDEX" \
    | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n > "$VERLIST"
  while IFS= read -r VER; do
    [ -n "$VER" ] || continue
    ZIP="$(/usr/bin/awk -F'\t' -v r="$REPO_NAME" -v v="$VER" '$1==r && $2==v{print $3; exit}' "$INDEX")"
    case " $EXISTING_TAGS " in *" v$VER "*) ylw "→ v$VER: тег уже есть, пропускаю"; continue;; esac
    if [ -n "$HIGHEST" ] && [ "${BACKFILL:-0}" != "1" ]; then
      NEWEST="$(printf '%s\n%s\n' "$HIGHEST" "$VER" | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n | /usr/bin/tail -1)"
      if [ "$NEWEST" != "$VER" ]; then
        ylw "→ v$VER: ниже опубликованного v$HIGHEST — пропускаю (BACKFILL=1 чтобы всё же залить)"
        continue
      fi
    fi

    echo ""; ylw "→ v$VER  ($(basename "$ZIP"))"
    SRCDIR="$WORK/unpack_${REPO_NAME}_$VER"
    /bin/rm -rf "$SRCDIR"; /bin/mkdir -p "$SRCDIR"
    /usr/bin/unzip -oq "$ZIP" -d "$SRCDIR" </dev/null || die "unzip не удался: $ZIP"

    SRC="$SRCDIR"
    n_all=$(ls -A "$SRC" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    n_dir=$(/usr/bin/find "$SRC" -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    [ "$n_all" = "1" ] && [ "$n_dir" = "1" ] && SRC="$SRC/$(ls -A "$SRC")"   # PIT-007

    # маркеры корня — до любого деструктива
    [ -f "$SRC/README.md" ] || die "v$VER: корень не опознан (нет README.md) — кривой архив"
    SRC_N=$(/usr/bin/find "$SRC" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    [ "$SRC_N" -ge "$MIN_FILES" ] || die "v$VER: файлов $SRC_N (< $MIN_FILES) — не похоже на репу"

    # сверка версии с VERSION в дереве
    if [ -f "$SRC/VERSION" ]; then
      VF="$(/usr/bin/tr -d ' \n' < "$SRC/VERSION")"
      [ "$VF" = "$VER" ] || die "v$VER: VERSION в дереве = $VF — не тот архив"
    fi

    # описание релиза из секции CHANGELOG этой версии.
    # Понимает оба диалекта заголовков:
    #   ## [1.15.0] — дата — заголовок (MINOR)      (base-repo / dota-dossier)
    #   ## v1.15.0 — дата                            (exam-kit)
    NOTES="$NOTES_DIR/v$VER.md"
    if [ -f "$SRC/CHANGELOG.md" ]; then
      VRE="$(printf '%s' "$VER" | /usr/bin/sed 's/\./\\./g')"
      /usr/bin/awk -v vre="$VRE" '
        !started && $0 ~ "^## \\[?v?" vre "\\]?([^0-9]|$)" { started=1; print; next }
        started && $0 ~ "^## \\[?v?[0-9]+\\.[0-9]+\\.[0-9]+" { exit }
        started && /^---[ \t]*$/ { next }
        started { print }' "$SRC/CHANGELOG.md" > "$NOTES"
    fi
    [ -s "$NOTES" ] || printf '## %s v%s\n\nСинхронизация дерева.\n' "$REPO_NAME" "$VER" > "$NOTES"

    # чистая замена дерева (чистка ≠ долив, PIT-004)
    /usr/bin/find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec /bin/rm -rf {} +
    /bin/cp -a "$SRC/." .
    /usr/bin/find . -name '.DS_Store' -delete 2>/dev/null || true
    /usr/bin/find . -name '__MACOSX' -type d -exec /bin/rm -rf {} + 2>/dev/null || true

    git add -A -f   # PIT-006
    if git diff --cached --quiet && [ -n "$(git tag -l)" ]; then
      ylw "  дерево не изменилось — ставлю только тег"
    else
      git commit -q -m "release: v$VER — $REPO_NAME tree sync" || die "commit v$VER"
      TREE_N=$(/usr/bin/find . -path ./.git -prune -o -type f -print | /usr/bin/wc -l | /usr/bin/tr -d ' ')
      GIT_N=$(git ls-tree -r --name-only HEAD | /usr/bin/wc -l | /usr/bin/tr -d ' ')
      [ "$GIT_N" = "$TREE_N" ] || die "v$VER: в коммите $GIT_N файлов, в дереве $TREE_N (PIT-006/007)"
      grn "  ✓ коммит: $GIT_N файлов"
    fi
    git tag -a "v$VER" -m "v$VER" || die "tag v$VER"
    PUBLISHED="$PUBLISHED $VER"
    /bin/rm -rf "$SRCDIR"
  done < "$VERLIST"

  [ -n "$PUBLISHED" ] || { ylw "→ новых версий нет, репа актуальна"; continue; }

  # ШАГ 4: push ветки и тегов
  echo ""; ylw "→ пушу ветку и теги"
  pushb(){ git push -u origin "$BRANCH"; }
  pusht(){ git push origin --tags; }
  retry "git push branch" pushb || die "не удалось запушить ветку (проверь токен и доступ)"
  retry "git push tags"   pusht || die "не удалось запушить теги"
  grn "✓ запушено"

  # ШАГ 5: релизы
  if [ "$HAVE_GH" -eq 1 ]; then
    for VER in $PUBLISHED; do
      if gh release view "v$VER" >/dev/null 2>&1; then
        ylw "  v$VER: релиз уже есть, пропускаю"; continue
      fi
      TITLE="$REPO_NAME v$VER"
      if [ "$ASSET" = "1" ]; then
        ZIP="$(/usr/bin/awk -F'\t' -v r="$REPO_NAME" -v v="$VER" '$1==r && $2==v{print $3; exit}' "$INDEX")"
        ANAME="$REPO_NAME-v$VER.zip"          # каноническое имя ассета
        /bin/cp "$ZIP" "$WORK/$ANAME"
        gh release create "v$VER" "$WORK/$ANAME" --title "$TITLE" --notes-file "$NOTES_DIR/v$VER.md" >/dev/null \
          && grn "  ✓ релиз v$VER (ассет $ANAME)" || red "  ✗ релиз v$VER не создан"
        /bin/rm -f "$WORK/$ANAME"
      else
        gh release create "v$VER" --title "$TITLE" --notes-file "$NOTES_DIR/v$VER.md" >/dev/null \
          && grn "  ✓ релиз v$VER" || red "  ✗ релиз v$VER не создан"
      fi
    done
  else
    ylw "gh не найден — релизы вручную:"
    for VER in $PUBLISHED; do
      echo "    gh release create v$VER --title '$REPO_NAME v$VER' --notes-file '$NOTES_DIR/v$VER.md'"
    done
  fi

  echo ""; grn "ГОТОВО: $REPO_NAME — опубликованы версии:$PUBLISHED"
  [ "$HAVE_GH" -eq 1 ] && gh release list --limit 5 2>/dev/null || true
done < "$REPOLIST"

/bin/rm -f "$INDEX" "$REPOLIST"
cd "$HOME" && /bin/rm -rf "$WORK"
echo ""; grn "✓ все репозитории обработаны, рабочая папка убрана"
