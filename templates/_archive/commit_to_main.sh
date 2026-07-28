#!/bin/zsh
# =============================================================================
# commit_to_main.sh — закоммитить актуальное содержимое репы в ветку main.
#
# ЧТО ДЕЛАЕТ: клон → копирует файлы поверх → коммит → push в main. Всё.
# ЧЕГО НЕ ДЕЛАЕТ: не трогает теги, не трогает GitHub Releases, ничего не удаляет.
#
# ЗАЧЕМ: push_archives.sh обновлял только Releases (теги + ассеты), но никогда не
# коммитил в main — раздел "Code" на GitHub застрял на v1.0.0, пока релизы шли до
# v1.0.8. Этот скрипт закрывает вторую половину. См. reports/pitfalls.md PIT-115.
#
# ЗАПУСК:
#   zsh commit_to_main.sh <путь-к-распакованной-папке-репы>
#   zsh commit_to_main.sh ~/Downloads/portrait-of-taste-v1_0_9
#
# ENV: OWNER=vevdokimovm  REPO=portrait-of-taste  BRANCH=main  MSG="своё сообщение"
# =============================================================================

# Абсолютные пути к утилитам (защита от битого PATH — PIT-103)
GIT=/usr/bin/git;      [ -x "$GIT" ] || GIT=$(command -v git)
BASENAME=/usr/bin/basename
MKTEMP=/usr/bin/mktemp
FIND=/usr/bin/find
RM=/bin/rm
CP=/bin/cp
CAT=/bin/cat

if   [ -x /opt/homebrew/bin/gh ]; then GH=/opt/homebrew/bin/gh
elif [ -x /usr/local/bin/gh ];    then GH=/usr/local/bin/gh
else GH=$(command -v gh 2>/dev/null); fi

red(){ print -P "%F{red}$*%f"; }
grn(){ print -P "%F{green}$*%f"; }
ylw(){ print -P "%F{yellow}$*%f"; }
bld(){ print -P "%B$*%b"; }
die(){ red "❌ $*"; exit 1; }

OWNER="${OWNER:-vevdokimovm}"
REPO_NAME="${REPO:-portrait-of-taste}"
BRANCH="${BRANCH:-main}"

SRC="${1:-}"
[ -n "$SRC" ] || die "укажи путь: zsh commit_to_main.sh ~/Downloads/portrait-of-taste-vX_Y_Z"
[ -d "$SRC" ] || die "папка не найдена: $SRC"
[ -f "$SRC/VERSION" ] || die "в $SRC нет VERSION — это точно распакованная репа?"

VER=$($CAT "$SRC/VERSION" | tr -d ' \n')

bld ""
bld "═══════════════════════════════════════════════════════"
bld "  commit_to_main → $OWNER/$REPO_NAME (v$VER)"
bld "═══════════════════════════════════════════════════════"
ylw "  теги и релизы НЕ трогаются — только коммит в $BRANCH"

$GIT --version >/dev/null 2>&1 || die "git не найден"

# --- 1. Клон ---
bld ""; bld "── 1/4. Клонирую"
WORK=$($MKTEMP -d); trap "$RM -rf '$WORK'" EXIT
a=1
while [ "$a" -le 5 ]; do
    $GIT clone --quiet "https://github.com/$OWNER/$REPO_NAME.git" "$WORK/repo" 2>&1 && break
    ylw "  попытка $a/5 не удалась, жду $((a*4))s"; sleep $((a*4)); a=$((a+1))
    [ "$a" -gt 5 ] && die "не смог клонировать"
done
cd "$WORK/repo" || die "cd в клон"
$GIT checkout -q "$BRANCH" 2>/dev/null || $GIT checkout -qb "$BRANCH"
BEFORE=$($GIT log --oneline -1 2>/dev/null || echo "нет коммитов")
grn "  ✓ клон готов. Последний коммит был: $BEFORE"

# --- 2. Копирую файлы ПОВЕРХ (ничего не удаляю) ---
bld ""; bld "── 2/4. Копирую актуальное содержимое поверх"
$CP -a "$SRC/." .
$FIND . -name '.DS_Store' -delete 2>/dev/null
$FIND . -name '__MACOSX' -type d -exec $RM -rf {} + 2>/dev/null

# предупреждаю о файлах, которые есть в репе, но нет в источнике (не удаляю, просто говорю)
STALE=$($GIT ls-files | while read f; do [ -e "$SRC/$f" ] || echo "$f"; done)
if [ -n "$STALE" ]; then
    ylw "  ⚠ в репе есть файлы, которых нет в источнике (НЕ удалены, разберись сам если надо):"
    echo "$STALE" | sed 's/^/      /'
fi
grn "  ✓ файлы скопированы"

# --- 3. Коммит ---
bld ""; bld "── 3/4. Коммит"
if [ -z "$($GIT config user.email 2>/dev/null)" ]; then
    E=$([ -x "$GH" ] && $GH api user --jq .email 2>/dev/null)
    [ -n "$E" ] && [ "$E" != "null" ] || E="${OWNER}@users.noreply.github.com"
    $GIT config user.email "$E"
fi
[ -z "$($GIT config user.name 2>/dev/null)" ] && $GIT config user.name "$OWNER"

$GIT add -A -f
if $GIT diff --cached --quiet; then
    ylw "  нечего коммитить — дерево уже актуально"
    exit 0
fi

CHANGED=$($GIT diff --cached --numstat | wc -l | tr -d ' ')
$GIT commit -q -m "${MSG:-release: v${VER} — sync repo tree}" || die "commit не удался"
grn "  ✓ закоммичено, файлов изменено/добавлено: $CHANGED"

# автопроверка: git-дерево == диск
GIT_N=$($GIT ls-tree -r --name-only HEAD | wc -l | tr -d ' ')
TREE_N=$($FIND . -path ./.git -prune -o -type f -print | wc -l | tr -d ' ')
[ "$GIT_N" = "$TREE_N" ] || die "автопроверка: в git $GIT_N файлов, на диске $TREE_N — что-то не попало"
grn "  ✓ автопроверка: $GIT_N файлов в git == $TREE_N на диске"

# --- 4. Push ---
bld ""; bld "── 4/4. Push в $BRANCH"
a=1
while [ "$a" -le 5 ]; do
    $GIT push -u origin "$BRANCH" 2>&1 && break
    ylw "  попытка $a/5 не удалась, жду $((a*4))s"; sleep $((a*4)); a=$((a+1))
    [ "$a" -gt 5 ] && die "не смог запушить"
done

echo
bld "═══════════════════════════════════════════════════════"
grn "  ✅ main обновлён (v$VER). Теги и релизы не тронуты."
bld "═══════════════════════════════════════════════════════"
echo
echo "  https://github.com/$OWNER/$REPO_NAME"
echo
echo "  Проверить: git log --oneline -3"
