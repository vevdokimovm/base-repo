#!/usr/bin/env bash
# =============================================================================
# deploy.sh — ЕДИНЫЙ деплойер репозиториев. Один скрипт на всю систему.
#
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ ЖЕЛЕЗНОЕ ПРАВИЛО: ВТОРОГО СКРИПТА НЕ ЗАВОДИТСЯ. НИКОГДА.                   │
# │                                                                           │
# │ Понадобилась новая возможность — она становится РЕЖИМОМ (env-флагом)       │
# │ внутри этого файла, и на неё пишется тест в tests/test_deploy.sh.          │
# │ Не «быстренько отдельный скриптик рядом» — именно сюда.                    │
# │                                                                           │
# │ Почему это правило существует: восемь скриптов-предшественников появились  │
# │ ровно так — каждый раз казалось, что проще написать новый, чем разобраться │
# │ в старом. Итог: у каждой репы свой вариант деплоя, релизы в разных         │
# │ форматах, никто не помнит, что запускать. Разгребали это неделю.           │
# │                                                                           │
# │ Рецидив был уже ПОСЛЕ консолидации: для починки старых релизов завели      │
# │ отдельный fix_releases.sh — и тут же получили два скрипта вместо одного.   │
# │ Слит обратно режимом. Если рука тянется создать файл рядом — читай         │
# │ templates/README.md, там разобрано, почему это тупик.                      │
# └───────────────────────────────────────────────────────────────────────────┘
#
# Заменяет собой все прежние вариации (publish.sh, deploy_all.sh, deploy_from_zip.sh,
# deploy_all_versions.sh, commit_to_main.sh, commit_all_versions.sh, push_archives.sh,
# push_base_repo.sh, fix_releases.sh). Каждая из них умела свой кусок; здесь собран
# объединённый рабочий процесс + починка того, что прежние версии делали не по стандарту.
# Разбор консолидации: reports/merges/scripts_consolidation_report.md
#
# ЧТО ДЕЛАЕТ (полный цикл, идемпотентно):
#   находит все версионные архивы в папке -> группирует по репам -> сортирует по SemVer
#   -> создаёт репу, если её нет -> клонирует -> чисто заменяет дерево -> коммит -> тег
#   -> push -> GitHub Release с ЗАГОЛОВКОМ и ОПИСАНИЕМ по стандарту -> канонический ассет
#   -> чинит уже существующие релизы, сделанные не по стандарту -> обновляет repos-map.
#
# ЗАПУСК:
#   zsh deploy.sh                      # папка по умолчанию ~/Downloads
#   zsh deploy.sh ~/Desktop/archives   # другая папка
#   DRY=1 zsh deploy.sh                # ПЛАН без единого изменения (запускай первым!)
#
# ПЕРЕКЛЮЧАТЕЛИ (env):
#   DRY=1          показать план и выйти. Ничего не меняет ни локально, ни на GitHub
#   ONLY="a b"     обработать только эти репы
#   SKIP="a b"     не трогать эти репы вообще
#   REPAIR=1       ТОЛЬКО починка: пройтись по существующим тегам/релизам и привести
#                  к стандарту (заголовок, описание из CHANGELOG, недостающий ассет).
#                  Новые версии не публикуются. Осмысленные описания не перезаписываются
#   FORCE=1        разрешить перезапись ОСМЫСЛЕННЫХ описаний релизов (по умолчанию нет:
#                  тег и релиз заморожены, 21-revision-protocol)
#   ASSETS_ONLY=1  только дозалить недостающие канонические ассеты
#   BACKFILL=1     разрешить публикацию версий НИЖЕ старшего существующего тега
#   PRIVATE=0      создавать публичные репы (по умолчанию приватные)
#   ASSET=0        не прикладывать zip к релизу (боевой прогон так НЕ запускать: §4 стандарта)
#   OWNER=...      владелец (по умолчанию vevdokimovm)
#   BRANCH=...     ветка (по умолчанию main)
#   BASE_REPO=...  путь к клону base-repo для авто-обновления repos-map
#                  (по умолчанию ищется рядом: ./base-repo, ~/base-repo, ~/Documents/base-repo)
#
# ИМЕНА АРХИВОВ (понимает все три конвенции):
#   <repo>-vX_Y_Z.zip · <repo>_vX.Y.Z.zip · <repo>-vX.Y.Z.zip
#   Версия сверяется с файлом VERSION в дереве: расхождение -> версия пропускается.
#
# ЗАЩИТЫ (вшитые уроки, не трогать):
#   PIT-004 чистка-кроме-.git (чистая замена != долив) · PIT-006 git add -A -f ·
#   PIT-007 разворот wrapper-обёртки · маркеры корня ДО деструктива · автопроверка
#   «файлов в коммите == файлов в дереве» · ретраи под РФ-TLS · CHANGELOG парсится
#   ПИТОНОМ в --notes-file (пайп рвёт UTF-8 кириллицу) · сбой на одной версии НЕ роняет
#   батч · на падении рабочая папка сохраняется.
# =============================================================================

set -u
if [ -n "${ZSH_VERSION:-}" ]; then setopt shwordsplit 2>/dev/null || true; fi

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
DIR="${1:-${SELF_DIR:-$HOME/Downloads}}"
OWNER="${OWNER:-vevdokimovm}"
BRANCH="${BRANCH:-main}"
RETRIES="${RETRIES:-5}"; RETRY_SLEEP="${RETRY_SLEEP:-4}"
REMOTE_BASE="${REMOTE_BASE:-https://github.com/$OWNER}"   # переопределяется только для локальных тестов
MIN_FILES="${MIN_FILES:-5}"
PRIVATE="${PRIVATE:-1}"
ASSET="${ASSET:-1}"
DRY="${DRY:-0}"
REPAIR="${REPAIR:-0}"
FORCE="${FORCE:-0}"
ASSETS_ONLY="${ASSETS_ONLY:-0}"
BACKFILL="${BACKFILL:-0}"
# служебные архивы (загрузки из чата, системные) — молча мимо, репу для них не заводим
SERVICE_RE="${SERVICE_RE:-^([0-9]+|files([ _-][0-9]+)?|[Aa]rchive([ _-][0-9]+)?|Downloads?)$}"
# репы, у которых бывает вариантный постфикс в имени архива (finpilot_v6_20_1_intl)
VARIANT_REPOS="${VARIANT_REPOS:-finpilot}"
# имя архива != имя репы. Историческое: архивы finpilot_* принадлежат personal-finance-dss
# (finpilot — публичное зеркало). Формат: "имя-в-архиве=имя-репы имя2=репа2"
REPO_MAP="${REPO_MAP:-finpilot=personal-finance-dss}"

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
mag(){ printf '%s%s%s\n' "$C_MAG" "$*" "$C_OFF"; }
bld(){ printf '%s%s%s\n' "$C_BLD" "$*" "$C_OFF"; }
# fail loud: то, что скрипт чинить НЕ станет — человек решает сам
LOUD=""
loud(){ LOUD="$LOUD
  $1"; printf '%s%s  ТРЕБУЕТ РЕШЕНИЯ: %s%s\n' "$C_BLD" "$C_MAG" "$1" "$C_OFF"; }
die(){ red "ОШИБКА: $*"; [ -n "${WORK:-}" ] && [ -d "${WORK:-}" ] && red "Рабочая папка сохранена: $WORK"; exit 1; }

retry(){ d="$1"; shift; a=1; s="$RETRY_SLEEP"
  while [ "$a" -le "$RETRIES" ]; do "$@" && return 0
    ylw "  попытка $a/$RETRIES ($d) не удалась — жду ${s}s (обычно TLS-таймаут к GitHub)"
    sleep "$s"; a=$((a+1)); s=$((s*2)); done; return 1; }

# сводка прогона: строки «репа|версия|действие|статус»
SUMMARY=""
note(){ SUMMARY="$SUMMARY
$1"; }

# --- ШАГ 0. Preflight -----------------------------------------------------------
command -v git >/dev/null 2>&1 || die "git не найден"
command -v python3 >/dev/null 2>&1 || die "python3 не найден (нужен для разбора CHANGELOG)"
HAVE_GH=0; command -v gh >/dev/null 2>&1 && HAVE_GH=1
[ "$HAVE_GH" -eq 1 ] || ylw "⚠ gh не найден: пуш и теги пройдут, релизы придётся создать вручную"
[ -d "$DIR" ] || die "папка не найдена: $DIR"
[ "$ASSET" = "0" ] && ylw "⚠ ASSET=0 — релизы будут без канонического zip (нарушение §4 стандарта)"

# --- парсер CHANGELOG (питон: UTF-8, кириллица, тире) ---------------------------
PARSER="$(mktemp -d)/chlog.py"
cat > "$PARSER" <<'PYEOF'
"""Достаёт из CHANGELOG секцию версии: тело релиза + тезис для заголовка.

Понимает диалекты заголовков:
    ## [1.2.3] — 2026-07-22 — Тезис (MINOR)
    ## v1.2.3 — 2026-07-22 — Тезис
    ## [1.2.3] - 2026-07-22
Печатает тезис в stdout, тело пишет в файл. Пустой stdout = тезиса нет.
"""

import re
import sys
from pathlib import Path

changelog, version, out_path = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
vre = re.escape(version)
head_re = re.compile(r"^##\s+\[?v?" + vre + r"\]?(?![0-9])")
any_head_re = re.compile(r"^##\s+\[?v?\d+\.\d+\.\d+")

lines, body, started = changelog.read_text(encoding="utf-8").splitlines(), [], False
heading = ""
for line in lines:
    if not started and head_re.match(line):
        started, heading = True, line
        continue
    if started and any_head_re.match(line):
        break
    if started:
        body.append(line)

if not started:
    sys.exit(3)

tail = re.sub(r"^##\s+", "", heading)
tail = re.sub(r"^\[?v?\d+\.\d+\.\d+\]?\s*", "", tail)
tail = re.sub(r"^[—\-–]\s*", "", tail)
tail = re.sub(r"^\d{4}-\d{2}-\d{2}\s*", "", tail)
tail = re.sub(r"^[—\-–]\s*", "", tail)
bump = re.search(r"\((MAJOR|MINOR|PATCH)\)\s*$", tail)
thesis = re.sub(r"\s*\((MAJOR|MINOR|PATCH)\)\s*$", "", tail).strip()

text = "\n".join(body).strip("\n")
while text.startswith("---"):
    text = text.split("\n", 1)[1].lstrip("\n") if "\n" in text else ""
out_path.write_text((heading + "\n\n" + text).strip() + "\n", encoding="utf-8")

print(thesis)
if not bump:
    print("NOBUMP", file=sys.stderr)
if not thesis:
    print("NOTHESIS", file=sys.stderr)
PYEOF

# --- ШАГ 1. Инвентаризация архивов ----------------------------------------------
bld "── Шаг 1. Ищу версионные архивы в $DIR"
INDEX="$(mktemp)"
NONCANON=""; DUPES=""; VARIANTS=""; MAPPED=""; UNKNOWN=""; N_SERVICE=0
for z in "$DIR"/*.zip; do
  [ -f "$z" ] || continue
  base="$(basename "$z" .zip)"

  # (A) служебные архивы из чата (files 3.zip, 16.zip) — не наши артефакты, молча мимо
  if printf '%s' "$base" | LC_ALL=C grep -qE "$SERVICE_RE"; then
    N_SERVICE=$((N_SERVICE+1)); continue
  fi
  if [ -n "${IGNORE:-}" ] && printf '%s' "$base" | LC_ALL=C grep -qE "$IGNORE"; then
    N_SERVICE=$((N_SERVICE+1)); continue
  fi

  # (B) рабочие копии и дубликаты — НИКОГДА не публикуем: это дубль, а не поставка
  if printf '%s' "$base" | LC_ALL=C grep -qiE '(^|[^a-zA-Z])copy([^a-zA-Z]|$)|\([0-9]+\)$|[0-9]+[._-][0-9]+[._-][0-9]+ [0-9]+$'; then
    DUPES="$DUPES
  $base.zip"; continue
  fi
  # macOS/браузер лепят хвосты: " copy", "-copy", "__copy_", " (1)", "(2)". Срезаем их,
  # иначе валидный архив просто не находится и человек думает, что скрипт сломан.
  clean="$(printf '%s' "$base" | sed -E 's/([ _-]*[Cc]opy[ _-]*)+$//; s/[ _-]*\([0-9]+\)$//; s/[ _-]+$//')"
  # ИСТОРИЧЕСКИЙ НЕЙМИНГ (§43): принимаем всё, что реально встречалось, чтобы старые архивы
  # не выпадали из системы. Разделитель имя↔версия: - _ . или пробел; префикс v необязателен;
  # разделитель внутри версии: . _ или -. Канон при этом один — точки, о нём говорим ниже.
  parsed="$(printf '%s' "$clean" | sed -nE 's/^(.+)[-_. ]v?([0-9]+)[._-]([0-9]+)[._-]([0-9]+)$/\1 \2.\3.\4/p')"
  if [ -z "$parsed" ]; then
    # двухчастная версия (v1.2) — тоже историческая ошибка: достраиваем до X.Y.0
    two="$(printf '%s' "$clean" | sed -nE 's/^(.+)[-_. ]v?([0-9]+)[._-]([0-9]+)$/\1 \2.\3.0/p')"
    if [ -n "$two" ]; then
      parsed="$two"
      ylw "  ! $base.zip — версия из двух частей, читаю как ${two#* } (§43: всегда X.Y.Z)"
    fi
  fi
  # вариантный постфикс (finpilot_v6_20_1_intl): срезаем ТОЛЬКО для реп из VARIANT_REPOS,
  # чтобы случайно не откусить кусок имени у чужой репы
  if [ -z "$parsed" ]; then
    vclean="$(printf '%s' "$clean" | sed -E 's/[-_](intl|international|ru|en)$//')"
    if [ "$vclean" != "$clean" ]; then
      vparsed="$(printf '%s' "$vclean" | sed -nE 's/^(.+)[-_. ]v?([0-9]+)[._-]([0-9]+)[._-]([0-9]+)$/\1 \2.\3.\4/p')"
      vname="$(printf '%s' "${vparsed%% *}" | sed -E 's/[-_. ]+$//')"
      for vr in $VARIANT_REPOS; do
        if [ -n "$vparsed" ] && [ "$vname" = "$vr" ]; then
          parsed="$vparsed"
          VARIANTS="$VARIANTS
  $base.zip → $vr v${vparsed#* }"
          break
        fi
      done
    fi
  fi
  if [ -z "$parsed" ]; then
    if printf '%s' "$base" | LC_ALL=C grep -qE '[0-9]+[._-][0-9]+'; then
      ylw "  ? $base.zip — похоже на версию, но не читается. Канон: <repo>-vX.Y.Z.zip"
    else
      UNKNOWN="$UNKNOWN
  $base.zip"
    fi
    continue
  fi
  name="${parsed%% *}"; ver="${parsed#* }"
  name="$(printf '%s' "$name" | sed -E 's/[-_. ]+$//')"
  # переименование по карте: архив едет в ту репу, которой принадлежит
  for _m in $REPO_MAP; do
    case "$_m" in
      "$name="*) _t="${_m#*=}"
        [ "$_t" != "$name" ] && MAPPED="$MAPPED
  $base.zip → репозиторий $_t (архив назван $name)"
        name="$_t";;
    esac
  done

  # ПРЕДПОЛЁТНАЯ ПРОВЕРКА (дёшево — по списку файлов, без распаковки).
  # Делается ДО создания репы: иначе битый архив успевал породить на GitHub пустую
  # репу-сироту, которую потом руками удалять. Поймано тестом 21.
  if ! unzip -l "$z" >/dev/null 2>&1; then
    red "  ✗ $base.zip — битый архив (не читается), пропускаю"; continue
  fi
  # LC_ALL=C: имена внутри архивов бывают не в UTF-8 (кириллица в CP1251, macOS-NFD).
  # BSD-шные cut/grep под UTF-8 локалью на таких байтах падают с Illegal byte sequence.
  _ent="$(unzip -Z1 "$z" 2>/dev/null | LC_ALL=C grep -v '/$' | LC_ALL=C grep -vE '(^|/)__MACOSX/|(^|/)\.DS_Store$|(^|/)\._')"
  _nf="$(printf '%s\n' "$_ent" | LC_ALL=C grep -c .)"
  if [ "$_nf" -lt "$MIN_FILES" ]; then
    red "  ✗ $base.zip — файлов $_nf (< $MIN_FILES), не похоже на репу — пропускаю"; continue
  fi
  if ! printf '%s\n' "$_ent" | LC_ALL=C grep -qE '(^|/)README\.md$'; then
    red "  ✗ $base.zip — корень не опознан (нет README.md) — пропускаю"; continue
  fi
  # VERSION берём СТРОГО корневой. Глоб '*/VERSION' ловил ещё и вложенные репы
  # (base-repo внутри dota-dossier) и склеивал их содержимое: "1.13.0"+"2.13.0".
  _roots="$(printf '%s\n' "$_ent" | LC_ALL=C cut -d/ -f1 | LC_ALL=C sort -u | LC_ALL=C grep -c .)"
  if [ "$_roots" = "1" ]; then
    _wrap="$(printf '%s\n' "$_ent" | LC_ALL=C cut -d/ -f1 | LC_ALL=C sort -u)"
    _vf="$(unzip -p "$z" "$_wrap/VERSION" 2>/dev/null | head -c 32 | tr -d ' \n\r')"
  else
    _vf="$(unzip -p "$z" 'VERSION' 2>/dev/null | head -c 32 | tr -d ' \n\r')"
  fi
  if [ -n "$_vf" ] && [ "$_vf" != "$ver" ]; then
    red "  ✗ $base.zip — VERSION в дереве = $_vf, а архив v$ver — пропускаю"; continue
  fi
  # §НЕЙМИНГ: канон — точки. Подчёркивания принимаем (легаси), но говорим об этом вслух.
  [ "$clean" = "$name-v$ver" ] || NONCANON="$NONCANON
  $base.zip → канон: $name-v$ver.zip"
  skip=0
  for s in ${SKIP:-}; do [ "$name" = "$s" ] && skip=1; done
  [ "$skip" = "1" ] && continue
  if [ -n "${ONLY:-}" ]; then
    keep=0; for o in $ONLY; do [ "$name" = "$o" ] && keep=1; done
    [ "$keep" = "1" ] || continue
  fi
  printf '%s\t%s\t%s\n' "$name" "$ver" "$z" >> "$INDEX"
done
[ "$N_SERVICE" -gt 0 ] && dim "  пропущено служебных архивов: $N_SERVICE (загрузки из чата, не наши артефакты)"
if [ -n "$DUPES" ]; then
  echo ""; ylw "  рабочие копии и дубликаты — НЕ публикую (переименуй, если это поставка):"
  printf '%s\n' "$DUPES" | sed '/^$/d'
fi
if [ -n "$VARIANTS" ]; then
  echo ""; cyn "  вариантные имена (постфикс отброшен, версия взята как есть):"
  printf '%s\n' "$VARIANTS" | sed '/^$/d'
fi
if [ -n "$MAPPED" ]; then
  echo ""; cyn "  переименование по REPO_MAP (архив едет в другую репу):"
  printf '%s\n' "$MAPPED" | sed '/^$/d'
fi
if [ -n "$UNKNOWN" ]; then
  echo ""; dim "  не версионные архивы — не трогаю (для полноты картины):"
  printf '%s\n' "$UNKNOWN" | sed '/^$/d' | while IFS= read -r _u; do dim "$_u"; done
fi

if [ ! -s "$INDEX" ]; then
  echo ""
  if [ -n "$DUPES" ] || [ "$N_SERVICE" -gt 0 ]; then
    die "версионных архивов к публикации нет — всё найденное отброшено как копии/служебное (см. выше)"
  fi
  die "версионных архивов не найдено (жду <repo>-vX.Y.Z.zip; принимаются и легаси-имена)"
fi

REPOLIST="$(mktemp)"
cut -f1 "$INDEX" | sort -u > "$REPOLIST"
while IFS= read -r r; do
  [ -n "$r" ] || continue
  n="$(awk -F'\t' -v r="$r" '$1==r' "$INDEX" | wc -l | tr -d ' ')"
  vers="$(awk -F'\t' -v r="$r" '$1==r{print $2}' "$INDEX" | sort -t. -k1,1n -k2,2n -k3,3n | tr '\n' ' ')"
  grn "  $r — версий: $n → $vers"
done < "$REPOLIST"
[ -n "${SKIP:-}" ] && ylw "  пропускаются по SKIP: $SKIP"
if [ -n "$NONCANON" ]; then
  echo ""; ylw "  имена не по стандарту (обработаю, но переименуй у себя — канон это ТОЧКИ):"
  printf '%s\n' "$NONCANON" | sed '/^$/d'
fi
[ "$REPAIR" = "1" ] && cyn "  режим REPAIR: только приведение существующих релизов к стандарту"

if [ "$DRY" = "1" ]; then
  ylw ""; ylw "DRY=1 — это только план, ничего не изменено. Убери DRY, чтобы выполнить."
  rm -f "$INDEX" "$REPOLIST" "$PARSER"; exit 0
fi

WORK="$HOME/Downloads/repo_deploy_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WORK" || die "mkdir $WORK"
NEW_REPOS=""

# --- поиск CHANGELOG где угодно в дереве ----------------------------------------
# Канон — корень репы (§46), но исторически файл живёт и в docs/, и в
# 00-infrastructure/, и глубже. Ищем везде и выбираем тот, где ЕСТЬ секция версии:
# наличие секции — единственный надёжный признак «это наш журнал».
# find_changelog <корень> <версия> -> путь или пусто
find_changelog(){
  _root="$1"; _fv="$2"
  # 1) приоритетные места по порядку
  for _c in "$_root/CHANGELOG.md" "$_root/docs/CHANGELOG.md" \
            "$_root/00-infrastructure/CHANGELOG.md" "$_root/CHANGELOG" "$_root/Changelog.md"; do
    [ -f "$_c" ] && LC_ALL=C grep -qE "^#+ *\\[?$_fv\\]?( |\$|—|-)" "$_c" 2>/dev/null && { printf '%s' "$_c"; return 0; }
  done
  # 2) поиск по всему дереву — сначала тот, где есть секция версии
  _found="$(find "$_root" -maxdepth 4 -iname 'CHANGELOG*.md' \
              ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/_archive/*' \
              ! -iname '*TEMPLATE*' ! -iname '*repos-map*' 2>/dev/null)"
  for _c in $_found; do
    LC_ALL=C grep -qE "^#+ *\\[?$_fv\\]?( |\$|—|-)" "$_c" 2>/dev/null && { printf '%s' "$_c"; return 0; }
  done
  # 3) секции нет нигде — вернём хоть какой-то журнал (приоритет корню)
  for _c in "$_root/CHANGELOG.md" "$_root/docs/CHANGELOG.md" "$_root/00-infrastructure/CHANGELOG.md"; do
    [ -f "$_c" ] && { printf '%s' "$_c"; return 0; }
  done
  for _c in $_found; do [ -f "$_c" ] && { printf '%s' "$_c"; return 0; }; done
  return 1
}

# --- вспомогательное: заголовок + описание релиза по стандарту -------------------
# build_notes <корень-дерева> <ver> <repo> <out.md>  -> печатает заголовок релиза
build_notes(){
  _clroot="$1"; _v="$2"; _r="$3"; _out="$4"
  _thesis=""
  # принимаем и готовый путь к файлу, и корень дерева
  if [ -f "$_clroot" ]; then _cl="$_clroot"; else _cl="$(find_changelog "$_clroot" "$_v" || true)"; fi
  CL_USED="$_cl"
  if [ -n "$_cl" ] && [ -f "$_cl" ]; then
    case "$_cl" in "$_clroot/CHANGELOG.md") : ;; *) dim "    CHANGELOG: ${_cl#$_clroot/}" >&2 ;; esac
    _thesis="$(python3 "$PARSER" "$_cl" "$_v" "$_out" 2>"$WORK/parse_err.txt")"
    if [ $? -ne 0 ]; then
      ylw "    CHANGELOG: секции [$_v] нет — описание будет техническим" >&2
      note "$_r|v$_v|описание|⚠ нет секции в CHANGELOG"
      _thesis=""
    else
      grep -q NOBUMP   "$WORK/parse_err.txt" 2>/dev/null && \
        { ylw "    CHANGELOG: в заголовке нет (MAJOR/MINOR/PATCH) — §2 стандарта" >&2; note "$_r|v$_v|формат|⚠ нет BUMP-маркера"; }
      grep -q NOTHESIS "$WORK/parse_err.txt" 2>/dev/null && \
        { ylw "    CHANGELOG: в заголовке нет тезиса — §2 стандарта" >&2; note "$_r|v$_v|формат|⚠ нет тезиса"; }
    fi
  else
    red "    ✗ CHANGELOG не найден нигде в дереве" >&2
    note "$_r|v$_v|описание|✗ CHANGELOG не найден"
    loud "$_r v$_v: CHANGELOG не найден — релиз без описания НЕ создаю"
    printf '' > "$_out"; return 1
  fi
  if [ ! -s "$_out" ]; then
    red "    ✗ в CHANGELOG нет секции [$_v] — релиз без описания не создаю" >&2
    loud "$_r v$_v: в CHANGELOG нет секции — добавь её и перезапусти с REPAIR=1"
    return 1
  fi
  if [ -n "$_thesis" ]; then printf '%s v%s — %s\n' "$_r" "$_v" "$_thesis"
  else printf '%s v%s\n' "$_r" "$_v"; fi
}

# release_is_stub <repo> <ver> -> 0 если описание пустое/заглушка (можно перезаписать)
release_is_stub(){
  _body="$(gh release view "v$2" --repo "$OWNER/$1" --json body --jq '.body' 2>/dev/null)"
  [ -z "$_body" ] && return 0
  printf '%s' "$_body" | grep -qE '^(Release |Синхронизация дерева)' && return 0
  [ "$(printf '%s' "$_body" | wc -c | tr -d ' ')" -lt 40 ] && return 0
  return 1
}

# ensure_release <repo> <ver> <notes.md> <title> <zip|"">
ensure_release(){
  _r="$1"; _v="$2"; _n="$3"; _t="$4"; _z="${5:-}"; _cl="${6:-}"
  [ "$HAVE_GH" -eq 1 ] || { ylw "    gh нет — релиз v$_v вручную"; return 0; }
  _aname="$_r-v$_v.zip"
  _top="$(git tag -l 'v*' 2>/dev/null | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  _lat="--latest=false"; [ -z "$_top" ] || [ "$_v" = "$_top" ] && _lat="--latest=true"

  if gh release view "v$_v" --repo "$OWNER/$_r" >/dev/null 2>&1; then
    # ---- АУДИТ существующего релиза (идёт всегда, а не по флагу) ----------------
    _ct="$(gh release view "v$_v" --repo "$OWNER/$_r" --json name --jq '.name' 2>/dev/null)"
    _cb="$(gh release view "v$_v" --repo "$OWNER/$_r" --json body --jq '.body' 2>/dev/null)"
    _fixt=0; _fixb=0
    [ -n "$_t" ] || _t="$_ct"                       # нет эталона — сохраняем текущий
    # заголовок: чиним, если расходится с эталоном из CHANGELOG
    [ -n "$_t" ] && [ "$_ct" != "$_t" ] && _fixt=1
    # тело: чиним заглушки; осмысленное, но расходящееся — только с FORCE
    if release_is_stub "$_r" "$_v"; then _fixb=1
    elif [ "$FORCE" = "1" ]; then _fixb=1
    elif [ -s "$_n" ] && [ -n "$_cb" ]; then
      if [ "$(printf '%s' "$_cb" | tr -d ' \n\r')" != "$(cat "$_n" | tr -d ' \n\r')" ]; then
        ylw "    ~ v$_v: описание отличается от CHANGELOG — не трогаю (FORCE=1 чтобы синхронизировать)"
        note "$_r|v$_v|описание|~ расходится с CHANGELOG"
      fi
    fi
    if [ "$_fixt" = "1" ] || [ "$_fixb" = "1" ]; then
      if [ "$_fixb" = "1" ]; then
        # пустой заголовок НИКОГДА не отправляем — затрёт существующий
        _targ=""; [ -n "$_t" ] && _targ="--title"
        gh release edit "v$_v" --repo "$OWNER/$_r" ${_targ:+$_targ "$_t"} --notes-file "$_n" >/dev/null 2>&1 \
          && { grn "    ✓ v$_v: заголовок и описание по стандарту"; note "$_r|v$_v|релиз|починен"; } \
          || { red "    ✗ v$_v: не удалось обновить"; note "$_r|v$_v|релиз|✗ ошибка"; }
      else
        gh release edit "v$_v" --repo "$OWNER/$_r" --title "$_t" >/dev/null 2>&1 \
          && { grn "    ✓ v$_v: заголовок → $_t"; note "$_r|v$_v|заголовок|починен"; } \
          || { red "    ✗ v$_v: заголовок не обновлён"; note "$_r|v$_v|заголовок|✗ ошибка"; }
      fi
    fi
  else
    if [ "$ASSET" = "1" ] && [ -n "$_z" ]; then
      cp "$_z" "$WORK/$_aname"
      gh release create "v$_v" "$WORK/$_aname" --repo "$OWNER/$_r" --title "$_t" --notes-file "$_n" $_lat >/dev/null 2>&1 \
        && { grn "    ✓ релиз v$_v (+ассет $_aname)"; note "$_r|v$_v|релиз|создан"; } \
        || { red "    ✗ релиз v$_v не создан"; note "$_r|v$_v|релиз|✗ ошибка"; }
      rm -f "$WORK/$_aname"; return 0
    fi
    gh release create "v$_v" --repo "$OWNER/$_r" --title "$_t" --notes-file "$_n" $_lat >/dev/null 2>&1 \
      && { grn "    ✓ релиз v$_v"; note "$_r|v$_v|релиз|создан"; } \
      || { red "    ✗ релиз v$_v не создан"; note "$_r|v$_v|релиз|✗ ошибка"; }
  fi

  # ---- канонический ассет (§4: ровно 3 ассета) ---------------------------------
  if [ "$ASSET" = "1" ]; then
    if ! gh release view "v$_v" --repo "$OWNER/$_r" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx "$_aname"; then
      _src=""
      if [ -n "$_z" ] && [ -f "$_z" ]; then
        cp "$_z" "$WORK/$_aname"; _src="архив"
      elif [ -n "$_cl" ] && git -C "$_cl" rev-parse "v$_v" >/dev/null 2>&1; then
        # Архива под рукой нет (старая версия) — собираем канонический zip из тега.
        # Содержимое то же дерево, обёртка по §43.
        git -C "$_cl" archive --format=zip --prefix="$_r-v$_v/" "v$_v" -o "$WORK/$_aname" 2>/dev/null && _src="тег"
      fi
      if [ -n "$_src" ] && [ -f "$WORK/$_aname" ]; then
        gh release upload "v$_v" "$WORK/$_aname" --repo "$OWNER/$_r" --clobber >/dev/null 2>&1 \
          && { grn "    ✓ v$_v: ассет $_aname догружен (из: $_src)"; note "$_r|v$_v|ассет|догружен ($_src)"; } \
          || { red "    ✗ v$_v: ассет не загрузился"; note "$_r|v$_v|ассет|✗ ошибка"; }
        rm -f "$WORK/$_aname"
      fi
    fi
  fi
}

# --- ШАГ 2. Обработка каждой репы ------------------------------------------------
while IFS= read -r REPO; do
  [ -n "$REPO" ] || continue
  echo ""; bld "══ Репозиторий: $REPO"
  URL="$REMOTE_BASE/$REPO.git"
  IS_NEW=0

  if [ "$HAVE_GH" -eq 1 ] && ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
    VIS="--private"; [ "$PRIVATE" = "0" ] && VIS="--public"
    ylw "→ репозитория нет, создаю ($VIS)"
    gh repo create "$OWNER/$REPO" $VIS --description "$REPO" >/dev/null \
      || { red "не удалось создать $OWNER/$REPO — пропускаю репу"; note "$REPO|—|репа|✗ не создана"; continue; }
    grn "✓ репозиторий создан"; IS_NEW=1; NEW_REPOS="$NEW_REPOS $REPO"
    note "$REPO|—|репа|СОЗДАНА (новая)"
  fi

  CLONE="$WORK/$REPO"
  ylw "→ клонирую"
  # Одна быстрая попытка. Ретраить с backoff имеет смысл только если репа ТОЧНО есть
  # (тогда сбой = сетевой таймаут). Если репы нет — ретраи это просто минута впустую.
  if ! git clone "$URL" "$CLONE" 2>/dev/null; then
    REPO_EXISTS=0
    [ "$HAVE_GH" -eq 1 ] && gh repo view "$OWNER/$REPO" >/dev/null 2>&1 && REPO_EXISTS=1
    if [ "$REPO_EXISTS" = "1" ]; then
      ylw "  репа существует — похоже на сетевой сбой, повторяю"
      retry "git clone" git clone "$URL" "$CLONE" 2>/dev/null \
        || { red "  клон не удался — пропускаю репу"; note "$REPO|—|клон|✗ сеть"; continue; }
    else
      ylw "  репы нет / пустая — инициализирую локально"
      mkdir -p "$CLONE" && cd "$CLONE" || { red "mkdir клона"; continue; }
      git init -q -b "$BRANCH"; git remote add origin "$URL"
    fi
  fi
  cd "$CLONE" || continue
  git checkout -B "$BRANCH" >/dev/null 2>&1 || true
  git config user.name  >/dev/null 2>&1 || git config user.name  "$OWNER"
  git config user.email >/dev/null 2>&1 || git config user.email "$OWNER@users.noreply.github.com"

  TAGS="$(git tag -l 2>/dev/null | tr '\n' ' ')"

  # АУДИТ ДЕРЕВА (fail loud). Класс ошибки, который скрипт чинить НЕ будет: тег стоит,
  # но дерево под ним от другой версии (наследие старых скриптов / PIT-014). Переписать
  # это = переписать историю опубликованного тега — решение только человека.
  for _t in $TAGS; do
    _tv="${_t#v}"
    case "$_tv" in ''|*[!0-9.]*) continue;; esac
    _tf="$(git show "$_t:VERSION" 2>/dev/null | tr -d ' \n')"
    [ -n "$_tf" ] || continue
    if [ "$_tf" != "$_tv" ]; then
      loud "$REPO: тег $_t указывает на дерево с VERSION=$_tf — история тега битая, авто-чинить не буду"
      note "$REPO|$_t|дерево|✗ тег≠дерево (нужно решение)"
    fi
  done
  HIGHEST="$(git tag -l 'v*' 2>/dev/null | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [ -n "$HIGHEST" ] && ylw "  старший тег: v$HIGHEST"
  NOTES_DIR="$WORK/notes_$REPO"; mkdir -p "$NOTES_DIR"
  PUBLISHED=""

  # --- 2A. РЕЖИМ REPAIR / ASSETS_ONLY: чиним существующее, новое не публикуем ----
  if [ "$REPAIR" = "1" ] || [ "$ASSETS_ONLY" = "1" ]; then
    for TAG in $TAGS; do
      V="${TAG#v}"
      case "$V" in ''|*[!0-9.]*) continue;; esac
      Z="$(awk -F'\t' -v r="$REPO" -v v="$V" '$1==r && $2==v{print $3; exit}' "$INDEX")"
      TITLE="$(build_notes "$CLONE" "$V" "$REPO" "$NOTES_DIR/v$V.md")"
      ylw "  → $TAG: $TITLE"
      ensure_release "$REPO" "$V" "$NOTES_DIR/v$V.md" "$TITLE" "$Z"
    done
    continue
  fi

  # --- 2B. Публикация версий по возрастанию -------------------------------------
  VERLIST="$WORK/vers_$REPO.txt"
  awk -F'\t' -v r="$REPO" '$1==r{print $2}' "$INDEX" | sort -t. -k1,1n -k2,2n -k3,3n > "$VERLIST"
  while IFS= read -r VER; do
    [ -n "$VER" ] || continue
    ZIP="$(awk -F'\t' -v r="$REPO" -v v="$VER" '$1==r && $2==v{print $3; exit}' "$INDEX")"
    case " $TAGS " in *" v$VER "*) ylw "→ v$VER: тег есть, пропускаю"; continue;; esac
    if [ -n "$HIGHEST" ] && [ "$BACKFILL" != "1" ]; then
      NEWEST="$(printf '%s\n%s\n' "$HIGHEST" "$VER" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
      if [ "$NEWEST" != "$VER" ]; then
        ylw "→ v$VER: ниже v$HIGHEST — пропускаю (BACKFILL=1 чтобы залить)"; continue
      fi
    fi

    echo ""; ylw "→ v$VER  ($(basename "$ZIP"))"
    SRCDIR="$WORK/unpack_${REPO}_$VER"; rm -rf "$SRCDIR"; mkdir -p "$SRCDIR"
    unzip -oq "$ZIP" -d "$SRCDIR" </dev/null || { red "  unzip не удался — пропускаю"; note "$REPO|v$VER|распаковка|✗ битый архив"; continue; }

    # PIT-015 (главная причина «архив не пушится»): macOS кладёт рядом с обёрткой
    # __MACOSX/ и .DS_Store. Тогда в корне НЕ один объект, разворот обёртки не срабатывает,
    # и в репу уезжает дерево, вложенное в папку-обёртку. Поэтому мусор сносим СНАЧАЛА.
    find "$SRCDIR" -name '__MACOSX' -type d -exec rm -rf {} + 2>/dev/null || true
    find "$SRCDIR" -name '.DS_Store' -delete 2>/dev/null || true
    find "$SRCDIR" -name '._*' -delete 2>/dev/null || true

    SRC="$SRCDIR"                                            # PIT-007: разворот обёртки
    _depth=0
    while [ ! -f "$SRC/README.md" ] && [ "$_depth" -lt 3 ]; do
      n_all=$(ls -A "$SRC" | wc -l | tr -d ' ')
      n_dir=$(find "$SRC" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
      [ "$n_all" = "1" ] && [ "$n_dir" = "1" ] || break
      SRC="$SRC/$(ls -A "$SRC")"; _depth=$((_depth+1))
    done
    [ "$_depth" -gt 0 ] && dim "  обёртка развёрнута (уровней: $_depth)"

    # маркеры корня — ДО любого деструктива
    if [ ! -f "$SRC/README.md" ]; then
      red "  корень не опознан (нет README.md) — пропускаю"; note "$REPO|v$VER|проверка|✗ нет README"; continue
    fi
    SRC_N=$(find "$SRC" -type f | wc -l | tr -d ' ')
    if [ "$SRC_N" -lt "$MIN_FILES" ]; then
      red "  файлов $SRC_N (< $MIN_FILES) — не похоже на репу, пропускаю"; note "$REPO|v$VER|проверка|✗ мало файлов"; continue
    fi
    if [ -f "$SRC/VERSION" ]; then
      VF="$(tr -d ' \n' < "$SRC/VERSION")"
      if [ "$VF" != "$VER" ]; then
        red "  VERSION в дереве = $VF, а архив v$VER — пропускаю"; note "$REPO|v$VER|проверка|✗ VERSION≠имени"; continue
      fi
    fi

    TITLE="$(build_notes "$SRC" "$VER" "$REPO" "$NOTES_DIR/v$VER.md")"
    cyn "  заголовок релиза: $TITLE"

    find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +   # PIT-004
    cp -a "$SRC/." .
    find . -name '.DS_Store' -delete 2>/dev/null || true
    find . -name '__MACOSX' -type d -exec rm -rf {} + 2>/dev/null || true

    # PIT-014: cp -a сохраняет mtime архива. У архивов одной серии mtime совпадает,
    # а VERSION ещё и одного размера — git по паре size+mtime решает «файл не менялся»
    # и НЕ хэширует содержимое. Итог: дерево новое, индекс пуст, тег висит на старом
    # дереве. Поэтому индекс пересобираем принудительно, а не доверяем stat-кэшу.
    git rm -r --cached -q . >/dev/null 2>&1 || true
    git add -A -f                                                        # PIT-006
    if git diff --cached --quiet && [ -n "$(git tag -l)" ]; then
      ylw "  дерево не изменилось — ставлю только тег"
    else
      git commit -q -m "release: v$VER — $REPO tree sync" || { red "  commit не удался"; continue; }
      TREE_N=$(find . -path ./.git -prune -o -type f -print | wc -l | tr -d ' ')
      GIT_N=$(git ls-tree -r --name-only HEAD | wc -l | tr -d ' ')
      if [ "$GIT_N" != "$TREE_N" ]; then
        red "  в коммите $GIT_N файлов, в дереве $TREE_N (PIT-006/007) — стоп по этой репе"
        note "$REPO|v$VER|коммит|✗ расхождение файлов"; break
      fi
      grn "  ✓ коммит: $GIT_N файлов"
    fi
    git tag -a "v$VER" -m "$TITLE" || { red "  tag не удался"; continue; }
    PUBLISHED="$PUBLISHED $VER"
    note "$REPO|v$VER|дерево|закоммичено+тег"
    rm -rf "$SRCDIR"
  done < "$VERLIST"

  # --- 2C. Push. Даже если релизы упадут — дерево и теги уже на месте ------------
  if [ -n "$PUBLISHED" ]; then
    echo ""; ylw "→ пушу ветку и теги"
    pushb(){ git push -u origin "$BRANCH"; }
    pusht(){ git push origin --tags; }
    if retry "git push branch" pushb && retry "git push tags" pusht; then
      grn "✓ запушено"
    else
      red "✗ push не удался (проверь токен/сеть) — репа пропущена, локальная работа в $WORK"
      note "$REPO|—|push|✗ не удался"; continue
    fi
  else
    ylw "→ новых версий нет"
  fi

  # --- 2D. Релизы: и на новые версии, и починка старых (главный прежний баг) -----
  if [ "$HAVE_GH" -eq 1 ]; then
    echo ""; ylw "→ релизы"
    ALLTAGS="$(git tag -l 'v*' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tr '\n' ' ')"
    NOREL=""
    for V in $ALLTAGS; do
      Z="$(awk -F'\t' -v r="$REPO" -v v="$V" '$1==r && $2==v{print $3; exit}' "$INDEX")"
      if ! gh release view "v$V" --repo "$OWNER/$REPO" >/dev/null 2>&1; then
        if [ ! -s "$NOTES_DIR/v$V.md" ]; then
          TITLE="$(build_notes "$CLONE" "$V" "$REPO" "$NOTES_DIR/v$V.md")" || { NOREL="$NOREL v$V"; continue; }
        fi
        [ -s "$NOTES_DIR/v$V.md" ] || { NOREL="$NOREL v$V"; continue; }
        [ -n "${TITLE:-}" ] || TITLE="$REPO v$V"
        ensure_release "$REPO" "$V" "$NOTES_DIR/v$V.md" "$TITLE" "$Z" "$CLONE"
      else
        # Существующий релиз проверяется ВСЕГДА: сверка с CHANGELOG, заголовок, ассет.
        # Ничего не ломаем — правится только то, что расходится со стандартом.
        if T2="$(build_notes "$CLONE" "$V" "$REPO" "$NOTES_DIR/v$V.md" 2>/dev/null)"; then
          ensure_release "$REPO" "$V" "$NOTES_DIR/v$V.md" "$T2" "$Z" "$CLONE"
        else
          # секции нет — описание не трогаем, но ассет доложить обязаны
          ensure_release "$REPO" "$V" "$NOTES_DIR/v$V.md" "" "$Z" "$CLONE"
        fi
      fi
    done
    [ -n "$NOREL" ] && ylw "  без релиза (нет секции в CHANGELOG):$NOREL"
  fi
  grn "ГОТОВО: $REPO —$([ -n "$PUBLISHED" ] && echo "$PUBLISHED" || echo ' актуальна')"
done < "$REPOLIST"

# --- ШАГ 3. repos-map: регистрируем новые репы ------------------------------------
if [ -n "$NEW_REPOS" ]; then
  echo ""; bld "── Шаг 3. Новые репы → repos-map"
  MAP=""
  # ВАЖНО: только ПОСТОЯННЫЕ клоны. $WORK/base-repo сюда не годится — он удаляется
  # в конце прогона, и правка карты исчезнет вместе с ним (баг, пойманный на боевом тесте).
  for cand in "${BASE_REPO:-}" "$DIR/base-repo" "./base-repo" "$HOME/base-repo" \
              "$HOME/Documents/base-repo" "$HOME/Documents/GitHub/base-repo"; do
    [ -n "$cand" ] && [ -f "$cand/repos-map.md" ] && { MAP="$(cd "$cand" && pwd)"; break; }
  done
  case "$MAP" in "$WORK"*) MAP="";; esac
  TODAY="$(date +%Y-%m-%d)"

  # Локального клона нет — берём base-repo с GitHub сами. Пользователь не должен
  # ничего задавать руками: одна команда должна делать всё до конца.
  MAP_AUTO=0
  if [ -z "$MAP" ] && [ "$DRY" != "1" ]; then
    MAPCLONE="$WORK/_map/base-repo"
    mkdir -p "$WORK/_map"
    # одна попытка, без retry: если base-repo нет или сети нет — не висим, а идём в фолбэк
    if git clone -q --depth 1 "$REMOTE_BASE/base-repo.git" "$MAPCLONE" 2>/dev/null \
       && [ -f "$MAPCLONE/repos-map.md" ]; then
      MAP="$MAPCLONE"; MAP_AUTO=1
      dim "  base-repo склонирована с GitHub для обновления карты"
    fi
  fi
  if [ -n "$MAP" ]; then
    for R in $NEW_REPOS; do
      if grep -q "^## .*\`$R\`" "$MAP/repos-map.md" 2>/dev/null; then
        ylw "  $R — уже в карте"; continue
      fi
      python3 - "$MAP/repos-map.md" "$R" "$TODAY" <<'PYEOF'
import sys, re
from pathlib import Path
path, repo, today = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
entry = (f"\n## 🆕 `{repo}`\n**⚠️ НЕ ОПИСАНА.** Репа заведена автоматически деплойером {today}. "
         f"Опиши зону ответственности и убери этот маркер.\n")
marker = "\n---\n\n# 📐 Стандарт репозитория"
text = text.replace(marker, entry + marker, 1) if marker in text else text + entry
text = re.sub(r"(\*\*Актуальность:\*\*\s*)\d{4}-\d{2}-\d{2}", r"\g<1>" + today, text)
path.write_text(text, encoding="utf-8")
print(f"  + {repo} добавлена в repos-map.md")
PYEOF
      CL="$MAP/repos-map-CHANGELOG.md"
      [ -f "$CL" ] && printf '\n## %s — авто\n- `%s` — репа создана деплойером, добавлена в карту как **не описанная**.\n' \
        "$TODAY" "$R" >> "$CL"
      note "$R|—|repos-map|добавлена (требует описания)"
    done
    if [ "$MAP_AUTO" = "1" ]; then
      if ( cd "$MAP" && git add -A && \
           git commit -q -m "repos-map: авторегистрация новых реп ($TODAY)" 2>/dev/null && \
           git push -q origin HEAD 2>/dev/null ); then
        grn "✓ repos-map обновлена и запушена в base-repo — опиши новые репы позже"
      else
        cp "$MAP/repos-map.md" "$HOME/Downloads/repos-map-updated.md" 2>/dev/null
        ylw "  карта обновлена, но push не прошёл — копия: ~/Downloads/repos-map-updated.md"
      fi
    else
      grn "✓ repos-map обновлена: $MAP/repos-map.md — опиши новые репы и закоммить"
    fi
  else
    ADD="$HOME/Downloads/repos-map-additions.md"
    ylw "  base-repo недоступна (нет сети или репы) — карту обновлю текстом."
    ylw "  Чтобы ничего не потерялось, кладу его в: $ADD"
    for R in $NEW_REPOS; do
      printf '\n## 🆕 `%s`\n**⚠️ НЕ ОПИСАНА.** Заведена автоматически деплойером %s. Опиши зону и убери маркер.\n' \
        "$R" "$TODAY" | tee -a "$ADD"
      note "$R|—|repos-map|⚠ вставить вручную из repos-map-additions.md"
    done
    loud "repos-map не обновлена автоматически — перенеси блоки из $ADD"
  fi
fi

# --- ШАГ 4. Сводка ---------------------------------------------------------------
echo ""; bld "── Итог прогона"
if [ -n "$SUMMARY" ]; then
  printf '%s\n' "$SUMMARY" | awk -F'|' 'NF==4{printf "  %-24s %-10s %-14s %s\n",$1,$2,$3,$4}'
else
  grn "  изменений не потребовалось — всё уже по стандарту"
fi
if [ -n "$LOUD" ]; then
  echo ""; printf '%s%s── ТРЕБУЕТ ТВОЕГО РЕШЕНИЯ (скрипт намеренно НЕ трогал)%s\n' "$C_BLD" "$C_MAG" "$C_OFF"
  printf '%s\n' "$LOUD" | sed '/^$/d'
  echo ""; ylw "  Это не сбой прогона: остальное опубликовано. Разбери эти пункты руками."
fi
printf '%s\n' "$SUMMARY" > "$HOME/Downloads/deploy_last_run.log"
echo ""; cyn "лог: ~/Downloads/deploy_last_run.log"

rm -f "$INDEX" "$REPOLIST" "$PARSER"
cd "$HOME" && rm -rf "$WORK"
grn "✓ все репозитории обработаны"
