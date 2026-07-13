#!/usr/bin/env bash
# =============================================================================
# deploy_all.sh — задеплоить ВСЕ репы системы из папки с архивами, одной командой.
#
# Обёртка над deploy_from_zip.sh (который умеет ровно одну репу за запуск).
# Часть base-repo (templates/). Тройка:
#   publish.sh          — внутри клона: версия -> тег -> GitHub Release
#   deploy_from_zip.sh  — снаружи: архив -> клон -> чистая замена -> push (+ publish.sh)
#   deploy_all.sh       — этот: пачка архивов -> deploy_from_zip.sh по каждому -> сводка
#
# ЗАПУСК (macOS/zsh):
#   zsh ~/Downloads/deploy_all.sh ~/Downloads/repos
#   zsh ~/Downloads/deploy_all.sh ~/Downloads/repos base-repo.zip edu-base.zip   # только эти
#
# Переменные:
#   DEPLOY=<путь>     где лежит deploy_from_zip.sh (по умолчанию — рядом с этим файлом)
#   SUMS=<путь>       файл SHA256SUMS для сверки целостности (по умолчанию ищет в папке)
#   STOP_ON_FAIL=1    падать на первой ошибке (по умолчанию: пройти все, ошибки — в сводку)
#   OWNER=vevdokimovm · BRANCH=main   — пробрасываются в deploy_from_zip.sh
#
# ВАЖНО: deploy_from_zip.sh делает ЧИСТУЮ ЗАМЕНУ дерева (всё, кроме .git). Файл, которого
# нет в архиве, будет удалён из репы. Это осознанное поведение (PIT-004: «чистка ≠ долив»),
# но означает: архив должен быть ПОЛНОЙ репой, а не патчем.
# =============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="${DEPLOY:-$HERE/deploy_from_zip.sh}"
DIR="${1:-}"
shift 2>/dev/null || true

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold(){ printf '\033[1m%s\033[0m\n' "$*"; }

usage(){ cat <<'USAGE'
Использование: zsh deploy_all.sh <папка-с-архивами> [архив1.zip архив2.zip ...]

  zsh ~/Downloads/deploy_all.sh ~/Downloads/repos                 # все .zip из папки
  zsh ~/Downloads/deploy_all.sh ~/Downloads/repos base-repo.zip   # только указанные

Требуется: git, gh (для релизов), deploy_from_zip.sh рядом с этим скриптом.
USAGE
exit 1; }

[ -n "$DIR" ] || usage
[ -d "$DIR" ] || { red "ОШИБКА: папка не найдена: $DIR"; exit 1; }
[ -f "$DEPLOY" ] || { red "ОШИБКА: deploy_from_zip.sh не найден: $DEPLOY"; red "Положи его рядом или задай DEPLOY=<путь>"; exit 1; }
command -v git >/dev/null 2>&1 || { red "ОШИБКА: git не найден"; exit 1; }
command -v gh  >/dev/null 2>&1 || ylw "⚠ gh не найден: push пройдёт, GitHub Release — вручную"

# --- какие архивы деплоим ------------------------------------------------------
if [ "$#" -gt 0 ]; then
  ZIPS=("$@")
else
  ZIPS=()
  for z in "$DIR"/*.zip; do [ -f "$z" ] && ZIPS+=("$(basename "$z")"); done
fi
[ "${#ZIPS[@]}" -gt 0 ] || { red "ОШИБКА: в $DIR нет .zip"; exit 1; }

# base-repo — первым: остальные репы наследуют его кит, логично обновить родителя раньше
ORDERED=()
for z in "${ZIPS[@]}"; do [ "$z" = "base-repo.zip" ] && ORDERED+=("$z"); done
for z in "${ZIPS[@]}"; do [ "$z" != "base-repo.zip" ] && ORDERED+=("$z"); done

bold "К деплою (${#ORDERED[@]}):"
for z in "${ORDERED[@]}"; do echo "   $z"; done
echo ""

# --- целостность архивов -------------------------------------------------------
SUMS="${SUMS:-$DIR/SHA256SUMS}"
if [ -f "$SUMS" ]; then
  ylw "→ сверяю sha256 по $SUMS"
  ( cd "$DIR" && /usr/bin/shasum -a 256 -c "$(basename "$SUMS")" ) || {
    red "ОШИБКА: sha256 не сошёлся — архив побился при скачивании. Перекачай."; exit 1; }
  grn "✓ все архивы целы"
else
  ylw "⚠ SHA256SUMS не найден — пропускаю сверку целостности"
fi
echo ""

# --- прогон --------------------------------------------------------------------
OK=(); FAIL=()
for z in "${ORDERED[@]}"; do
  ZIP="$DIR/$z"
  [ -f "$ZIP" ] || { red "✗ $z — файла нет"; FAIL+=("$z"); continue; }

  bold "════════════════════════════════════════════════════════"
  bold "  $z"
  bold "════════════════════════════════════════════════════════"

  if zsh "$DEPLOY" "$ZIP"; then
    OK+=("$z")
    grn "✓ $z — задеплоена"
  else
    FAIL+=("$z")
    red "✗ $z — НЕ задеплоена"
    if [ "${STOP_ON_FAIL:-0}" = "1" ]; then
      red "STOP_ON_FAIL=1 — останавливаюсь"
      break
    fi
    ylw "  иду дальше (STOP_ON_FAIL=1, чтобы падать сразу)"
  fi
  echo ""
done

# --- сводка --------------------------------------------------------------------
echo ""
bold "════════════════════ ИТОГ ════════════════════"
grn "Успешно: ${#OK[@]}"
for z in "${OK[@]}"; do echo "   ✓ ${z%.zip}"; done
if [ "${#FAIL[@]}" -gt 0 ]; then
  echo ""
  red "Провалено: ${#FAIL[@]}"
  for z in "${FAIL[@]}"; do echo "   ✗ ${z%.zip}"; done
  echo ""
  ylw "Перезапуск безопасен: deploy_from_zip.sh идемпотентен —"
  ylw "если дерево уже актуально, он просто скажет «коммит не нужен»."
  exit 1
fi
echo ""
grn "Все репы обновлены."
