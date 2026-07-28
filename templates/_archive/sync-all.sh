#!/usr/bin/env bash
# sync-all.sh — обновляет base-repo во всех репах системы и пушит.
#
# ЧТО ДЕЛАЕТ:
#   1. Обновляет локальный base-repo из его архива (~/Downloads/base-repo.zip).
#   2. В каждую репу раскладывает свежий 00-infrastructure/ (kit + claude-context
#      + reports + templates + START-HERE/repos-map/base-repo-readme).
#   3. Коммитит и пушит только те репы, где реально что-то изменилось.
#
# ЗАЩИТА (уроки прошлых факапов):
#   - распаковка через временную папку + авто-разворот обёртки (нет вложенности);
#   - git add -f (мимо .gitignore, файлы не теряются);
#   - работа с абсолютными путями (не промахнёшься мимо папки);
#   - если репы/архива нет — пропуск, ничего не удаляется вслепую.
#
# ИСПОЛЬЗОВАНИЕ:
#   bash ~/repos/base-repo/00-infrastructure/sync-all.sh
#
# ФЛАГИ:
#   --dry-run   показать, что изменится, без коммита и пуша
#   --no-push   закоммитить локально, но не пушить

set -uo pipefail

# ---------- настройки ----------
GH_USER="vevdokimovm"
REPOS_DIR="$HOME/repos"
BASE_ZIP="$HOME/Downloads/base-repo.zip"        # свежий архив base-repo
BASE_DIR="$REPOS_DIR/base-repo"                  # локальный клон base-repo

REPOS=(academic-portfolio edu-base family health-vault it-base \
       legal-knowledge-base misc-vault self-map truth-seeking christ-walk)

DRY_RUN=0; NO_PUSH=0
for a in "$@"; do
  [ "$a" = "--dry-run" ] && DRY_RUN=1
  [ "$a" = "--no-push" ] && NO_PUSH=1
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

# ---------- 0. обновить локальный base-repo из архива ----------
say "0. Обновляю локальный base-repo"
if [ -f "$BASE_ZIP" ]; then
  rm -rf /tmp/base_unz && mkdir -p /tmp/base_unz
  unzip -oq "$BASE_ZIP" -d /tmp/base_unz
  SRC=/tmp/base_unz
  # авто-разворот папки-обёртки
  if [ "$(ls -A "$SRC" | wc -l | tr -d ' ')" = "1" ] && [ -d "$SRC/$(ls -A "$SRC")" ]; then
    SRC="$SRC/$(ls -A "$SRC")"
  fi
  mkdir -p "$BASE_DIR"
  # обновляем рабочее дерево base-repo (кроме .git)
  find "$BASE_DIR" -mindepth 1 -not -path "$BASE_DIR/.git*" -delete 2>/dev/null
  shopt -s dotglob; cp -R "$SRC"/* "$BASE_DIR"/; shopt -u dotglob
  ok "base-repo обновлён из $BASE_ZIP"
else
  warn "нет $BASE_ZIP — беру то, что уже лежит в $BASE_DIR"
  [ -d "$BASE_DIR" ] || { echo "И локального base-repo нет. Прерываю."; exit 1; }
fi

# источник инфраструктуры
K="$BASE_DIR/00-infrastructure"     # kit
CC="$BASE_DIR/01-claude-context"
RP="$BASE_DIR/reports"
TP="$BASE_DIR/templates"

# ---------- функция: собрать 00-infrastructure в целевой репе ----------
build_infra() {
  local dest="$1/00-infrastructure"
  rm -rf "$dest"; mkdir -p "$dest"
  # kit -> в корень слота
  shopt -s dotglob
  [ -d "$K" ] && cp -R "$K"/* "$dest"/ 2>/dev/null
  shopt -u dotglob
  # подпапки
  [ -d "$CC" ] && cp -R "$CC" "$dest/claude-context"
  [ -d "$RP" ] && cp -R "$RP" "$dest/reports"
  [ -d "$TP" ] && cp -R "$TP" "$dest/templates"
  # корневые файлы base-repo
  for f in START-HERE.md start-here.md repos-map.md VERSION version; do
    [ -f "$BASE_DIR/$f" ] && cp "$BASE_DIR/$f" "$dest/$f"
  done
  [ -f "$BASE_DIR/README.md" ] && cp "$BASE_DIR/README.md" "$dest/base-repo-readme.md"
}

# ---------- 1. пройтись по всем репам ----------
changed=(); skipped=()
for r in "${REPOS[@]}"; do
  say "→ $r"
  rd="$REPOS_DIR/$r"
  if [ ! -d "$rd/.git" ]; then
    warn "нет клона в $rd — пропуск (склонируй репу заранее)"; skipped+=("$r"); continue
  fi

  build_infra "$rd"

  cd "$rd" || { warn "cd fail"; continue; }
  git add -A -f 00-infrastructure

  if git diff --cached --quiet; then
    ok "изменений нет"; continue
  fi

  if [ "$DRY_RUN" = "1" ]; then
    ok "(dry-run) изменилось файлов: $(git diff --cached --name-only | wc -l | tr -d ' ')"
    git reset -q; continue
  fi

  git commit -q -m "chore: sync base-repo infrastructure (00-infrastructure)"
  if [ "$NO_PUSH" = "1" ]; then
    ok "закоммичено (без пуша)"
  else
    if git push -q; then ok "запушено"; else warn "push не удался — проверь вручную"; fi
  fi
  changed+=("$r")
  cd "$REPOS_DIR"
done

# ---------- итог ----------
say "ИТОГ"
ok "обновлено реп: ${#changed[@]} ${changed[*]:-—}"
[ "${#skipped[@]}" -gt 0 ] && warn "пропущено (нет клона): ${skipped[*]}"
echo
echo "Проверка числа файлов по репам:"
for r in "${REPOS[@]}"; do
  rd="$REPOS_DIR/$r"
  [ -d "$rd/.git" ] && printf '  %-24s %s файлов\n' "$r" \
    "$(cd "$rd" && git ls-tree -r --name-only HEAD | wc -l | tr -d ' ')"
done
