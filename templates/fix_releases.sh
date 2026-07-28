#!/usr/bin/env bash
# =============================================================================
# fix_releases.sh — привести УЖЕ СУЩЕСТВУЮЩИЕ релизы на GitHub к стандарту.
#
# Зачем отдельно от deploy.sh: deploy.sh занимается доставкой (архив → коммит →
# тег → релиз). Этот чинит то, что уже опубликовано, и ничего не пушит в дерево.
#
# Что делает по каждому релизу каждой репы:
#   1. клонирует репу, находит CHANGELOG ГДЕ УГОДНО в дереве (корень, docs/,
#      00-infrastructure/, глубже) и достаёт секцию нужной версии;
#   2. пересобирает заголовок  <repo> vX.Y.Z — <тезис>  и тело по §42;
#   3. чинит только то, что не по стандарту: заголовок без тезиса, описание-
#      заглушка, пустое тело. Осмысленные описания не трогает (нужен FORCE=1);
#   4. удаляет релизы-пустышки, у которых нет ни секции в CHANGELOG, ни ассета
#      (только с DELETE_EMPTY=1 — по умолчанию просто показывает список).
#
# ЗАПУСК:
#   zsh ~/Downloads/fix_releases.sh              # план, ничего не меняет
#   APPLY=1 zsh ~/Downloads/fix_releases.sh      # применить
#   APPLY=1 ONLY="base-repo" zsh ~/Downloads/fix_releases.sh
#   APPLY=1 DELETE_EMPTY=1 ONLY="self-map" zsh ~/Downloads/fix_releases.sh
#   APPLY=1 FORCE=1 ...                          # переписать даже осмысленные
# =============================================================================
set -u

OWNER="${OWNER:-vevdokimovm}"
APPLY="${APPLY:-0}"
FORCE="${FORCE:-0}"
DELETE_EMPTY="${DELETE_EMPTY:-0}"
ONLY="${ONLY:-}"
SKIP="${SKIP:-}"
REPOS="${REPOS:-base-repo character-a-analysis dota-dossier exam-kit legal-knowledge-base personal-finance-dss portrait-of-taste self-map}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_CYN=$'\033[36m'
  C_MAG=$'\033[35m'; C_BLD=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_CYN=""; C_MAG=""; C_BLD=""; C_DIM=""; C_OFF=""
fi
red(){ printf '%s%s%s\n' "$C_RED" "$*" "$C_OFF"; }
grn(){ printf '%s%s%s\n' "$C_GRN" "$*" "$C_OFF"; }
ylw(){ printf '%s%s%s\n' "$C_YLW" "$*" "$C_OFF"; }
cyn(){ printf '%s%s%s\n' "$C_CYN" "$*" "$C_OFF"; }
dim(){ printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
bld(){ printf '%s%s%s\n' "$C_BLD" "$*" "$C_OFF"; }
die(){ red "ОШИБКА: $*"; exit 1; }

command -v gh >/dev/null 2>&1 || die "нужен GitHub CLI (gh)"
command -v python3 >/dev/null 2>&1 || die "нужен python3"
gh auth status >/dev/null 2>&1 || die "gh не авторизован: gh auth login"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PARSER="$WORK/parse.py"
cat > "$PARSER" <<'PYEOF'
import re, sys
from pathlib import Path
src, ver, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
text = src.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()
start = end = None
pat = re.compile(r'^#{1,3}\s*\[?' + re.escape(ver) + r'\]?(\s|$|—|-|\))')
for i, ln in enumerate(lines):
    if pat.match(ln.strip()):
        start = i; break
if start is None:
    sys.exit(1)
head = lines[start].strip()
for j in range(start + 1, len(lines)):
    if re.match(r'^#{1,3}\s*\[?\d+\.\d+', lines[j].strip()):
        end = j; break
body = "\n".join(lines[start:end if end else len(lines)]).rstrip()
body = re.sub(r'\n{3,}', '\n\n', body)
out.write_text(body + "\n", encoding="utf-8")
m = re.match(r'^#{1,3}\s*\[?' + re.escape(ver) + r'\]?\s*[—-]\s*\d{4}-\d{2}-\d{2}\s*[—-]\s*(.+?)\s*(\((MAJOR|MINOR|PATCH)\))?\s*$', head)
if m:
    print(m.group(1).strip()); sys.exit(0)
m = re.match(r'^#{1,3}\s*\[?' + re.escape(ver) + r'\]?\s*[—-]\s*(.+?)\s*(\((MAJOR|MINOR|PATCH)\))?\s*$', head)
if m:
    t = m.group(1).strip()
    if not re.match(r'^\d{4}-\d{2}-\d{2}$', t):
        print(t); sys.exit(0)
print(""); sys.exit(0)
PYEOF

find_changelog(){
  root="$1"; fv="$2"
  for c in "$root/CHANGELOG.md" "$root/docs/CHANGELOG.md" \
           "$root/00-infrastructure/CHANGELOG.md" "$root/CHANGELOG" "$root/Changelog.md"; do
    [ -f "$c" ] && LC_ALL=C grep -qE "^#+ *\[?$fv\]?( |$|—|-)" "$c" 2>/dev/null && { printf '%s' "$c"; return 0; }
  done
  found="$(find "$root" -maxdepth 4 -iname 'CHANGELOG*.md' \
            ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/_archive/*' \
            ! -iname '*TEMPLATE*' ! -iname '*repos-map*' 2>/dev/null)"
  for c in $found; do
    LC_ALL=C grep -qE "^#+ *\[?$fv\]?( |$|—|-)" "$c" 2>/dev/null && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# описание считается «плохим», если пустое, техническое или короче 120 символов
body_is_bad(){
  b="$1"
  [ -z "$b" ] && return 0
  printf '%s' "$b" | grep -qiE 'Синхронизация дерева|^Release [0-9]|^v?[0-9]+\.[0-9]+\.[0-9]+$' && return 0
  [ "$(printf '%s' "$b" | wc -c)" -lt 120 ] && return 0
  return 1
}

N_FIX=0; N_OK=0; N_SKIP=0; N_DEL=0; N_MANUAL=""
[ "$APPLY" = "1" ] || ylw "РЕЖИМ ПЛАНА: ничего не меняется. APPLY=1 — применить."
echo ""

for REPO in $REPOS; do
  [ -n "$ONLY" ] && { case " $ONLY " in *" $REPO "*) :;; *) continue;; esac; }
  [ -n "$SKIP" ] && { case " $SKIP " in *" $REPO "*) continue;; esac; }
  gh repo view "$OWNER/$REPO" >/dev/null 2>&1 || { dim "  $REPO — нет на GitHub, пропускаю"; continue; }

  bld "══ $REPO"
  CLONE="$WORK/$REPO"
  git clone -q "${GIT_BASE:-https://github.com/$OWNER}/$REPO.git" "$CLONE" 2>/dev/null || { red "  клон не удался"; continue; }

  TAGS="$(gh release list --repo "$OWNER/$REPO" --limit 500 2>/dev/null | awk '{print $1}' | grep -E '^v?[0-9]' | sed 's/^v//')"
  [ -n "$TAGS" ] || { dim "  релизов нет"; continue; }

  for V in $TAGS; do
    CUR_TITLE="$(gh release view "v$V" --repo "$OWNER/$REPO" --json name --jq '.name' 2>/dev/null)"
    CUR_BODY="$(gh release view "v$V" --repo "$OWNER/$REPO" --json body --jq '.body' 2>/dev/null)"

    CL="$(find_changelog "$CLONE" "$V" || true)"
    if [ -z "$CL" ]; then
      if body_is_bad "$CUR_BODY"; then
        HAS_ASSET="$(gh release view "v$V" --repo "$OWNER/$REPO" --json assets --jq '.assets|length' 2>/dev/null)"
        if [ "${HAS_ASSET:-0}" = "0" ]; then
          if [ "$DELETE_EMPTY" = "1" ] && [ "$APPLY" = "1" ]; then
            gh release delete "v$V" --repo "$OWNER/$REPO" --yes >/dev/null 2>&1 \
              && { red "  ✗ v$V — пустышка без секции и без ассета: УДАЛЁН"; N_DEL=$((N_DEL+1)); } \
              || red "  v$V — удалить не удалось"
          else
            red "  ! v$V — пустышка (нет секции в CHANGELOG, нет ассета). DELETE_EMPTY=1 чтобы удалить"
            N_MANUAL="$N_MANUAL
  $REPO v$V — релиз-пустышка"
          fi
          continue
        fi
      fi
      ylw "  ? v$V — секции нет в CHANGELOG, описание оставляю как есть"
      N_MANUAL="$N_MANUAL
  $REPO v$V — нет секции [$V] в CHANGELOG"
      continue
    fi

    OUT="$WORK/notes_$V.md"
    THESIS="$(python3 "$PARSER" "$CL" "$V" "$OUT" 2>/dev/null)" || THESIS=""
    [ -s "$OUT" ] || { ylw "  ? v$V — секция не разобралась"; continue; }

    if [ -n "$THESIS" ]; then WANT_TITLE="$REPO v$V — $THESIS"; else WANT_TITLE="$REPO v$V"; fi

    NEED=0
    [ "$CUR_TITLE" != "$WANT_TITLE" ] && NEED=1
    body_is_bad "$CUR_BODY" && NEED=1
    [ "$FORCE" = "1" ] && NEED=1

    if [ "$NEED" = "0" ]; then N_OK=$((N_OK+1)); continue; fi

    # осмысленное описание не трогаем без FORCE
    if ! body_is_bad "$CUR_BODY" && [ "$FORCE" != "1" ] && [ "$CUR_TITLE" = "$WANT_TITLE" ]; then
      N_SKIP=$((N_SKIP+1)); continue
    fi

    if [ "$APPLY" = "1" ]; then
      if gh release edit "v$V" --repo "$OWNER/$REPO" --title "$WANT_TITLE" --notes-file "$OUT" >/dev/null 2>&1; then
        grn "  ✓ v$V → $WANT_TITLE"; N_FIX=$((N_FIX+1))
      else
        red "  ✗ v$V — правка не удалась"
      fi
    else
      cyn "  → v$V станет: $WANT_TITLE"
      dim "     описание: $(head -c 90 "$OUT" | tr '\n' ' ')…"
      N_FIX=$((N_FIX+1))
    fi
  done
done

echo ""
bld "── Итог"
[ "$APPLY" = "1" ] && grn "  исправлено: $N_FIX" || cyn "  будет исправлено: $N_FIX"
[ "$N_DEL" -gt 0 ] && red "  удалено пустышек: $N_DEL"
dim "  уже по стандарту: $N_OK · осмысленные не тронуты: $N_SKIP"
if [ -n "$N_MANUAL" ]; then
  echo ""; printf '%s%s── ТРЕБУЕТ ТВОЕГО РЕШЕНИЯ%s\n' "$C_BLD" "$C_MAG" "$C_OFF"
  printf '%s\n' "$N_MANUAL" | sed '/^$/d'
  echo ""; ylw "  Добавь секции в CHANGELOG и прогони снова, либо удали пустышки с DELETE_EMPTY=1."
fi
[ "$APPLY" = "1" ] || { echo ""; ylw "Это был план. APPLY=1 чтобы применить."; }
