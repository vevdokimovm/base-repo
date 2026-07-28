#!/bin/zsh
# =============================================================================
# commit_all_versions.sh — коммитит в main все версии из архивов, которых там ещё нет.
# Теги и GitHub Releases НЕ трогает (это делает push_archives.sh).
#
#   zsh build/commit_all_versions.sh              # ищет архивы в ~/Downloads
#   zsh build/commit_all_versions.sh ~/Downloads
#   DRY=1 zsh build/commit_all_versions.sh        # только план
# =============================================================================
GIT=/usr/bin/git;  [ -x "$GIT" ] || GIT=$(command -v git)
UNZIP=/usr/bin/unzip
MKTEMP=/usr/bin/mktemp
FIND=/usr/bin/find
BASENAME=/usr/bin/basename
SORT=/usr/bin/sort
SED=/usr/bin/sed
RM=/bin/rm
CP=/bin/cp
CAT=/bin/cat

red(){ print -P "%F{red}$*%f"; }
grn(){ print -P "%F{green}$*%f"; }
ylw(){ print -P "%F{yellow}$*%f"; }
bld(){ print -P "%B$*%b"; }
die(){ red "❌ $*"; exit 1; }

OWNER="${OWNER:-vevdokimovm}"
REPO_NAME="${REPO:-portrait-of-taste}"
BRANCH="${BRANCH:-main}"
DIR="${1:-$HOME/Downloads}"
DRY="${DRY:-0}"

[ -d "$DIR" ] || die "папка не найдена: $DIR"
$GIT --version >/dev/null 2>&1 || die "git не найден"

bld ""
bld "═══════════════════════════════════════════════════════"
bld "  commit_all_versions → $OWNER/$REPO_NAME"
bld "═══════════════════════════════════════════════════════"
bld "  Ищу portrait-of-taste-v*.zip в $DIR"

# --- Сбор архивов ---
LIST=$($MKTEMP)
setopt NULL_GLOB 2>/dev/null || true
for z in "$DIR"/portrait-of-taste-v*.zip; do
    [ -f "$z" ] || continue
    base=$($BASENAME "$z" .zip)
    ver=$(echo "$base" | $SED -nE 's/^portrait-of-taste-v([0-9]+)[._]([0-9]+)[._]([0-9]+)$/\1.\2.\3/p')
    [ -n "$ver" ] || continue
    printf '%s\t%s\n' "$ver" "$z" >> "$LIST"
done
[ -s "$LIST" ] || die "не нашёл ни одного portrait-of-taste-v*.zip в $DIR"

SORTED=$($MKTEMP)
$SORT -t. -k1,1n -k2,2n -k3,3n "$LIST" > "$SORTED"

echo
bld "  Найденные архивы:"
while IFS=$'\t' read -r v p; do echo "    v$v  $($BASENAME "$p")"; done < "$SORTED"

# --- Клон ---
bld ""; bld "── Клонирую репозиторий"
WORK=$($MKTEMP -d); trap "$RM -rf '$WORK'" EXIT
a=1
while [ "$a" -le 5 ]; do
    $GIT clone --quiet "https://github.com/$OWNER/$REPO_NAME.git" "$WORK/repo" 2>&1 && break
    ylw "  попытка $a/5, жду $((a*4))s"; sleep $((a*4)); a=$((a+1))
    [ "$a" -gt 5 ] && die "не смог клонировать"
done
cd "$WORK/repo" || die "cd в клон"
$GIT checkout -q "$BRANCH" 2>/dev/null || $GIT checkout -qb "$BRANCH"

CUR_VER="0.0.0"
[ -f VERSION ] && CUR_VER=$($CAT VERSION | tr -d ' \n')
grn "  ✓ main сейчас на версии: v$CUR_VER"

# --- Что коммитить ---
verlte() { [ "$1" = "$(printf '%s\n%s' "$1" "$2" | $SORT -t. -k1,1n -k2,2n -k3,3n | head -1)" ]; }

TODO=$($MKTEMP)
while IFS=$'\t' read -r v p; do
    if verlte "$v" "$CUR_VER" && [ "$v" != "$CUR_VER" ]; then continue; fi
    [ "$v" = "$CUR_VER" ] && continue
    printf '%s\t%s\n' "$v" "$p" >> "$TODO"
done < "$SORTED"

if [ ! -s "$TODO" ]; then
    grn ""; grn "  ✅ Всё уже закоммичено, main актуален (v$CUR_VER)"
    exit 0
fi

echo
bld "  К коммиту ($(wc -l < "$TODO" | tr -d ' ') версий):"
while IFS=$'\t' read -r v p; do echo "    → v$v"; done < "$TODO"

if [ "$DRY" = "1" ]; then
    echo; ylw "  DRY=1 — только план, ничего не делаю"; exit 0
fi

# --- git config ---
[ -z "$($GIT config user.email 2>/dev/null)" ] && $GIT config user.email "${OWNER}@users.noreply.github.com"
[ -z "$($GIT config user.name 2>/dev/null)" ] && $GIT config user.name "$OWNER"

# --- Коммитим каждую версию по порядку ---
echo
bld "═══════════════════════════════════════════════════════"
N=0
while IFS=$'\t' read -r v p; do
    N=$((N+1))
    bld ""; bld "── v$v"

    EX=$($MKTEMP -d)
    $UNZIP -qq -o "$p" -d "$EX" 2>/dev/null || { red "  ✗ не распаковался, пропускаю"; $RM -rf "$EX"; continue; }

    # ищу корень (папка с VERSION внутри обёртки, или сам EX)
    ROOT="$EX"
    if [ ! -f "$EX/VERSION" ]; then
        CAND=$($FIND "$EX" -maxdepth 2 -name VERSION -type f 2>/dev/null | head -1)
        [ -n "$CAND" ] && ROOT=$(dirname "$CAND")
    fi
    [ -f "$ROOT/VERSION" ] || { red "  ✗ нет VERSION в архиве, пропускаю"; $RM -rf "$EX"; continue; }

    # чистая замена дерева (кроме .git) — иначе удалённые в новой версии файлы останутся
    $FIND . -mindepth 1 -maxdepth 1 -not -name '.git' -exec $RM -rf {} +
    $CP -a "$ROOT/." .
    $FIND . -name '.DS_Store' -delete 2>/dev/null
    $FIND . -name '__MACOSX' -type d -exec $RM -rf {} + 2>/dev/null
    $RM -rf "$EX"

    # ВАЖНО: cp -a сохраняет mtime из архива. Git использует stat-кэш (mtime+size) и
    # при совпадении считает файл неизменённым, не пересчитывая хэш — из-за этого
    # вторая и последующие версии выглядели как "без изменений". Сбрасываем mtime.
    $FIND . -path ./.git -prune -o -type f -exec /usr/bin/touch {} +

    $GIT add -A -f
    if $GIT diff --cached --quiet; then
        ylw "  = без изменений, пропускаю коммит"
        continue
    fi
    CH=$($GIT diff --cached --numstat | wc -l | tr -d ' ')
    $GIT commit -q -m "release: v${v}" || { red "  ✗ commit не удался"; continue; }
    grn "  ✓ коммит создан (файлов: $CH)"
done < "$TODO"

# --- Один push всех коммитов ---
bld ""; bld "── Push всех коммитов в $BRANCH"
a=1
while [ "$a" -le 5 ]; do
    $GIT push -u origin "$BRANCH" 2>&1 && break
    ylw "  попытка $a/5, жду $((a*4))s"; sleep $((a*4)); a=$((a+1))
    [ "$a" -gt 5 ] && die "не смог запушить"
done

echo
bld "═══════════════════════════════════════════════════════"
grn "  ✅ Готово. Теги и релизы не тронуты."
bld "═══════════════════════════════════════════════════════"
echo
$GIT log --oneline -10
echo
echo "  https://github.com/$OWNER/$REPO_NAME"
