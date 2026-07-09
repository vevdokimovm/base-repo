#!/usr/bin/env bash
# =============================================================================
# push_base_repo.sh — залить свежий base-repo в его УЖЕ существующую репу на
#                     GitHub чистым коммитом (полная замена дерева).
#
# Часть base-repo (00-infrastructure/). Обновление base-repo самой; раздачу его
# в остальные 10 реп делает sync-all.sh (рядом).
#
# ЗАЩИТЫ (уроки reports/situations/2026-07-08-* и 2026-07-09-*):
#   - git add -A -f      → мимо .gitignore, файлы НЕ теряются (PIT-006)
#   - авто-разворот обёртки при распаковке → нет вложенности base-repo/base-repo (PIT-007)
#   - клон → стереть дерево КРОМЕ .git → положить новое → add -f  (чистка ≠ долив, PIT-004)
#   - автопроверка git ls-tree | wc -l после пуша → ловит оба бага мгновенно (PIT-008)
#   - ретраи под РФ-TLS-таймауты; абсолютные пути; пропуск при отсутствии, без слепых удалений.
#
# Запуск (macOS/zsh):
#   1) поправь SRC (папка с распакованным base-repo ИЛИ путь к base-repo.zip) и REPO_URL
#   2) zsh ~/Downloads/push_base_repo.sh
# =============================================================================

set -u

# ------------------------------------------------------------------ НАСТРОЙ ---
# Папка с base-repo ИЛИ путь к .zip (скрипт сам распакует и развернёт обёртку):
SRC="${SRC:-$HOME/Downloads/base-repo}"
REPO_URL="${REPO_URL:-https://github.com/vevdokimovm/base-repo.git}"
BRANCH="${BRANCH:-main}"
MSG="${MSG:-release: v1.4.0 — reporting/versioning/experiments + sync tooling}"
RETRIES="${RETRIES:-5}"; RETRY_SLEEP="${RETRY_SLEEP:-4}"
# -----------------------------------------------------------------------------

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }
die(){ red "ОШИБКА: $*"; exit 1; }
retry(){ d="$1"; shift; a=1; s="$RETRY_SLEEP"
  while [ "$a" -le "$RETRIES" ]; do "$@" && return 0
    ylw "  попытка $a/$RETRIES ($d) не удалась — жду ${s}s (вероятно TLS-таймаут к GitHub)"
    sleep "$s"; a=$((a+1)); s=$((s*2)); done; return 1; }

# развернуть обёртку: если в папке ровно одна директория и нет файлов — спуститься
unwrap(){ d="$1"
  n_all=$(ls -A "$d" | wc -l | tr -d ' ')
  n_dir=$(find "$d" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  if [ "$n_all" = "1" ] && [ "$n_dir" = "1" ]; then echo "$d/$(ls -A "$d")"; else echo "$d"; fi
}

command -v git >/dev/null 2>&1 || die "git не найден"

# --- подготовить SRC: если это .zip — распаковать во временную и развернуть обёртку ---
if [ -f "$SRC" ] && printf '%s' "$SRC" | grep -qiE '\.zip$'; then
  TMPZ="$(mktemp -d -t baserepo_src.XXXXXX)"; trap 'rm -rf "$TMPZ"' EXIT
  ylw "→ распаковываю $SRC"
  unzip -oq "$SRC" -d "$TMPZ" </dev/null || die "unzip не удался"
  SRC="$(unwrap "$TMPZ")"
else
  [ -d "$SRC" ] || die "SRC не найден: $SRC (укажи папку base-repo или путь к .zip)"
  SRC="$(unwrap "$SRC")"
fi
[ -f "$SRC/00-infrastructure/README.md" ] || die "SRC не похож на base-repo (нет 00-infrastructure/README.md): $SRC"
ylw "→ источник: $SRC"

WORK="$(mktemp -d -t baserepo_push.XXXXXX)"
cleanup(){ rm -rf "$WORK"; [ -n "${TMPZ:-}" ] && rm -rf "$TMPZ"; }
trap cleanup EXIT

# --- клон существующей репы (сохраняем .git-историю) ---
ylw "→ клонирую $REPO_URL"
retry "git clone" git clone "$REPO_URL" "$WORK/repo" || die "не удалось клонировать после $RETRIES попыток"
cd "$WORK/repo" || die "cd"
git checkout -B "$BRANCH" >/dev/null 2>&1 || true

# --- стереть рабочее дерево КРОМЕ .git ---
ylw "→ очищаю рабочее дерево клона (кроме .git)"
find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +

# --- положить новую версию (включая dotfiles) ---
ylw "→ копирую base-repo из $SRC"
cp -a "$SRC/." .
find . -name '.DS_Store' -delete 2>/dev/null || true
find . -name '__MACOSX' -type d -exec rm -rf {} + 2>/dev/null || true

# --- один чистый коммит; add -A -f мимо .gitignore, чтобы файлы не потерялись ---
git add -A -f
if git diff --cached --quiet; then grn "✓ изменений нет — репа уже актуальна."; exit 0; fi
git config user.name  >/dev/null 2>&1 || git config user.name  "vevdokimovm"
git config user.email >/dev/null 2>&1 || git config user.email "vevdokimovm@users.noreply.github.com"
git commit -m "$MSG" || die "commit не удался"
grn "✓ коммит: $MSG"

# --- пуш с ретраями ---
push(){ git push -u origin "$BRANCH"; }
retry "git push" push || die "не удалось запушить после $RETRIES попыток (проверь доступ/токен)"
grn "✓ запушено в $REPO_URL ($BRANCH)"

# --- АВТОПРОВЕРКА: число файлов в дереве (ловит .gitignore-баг и вложенность) ---
N=$(git ls-tree -r --name-only HEAD | wc -l | tr -d ' ')
echo ""
if [ "$N" -le 1 ]; then
  red "⚠ в дереве всего $N файл — похоже на баг (.gitignore съел файлы или вложенность). Проверь!"
else
  grn "✓ автопроверка: в дереве $N файлов (норма — ноль/один = баг)"
fi
ylw "Дальше по желанию — тег + Release v1.4.0 (описание в CHANGELOG): zsh \"$SRC/templates/publish.sh\" --minor"
