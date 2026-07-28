#!/usr/bin/env bash
# =============================================================================
# test_deploy.sh — регрессионный набор для templates/deploy.sh.
#
# Гоняет ПОЛНЫЙ боевой цикл, но безопасно: вместо GitHub — локальные bare-репы
# (REMOTE_BASE), вместо gh — стаб tests/bin/gh с журналом вызовов. Ни сети,
# ни токена, ни реальных реп не требуется.
#
# ЗАПУСК:  bash tests/test_deploy.sh          (из корня base-repo)
# Код возврата 0 — всё зелено; 1 — есть падения.
# =============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="${DEPLOY:-$HERE/../templates/deploy.sh}"
[ -f "$DEPLOY" ] || { echo "не найден deploy.sh: $DEPLOY"; exit 1; }

PASS=0; FAIL=0; CURRENT=""
ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad(){  printf '  \033[31m✗ %s\033[0m\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }
case_(){ CURRENT="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }
assert_eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "ждал: [$3]  получил: [$2]"; }
assert_contains(){ printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1" "нет подстроки: $3"; }
assert_missing(){ printf '%s' "$2" | grep -qF -- "$3" && bad "$1" "не должно быть: $3" || ok "$1"; }

# --- песочница ----------------------------------------------------------------
SANDBOX="$(mktemp -d)"
export HOME="$SANDBOX/home"; mkdir -p "$HOME/Downloads"
export PATH="$HERE/bin:$PATH"
export GH_STORE="$SANDBOX/ghstore"; mkdir -p "$GH_STORE"
REMOTES="$SANDBOX/remotes"; mkdir -p "$REMOTES"
export REMOTE_BASE="$REMOTES"
export OWNER="testuser"
export NO_COLOR=1
trap 'rm -rf "$SANDBOX"' EXIT

git config --global user.email "t@t.t" 2>/dev/null
git config --global user.name  "t" 2>/dev/null
git config --global init.defaultBranch main 2>/dev/null

# make_zip <outdir> <repo> <ver> <naming: dot|under> [--junk] [--nothesis] [--noreadme] [--flat]
make_zip(){
  local out="$1" repo="$2" ver="$3" naming="$4"; shift 4
  local junk=0 thesis=1 readme=1 flat=0 a
  for a in "$@"; do case "$a" in
    --junk) junk=1 ;; --nothesis) thesis=0 ;; --noreadme) readme=0 ;; --flat) flat=1 ;;
  esac; done
  local tmp; tmp="$(mktemp -d)"; local root="$tmp/$repo-v$ver"
  mkdir -p "$root/src"
  [ "$readme" = "1" ] && echo "# $repo" > "$root/README.md"
  printf '%s' "$ver" > "$root/VERSION"
  echo "print('$repo $ver')" > "$root/src/main.py"
  echo "doc"  > "$root/docs.md"
  echo "note" > "$root/notes.md"
  if [ "$thesis" = "1" ]; then
    printf '# CHANGELOG\n\n## [%s] — 2026-07-24 — Тезис версии %s (MINOR)\n\nОпорный абзац для %s: что сделано и зачем, своими словами.\n\n### Added\n- пункт про %s\n' \
      "$ver" "$ver" "$ver" "$ver" > "$root/CHANGELOG.md"
  else
    printf '# CHANGELOG\n\n## [%s]\n\n### Added\n- без тезиса\n' "$ver" > "$root/CHANGELOG.md"
  fi
  if [ "$junk" = "1" ]; then
    mkdir -p "$tmp/__MACOSX"; echo x > "$tmp/__MACOSX/._$repo-v$ver"
    echo junk > "$root/.DS_Store"
  fi
  local vname="$ver"; [ "$naming" = "under" ] && vname="$(printf '%s' "$ver" | tr '.' '_')"
  ( cd "$tmp" && if [ "$flat" = "1" ]; then
      cd "$root" && zip -qr "$out/$repo-v$vname.zip" .
    else
      zip -qr "$out/$repo-v$vname.zip" . -x '.*'
    fi )
  rm -rf "$tmp"
}

run_deploy(){ ( cd "$1" && bash "$DEPLOY" "$1" 2>&1 ); }
tag_tree_version(){ git -C "$1" show "v$2:VERSION" 2>/dev/null | tr -d ' \n'; }

# =============================================================================
case_ "1. Новая репа: создание, коммит, тег, релиз, ассет"
D="$SANDBOX/t1"; mkdir -p "$D"
make_zip "$D" "alpha-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"
assert_contains "репа создана" "$OUT" "репозиторий создан"
[ -f "$GH_STORE/repos/alpha-repo" ] && ok "репа есть в gh-сторе" || bad "репа есть в gh-сторе"
git clone -q "$REMOTES/alpha-repo.git" "$SANDBOX/c1" 2>/dev/null
assert_eq "тег v1.0.0 запушен" "$(git -C "$SANDBOX/c1" tag -l)" "v1.0.0"
assert_eq "дерево тега = версии архива" "$(tag_tree_version "$SANDBOX/c1" 1.0.0)" "1.0.0"
assert_eq "заголовок релиза по стандарту" \
  "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/title" 2>/dev/null)" "alpha-repo v1.0.0 — Тезис версии 1.0.0"
assert_contains "тело релиза = секция CHANGELOG" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body" 2>/dev/null)" "Опорный абзац"
assert_eq "канонический ассет приложен" \
  "$(ls -1 "$GH_STORE/rel/alpha-repo/v1.0.0/assets" 2>/dev/null)" "alpha-repo-v1.0.0.zip"

# =============================================================================
case_ "2. Серия версий: каждый тег указывает на СВОЁ дерево (регресс PIT-014)"
D="$SANDBOX/t2"; mkdir -p "$D"
for v in 1.0.0 1.1.0 1.2.0; do make_zip "$D" "beta-repo" "$v" dot; done
touch -t 202607240000 "$D"/*.zip           # одинаковый mtime — тот самый триггер бага
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/beta-repo.git" "$SANDBOX/c2" 2>/dev/null
assert_eq "все три тега на месте" "$(git -C "$SANDBOX/c2" tag -l | tr '\n' ' ')" "v1.0.0 v1.1.0 v1.2.0 "
for v in 1.0.0 1.1.0 1.2.0; do
  assert_eq "тег v$v → дерево $v" "$(tag_tree_version "$SANDBOX/c2" "$v")" "$v"
done
assert_eq "порядок версий соблюдён (HEAD = старшая)" \
  "$(git -C "$SANDBOX/c2" show HEAD:VERSION | tr -d ' \n')" "1.2.0"

# =============================================================================
case_ "3. Идемпотентность: повторный прогон ничего не меняет"
BEFORE="$(git -C "$SANDBOX/c2" rev-parse HEAD)"
OUT="$(run_deploy "$SANDBOX/t2")"
git -C "$SANDBOX/c2" fetch -q origin 2>/dev/null
assert_eq "HEAD не сдвинулся" "$(git -C "$SANDBOX/c2" rev-parse origin/main)" "$BEFORE"
assert_contains "версии распознаны как опубликованные" "$OUT" "тег есть, пропускаю"
assert_missing "новых коммитов не было" "$OUT" "✓ коммит:"

# =============================================================================
case_ "4. Нейминг: подчёркивания принимаются, но помечаются как неканон"
D="$SANDBOX/t4"; mkdir -p "$D"
make_zip "$D" "gamma-repo" "1.0.0" under
OUT="$(run_deploy "$D")"
assert_contains "предупреждение о нейминге" "$OUT" "канон это ТОЧКИ"
assert_contains "канон подсказан" "$OUT" "gamma-repo-v1.0.0.zip"
git clone -q "$REMOTES/gamma-repo.git" "$SANDBOX/c4" 2>/dev/null
assert_eq "версия из подчёркиваний разобрана верно" "$(tag_tree_version "$SANDBOX/c4" 1.0.0)" "1.0.0"
assert_eq "ассет всё равно с точками" \
  "$(ls -1 "$GH_STORE/rel/gamma-repo/v1.0.0/assets" 2>/dev/null)" "gamma-repo-v1.0.0.zip"

# =============================================================================
case_ "5. Упаковка: __MACOSX/.DS_Store рядом с обёрткой не ломают пуш (PIT-015)"
D="$SANDBOX/t5"; mkdir -p "$D"
make_zip "$D" "delta-repo" "1.0.0" dot --junk
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/delta-repo.git" "$SANDBOX/c5" 2>/dev/null
FILES="$(git -C "$SANDBOX/c5" ls-tree -r --name-only HEAD | tr '\n' ' ')"
assert_contains "README в корне (обёртка развёрнута)" "$FILES" "README.md"
assert_missing "папка-обёртка не уехала в репу" "$FILES" "delta-repo-v1.0.0/"
assert_missing "__MACOSX выкинут" "$FILES" "__MACOSX"
assert_missing ".DS_Store выкинут" "$FILES" ".DS_Store"

# =============================================================================
case_ "6. Рабочие копии и дубликаты НЕ публикуются, но названы вслух"
D="$SANDBOX/t6"; mkdir -p "$D"
for tail in " copy" " (copy)" "__copy_" " (1)"; do
  make_zip "$D" "eps-repo" "1.0.0" dot
  mv "$D/eps-repo-v1.0.0.zip" "$D/eps-repo-v1.0.0$tail.zip"
done
OUT="$(run_deploy "$D" || true)"
assert_contains "дубликаты названы" "$OUT" "рабочие копии и дубликаты"
assert_missing "репа НЕ создана" "$OUT" "репозиторий создан"
[ ! -d "$REMOTES/eps-repo.git" ] && ok "remote не появился" || bad "remote не появился"
make_zip "$D" "eps-repo" "1.0.0" dot          # нормальное имя рядом — публикуется
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/eps-repo.git" "$SANDBOX/c6" 2>/dev/null
assert_eq "нормальный архив рядом опубликован" "$(git -C "$SANDBOX/c6" tag -l)" "v1.0.0"

# =============================================================================
case_ "7. Битый архив: нет README — версия пропускается, репа не разрушена"
D="$SANDBOX/t7"; mkdir -p "$D"
make_zip "$D" "beta-repo" "1.3.0" dot --noreadme
OUT="$(run_deploy "$D")"
assert_contains "сказано про неопознанный корень" "$OUT" "корень не опознан"
git -C "$SANDBOX/c2" fetch -q origin --tags 2>/dev/null
assert_missing "битый тег НЕ создан" "$(git -C "$SANDBOX/c2" tag -l)" "v1.3.0"
assert_eq "старое дерево цело" "$(git -C "$SANDBOX/c2" show origin/main:VERSION | tr -d ' \n')" "1.2.0"

# =============================================================================
case_ "8. VERSION в дереве ≠ версии в имени — стоп по этой версии"
D="$SANDBOX/t8"; mkdir -p "$D"
make_zip "$D" "zeta-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/zeta-repo-v1.0.0.zip" )
printf '9.9.9' > "$tmp/zeta-repo-v1.0.0/VERSION"
rm "$D/zeta-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D/zeta-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_contains "рассинхрон пойман" "$OUT" "VERSION в дереве"
[ -d "$REMOTES/zeta-repo.git" ] && \
  { [ -z "$(git -C "$REMOTES/zeta-repo.git" tag -l 2>/dev/null)" ] && ok "тег не поставлен" || bad "тег не поставлен"; } \
  || ok "тег не поставлен"

# =============================================================================
case_ "9. DRY=1 — только план, ни одного изменения"
D="$SANDBOX/t9"; mkdir -p "$D"
make_zip "$D" "eta-repo" "1.0.0" dot
OUT="$(DRY=1 run_deploy "$D")"
assert_contains "план показан" "$OUT" "eta-repo"
assert_contains "сказано, что это план" "$OUT" "DRY=1"
[ ! -d "$REMOTES/eta-repo.git" ] && ok "репа НЕ создана" || bad "репа НЕ создана"
[ ! -f "$GH_STORE/repos/eta-repo" ] && ok "gh не звали на создание" || bad "gh не звали на создание"

# =============================================================================
case_ "10. Описания: заглушка чинится, осмысленное описание не трогается"
mkdir -p "$GH_STORE/rel/alpha-repo/v1.0.0"
printf 'Release 1.0.0' > "$GH_STORE/rel/alpha-repo/v1.0.0/body"
printf 'alpha-repo v1.0.0' > "$GH_STORE/rel/alpha-repo/v1.0.0/title"
OUT="$(REPAIR=1 run_deploy "$SANDBOX/t1")"
assert_contains "заглушка приведена к стандарту" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "Опорный абзац"
assert_eq "заголовок восстановлен с тезисом" \
  "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/title")" "alpha-repo v1.0.0 — Тезис версии 1.0.0"
GOOD="$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")"
OUT="$(REPAIR=1 run_deploy "$SANDBOX/t1")"
assert_eq "осмысленное описание не перезаписано" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "$GOOD"
assert_contains "сказано, что релиз заморожен" "$OUT" "не трогаю"

# =============================================================================
case_ "11. CHANGELOG без тезиса — предупреждение, но публикация идёт"
D="$SANDBOX/t11"; mkdir -p "$D"
make_zip "$D" "theta-repo" "1.0.0" dot --nothesis
OUT="$(run_deploy "$D")"
assert_contains "предупреждение о тезисе" "$OUT" "нет тезиса"
assert_eq "релиз всё равно создан" \
  "$(cat "$GH_STORE/rel/theta-repo/v1.0.0/title" 2>/dev/null)" "theta-repo v1.0.0"

# =============================================================================
case_ "12. Fail loud: тег указывает на чужое дерево — скрипт не чинит молча"
git clone -q "$REMOTES/alpha-repo.git" "$SANDBOX/c12" 2>/dev/null
( cd "$SANDBOX/c12" && printf '7.7.7' > VERSION && git add -A && \
  git commit -q -m "bad" && git tag -f -a v7.7.0 -m x >/dev/null 2>&1 && \
  git push -q origin main --tags 2>/dev/null )
make_zip "$SANDBOX/t1" "alpha-repo" "1.1.0" dot
OUT="$(run_deploy "$SANDBOX/t1")"
assert_contains "громкий флаг поднят" "$OUT" "ТРЕБУЕТ"
assert_contains "названа суть проблемы" "$OUT" "VERSION=7.7.7"
assert_contains "новая версия всё равно опубликована" "$OUT" "v1.1.0"

# =============================================================================
case_ "13. ONLY / SKIP"
D="$SANDBOX/t13"; mkdir -p "$D"
make_zip "$D" "iota-repo" "1.0.0" dot
make_zip "$D" "kappa-repo" "1.0.0" dot
OUT="$(ONLY="iota-repo" run_deploy "$D")"
assert_contains "ONLY: нужная репа взята" "$OUT" "iota-repo"
assert_missing "ONLY: лишняя отсеяна" "$OUT" "kappa-repo"
OUT="$(SKIP="kappa-repo" run_deploy "$D")"
assert_missing "SKIP: репа пропущена" "$OUT" "══ Репозиторий: kappa-repo"

# =============================================================================
case_ "14. repos-map: новая репа регистрируется автоматически"
MAPDIR="$SANDBOX/base-repo"; mkdir -p "$MAPDIR"
printf '# Карта\n\n**Актуальность:** 2026-01-01\n\n## `old-repo`\nОписание.\n\n---\n\n# 📐 Стандарт репозитория\n' \
  > "$MAPDIR/repos-map.md"
printf '# CHANGELOG карты\n' > "$MAPDIR/repos-map-CHANGELOG.md"
D="$SANDBOX/t14"; mkdir -p "$D"
make_zip "$D" "lambda-repo" "1.0.0" dot
OUT="$(BASE_REPO="$MAPDIR" run_deploy "$D")"
assert_contains "карта обновлена" "$(cat "$MAPDIR/repos-map.md")" "lambda-repo"
assert_contains "помечена как не описанная" "$(cat "$MAPDIR/repos-map.md")" "НЕ ОПИСАНА"
assert_contains "дата актуальности обновлена" "$(cat "$MAPDIR/repos-map.md")" "$(date +%Y-%m-%d)"
assert_contains "запись в истории карты" "$(cat "$MAPDIR/repos-map-CHANGELOG.md")" "lambda-repo"
OUT="$(BASE_REPO="$MAPDIR" run_deploy "$D")"
assert_eq "повторно не дублируется" \
  "$(grep -c 'lambda-repo' "$MAPDIR/repos-map.md")" "1"

# =============================================================================
case_ "15. repos-map: правка не теряется во временном клоне (регресс боевого прогона)"
D="$SANDBOX/t15"; mkdir -p "$D"
make_zip "$D" "base-repo" "1.0.0" dot          # base-repo деплоится в этом же прогоне
make_zip "$D" "mu-repo"   "1.0.0" dot
OUT="$(run_deploy "$D")"
assert_contains "новая репа зарегистрирована" "$OUT" "mu-repo"
if [ -f "$HOME/Downloads/repos-map-additions.md" ]; then
  assert_contains "текст сохранён на диск" "$(cat "$HOME/Downloads/repos-map-additions.md")" "mu-repo"
  assert_contains "поднят громкий флаг" "$OUT" "ТРЕБУЕТ"
else
  bad "текст сохранён на диск" "repos-map-additions.md не создан"
fi
assert_missing "во временный клон не писали" "$OUT" "repo_deploy_"

# =============================================================================
case_ "16. Исторический нейминг: все встречавшиеся варианты читаются"
D="$SANDBOX/t16"; mkdir -p "$D"
make_zip "$D" "nu-repo" "1.0.0" dot
# каждый вариант — настоящий архив своей версии, переименован в исторический формат
set -- "1.1.0:nu-repo_v1.1.0" "1.2.0:nu-repo-v1_2_0" "1.3.0:nu-repo-v1-3-0" \
       "1.4.0:nu-repo-1.4.0" "1.5.0:nu-repo_1.5.0"
for pair in "$@"; do
  v="${pair%%:*}"; fname="${pair#*:}"
  make_zip "$D" "nu-repo" "$v" dot
  mv "$D/nu-repo-v$v.zip" "$D/$fname.zip"
done
OUT="$(DRY=1 run_deploy "$D")"
assert_contains "все шесть версий распознаны" "$OUT" "версий: 6"
for v in 1.1.0 1.2.0 1.3.0 1.4.0 1.5.0; do
  assert_contains "вариант с версией $v прочитан" "$OUT" "$v"
done
assert_contains "неканон помечен" "$OUT" "канон это ТОЧКИ"

case_ "17. Двухчастная версия (v1.2) достраивается до X.Y.0"
D="$SANDBOX/t17"; mkdir -p "$D"
make_zip "$D" "xi-repo" "2.7.0" dot
mv "$D/xi-repo-v2.7.0.zip" "$D/xi-repo-v2.7.zip"
OUT="$(DRY=1 run_deploy "$D")"
assert_contains "версия достроена" "$OUT" "2.7.0"
assert_contains "сказано про правило" "$OUT" "всегда X.Y.Z"

case_ "18. SemVer-сортировка: 2.9.0 младше 2.10.0 (не строковое сравнение)"
D="$SANDBOX/t18"; mkdir -p "$D"
for v in 2.9.0 2.10.0 2.12.0; do make_zip "$D" "omicron-repo" "$v" dot; done
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/omicron-repo.git" "$SANDBOX/c18" 2>/dev/null
assert_eq "порядок публикации верный (HEAD = 2.12.0)" \
  "$(git -C "$SANDBOX/c18" show "v2.12.0:VERSION" | tr -d ' \n')" "2.12.0"
for v in 2.9.0 2.10.0 2.12.0; do
  assert_eq "тег v$v → своё дерево" "$(tag_tree_version "$SANDBOX/c18" "$v")" "$v"
done

case_ "19. Плоская упаковка (без обёртки) — тоже работает"
D="$SANDBOX/t19"; mkdir -p "$D"
make_zip "$D" "pi-repo" "1.0.0" dot --flat
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/pi-repo.git" "$SANDBOX/c19" 2>/dev/null
assert_eq "версия опубликована" "$(tag_tree_version "$SANDBOX/c19" 1.0.0)" "1.0.0"
assert_contains "README в корне" "$(git -C "$SANDBOX/c19" ls-tree --name-only v1.0.0)" "README.md"

case_ "20. Двойная обёртка (папка в папке) разворачивается"
D="$SANDBOX/t20"; mkdir -p "$D"
make_zip "$D" "rho-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/rho-repo-v1.0.0.zip" )
mkdir -p "$tmp/outer" && mv "$tmp/rho-repo-v1.0.0" "$tmp/outer/"
rm "$D/rho-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D/rho-repo-v1.0.0.zip" outer )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
git clone -q "$REMOTES/rho-repo.git" "$SANDBOX/c20" 2>/dev/null
assert_contains "обёртка развёрнута на 2 уровня" "$OUT" "уровней: 2"
assert_contains "README в корне" "$(git -C "$SANDBOX/c20" ls-tree --name-only v1.0.0)" "README.md"

case_ "21. Слишком мало файлов — не считаем это репой"
D="$SANDBOX/t21"; mkdir -p "$D"
tmp="$(mktemp -d)"; mkdir -p "$tmp/sigma-repo-v1.0.0"
echo "# x" > "$tmp/sigma-repo-v1.0.0/README.md"; printf '1.0.0' > "$tmp/sigma-repo-v1.0.0/VERSION"
( cd "$tmp" && zip -qr "$D/sigma-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_contains "отказ с объяснением" "$OUT" "не похоже на репу"
[ ! -d "$REMOTES/sigma-repo.git" ] && ok "репа не создана" || bad "репа не создана"

case_ "22. Битый zip не роняет батч — соседняя репа публикуется"
D="$SANDBOX/t22"; mkdir -p "$D"
make_zip "$D" "tau-repo" "1.0.0" dot
printf 'это не zip' > "$D/upsilon-repo-v1.0.0.zip"
OUT="$(run_deploy "$D")"
assert_contains "битый архив назван" "$OUT" "upsilon-repo"
git clone -q "$REMOTES/tau-repo.git" "$SANDBOX/c22" 2>/dev/null
assert_eq "соседняя репа всё равно опубликована" "$(tag_tree_version "$SANDBOX/c22" 1.0.0)" "1.0.0"

case_ "23. BACKFILL: старая версия по умолчанию не заливается"
D="$SANDBOX/t23"; mkdir -p "$D"
make_zip "$D" "phi-repo" "2.0.0" dot
run_deploy "$D" >/dev/null
make_zip "$D" "phi-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"
assert_contains "старая версия пропущена" "$OUT" "ниже v2.0.0"
OUT="$(BACKFILL=1 run_deploy "$D")"
git clone -q "$REMOTES/phi-repo.git" "$SANDBOX/c23" 2>/dev/null
assert_contains "с BACKFILL=1 залилась" "$(git -C "$SANDBOX/c23" tag -l | tr '\n' ' ')" "v1.0.0"

case_ "24. FORCE: осмысленное описание перезаписывается только явно"
GOOD="$(cat "$GH_STORE/rel/tau-repo/v1.0.0/body")"
printf 'РУЧНОЕ ОПИСАНИЕ, написанное человеком и вполне осмысленное' > "$GH_STORE/rel/tau-repo/v1.0.0/body"
OUT="$(REPAIR=1 run_deploy "$SANDBOX/t22")"
assert_contains "без FORCE не тронуто" "$(cat "$GH_STORE/rel/tau-repo/v1.0.0/body")" "РУЧНОЕ ОПИСАНИЕ"
OUT="$(REPAIR=1 FORCE=1 run_deploy "$SANDBOX/t22")"
assert_contains "с FORCE=1 перезаписано из CHANGELOG" "$(cat "$GH_STORE/rel/tau-repo/v1.0.0/body")" "Опорный абзац"

case_ "25. ASSETS_ONLY: догружает ассет, дерево не трогает"
rm -rf "$GH_STORE/rel/tau-repo/v1.0.0/assets"; mkdir -p "$GH_STORE/rel/tau-repo/v1.0.0/assets"
BEFORE="$(git -C "$SANDBOX/c22" rev-parse HEAD)"
OUT="$(ASSETS_ONLY=1 run_deploy "$SANDBOX/t22")"
assert_eq "ассет догружен" "$(ls -1 "$GH_STORE/rel/tau-repo/v1.0.0/assets")" "tau-repo-v1.0.0.zip"
git -C "$SANDBOX/c22" fetch -q origin 2>/dev/null
assert_eq "дерево не сдвинулось" "$(git -C "$SANDBOX/c22" rev-parse origin/main)" "$BEFORE"

case_ "26. Кириллица и тире в описании не бьются (UTF-8 через notes-file)"
assert_contains "русский текст цел" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "Опорный абзац"
assert_contains "em-dash из заголовка цел" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/title")" "—"

case_ "27. В папке нет архивов — понятное сообщение, а не молчание"
D="$SANDBOX/t27"; mkdir -p "$D"; echo x > "$D/readme.txt"; echo y > "$D/notes.md"
OUT="$(run_deploy "$D" || true)"
assert_contains "объяснено, чего ждали" "$OUT" "версионных архивов не найдено"

case_ "28. NO_COLOR: в пайп уходит чистый текст без ANSI"
D="$SANDBOX/t28"; mkdir -p "$D"
make_zip "$D" "chi-repo" "1.0.0" dot
OUT="$(DRY=1 run_deploy "$D")"
printf '%s' "$OUT" | grep -q "$(printf '\033')" && bad "ANSI-кодов нет в неинтерактивном выводе" || ok "ANSI-кодов нет в неинтерактивном выводе"

case_ "29. Репа существует, но пустая (нет коммитов) — публикуем без падения"
git init -q --bare "$REMOTES/psi-repo.git"
echo private > "$GH_STORE/repos/psi-repo"
D="$SANDBOX/t29"; mkdir -p "$D"
make_zip "$D" "psi-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/psi-repo.git" "$SANDBOX/c29" 2>/dev/null
assert_eq "версия опубликована в пустую репу" "$(tag_tree_version "$SANDBOX/c29" 1.0.0)" "1.0.0"

case_ "30. Несколько реп за один прогон — все обработаны"
D="$SANDBOX/t30"; mkdir -p "$D"
for r in aa-repo bb-repo cc-repo; do make_zip "$D" "$r" "1.0.0" dot; done
OUT="$(run_deploy "$D")"
for r in aa-repo bb-repo cc-repo; do
  git clone -q "$REMOTES/$r.git" "$SANDBOX/c30-$r" 2>/dev/null
  assert_eq "$r опубликована" "$(tag_tree_version "$SANDBOX/c30-$r" 1.0.0)" "1.0.0"
done

case_ "31. Вложенная репа со своим VERSION не путает предполёт (регресс на реальном архиве)"
D="$SANDBOX/t31"; mkdir -p "$D"
make_zip "$D" "omega-repo" "2.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/omega-repo-v2.0.0.zip" )
mkdir -p "$tmp/omega-repo-v2.0.0/base-repo"
printf '1.13.0' > "$tmp/omega-repo-v2.0.0/base-repo/VERSION"
echo "# base" > "$tmp/omega-repo-v2.0.0/base-repo/README.md"
rm "$D/omega-repo-v2.0.0.zip"; ( cd "$tmp" && zip -qr "$D/omega-repo-v2.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_missing "предполёт не склеил версии" "$OUT" "1.13.02.0.0"
git clone -q "$REMOTES/omega-repo.git" "$SANDBOX/c31" 2>/dev/null
assert_eq "репа с вложенной репой опубликована" "$(tag_tree_version "$SANDBOX/c31" 2.0.0)" "2.0.0"
assert_contains "вложенная репа сохранена в дереве" \
  "$(git -C "$SANDBOX/c31" ls-tree -r --name-only v2.0.0)" "base-repo/VERSION"

case_ "32. Служебные архивы из чата игнорируются молча"
D="$SANDBOX/t32"; mkdir -p "$D"
make_zip "$D" "zeta2-repo" "1.0.0" dot
for junk in "1" "16" "files" "files 10" "Archive_2"; do
  make_zip "$D" "tmp-repo" "9.9.9" dot; mv "$D/tmp-repo-v9.9.9.zip" "$D/$junk.zip"
done
OUT="$(run_deploy "$D")"
assert_contains "счётчик служебных показан" "$OUT" "пропущено служебных архивов: 5"
assert_missing "нет жалоб на нечитаемую версию" "$OUT" "есть цифры, но версия не читается"
[ ! -d "$REMOTES/files.git" ] && ok "репа files не заведена" || bad "репа files не заведена"
[ ! -d "$REMOTES/1.git" ] && ok "репа 1 не заведена" || bad "репа 1 не заведена"
git clone -q "$REMOTES/zeta2-repo.git" "$SANDBOX/c32" 2>/dev/null
assert_eq "нормальная репа рядом опубликована" "$(tag_tree_version "$SANDBOX/c32" 1.0.0)" "1.0.0"

case_ "33. Вариантный постфикс: только для реп из VARIANT_REPOS"
D="$SANDBOX/t33"; mkdir -p "$D"
make_zip "$D" "finpilot" "6.20.1" dot
mv "$D/finpilot-v6.20.1.zip" "$D/finpilot_v6_20_1_intl.zip"
make_zip "$D" "other-repo" "1.0.0" dot
mv "$D/other-repo-v1.0.0.zip" "$D/other-repo_v1_0_0_intl.zip"
OUT="$(run_deploy "$D" || true)"
assert_contains "finpilot распознан" "$OUT" "finpilot v6.20.1"
assert_contains "постфикс показан вслух" "$OUT" "вариантные имена"
assert_missing "чужая репа НЕ распознана по постфиксу" "$OUT" "══ Репозиторий: other-repo"
git clone -q "$REMOTES/finpilot.git" "$SANDBOX/c33" 2>/dev/null
assert_eq "finpilot опубликован" "$(tag_tree_version "$SANDBOX/c33" 6.20.1)" "6.20.1"

case_ "34. Не-UTF-8 имена внутри архива не роняют предполёт"
D="$SANDBOX/t34"; mkdir -p "$D"
tmp="$(mktemp -d)"; root="$tmp/iota2-repo-v1.0.0"; mkdir -p "$root/src"
echo "# iota2-repo" > "$root/README.md"; printf '1.0.0' > "$root/VERSION"
printf '# CHANGELOG\n\n## [1.0.0] — 2026-07-24 — Тезис (MINOR)\n\nАбзац.\n\n### Added\n- x\n' > "$root/CHANGELOG.md"
echo a > "$root/src/main.py"; echo b > "$root/docs.md"; echo c > "$root/notes.md"
# имя в CP1251 — невалидный UTF-8
cp "$root/notes.md" "$root/$(printf '\xe4\xf0\xf3\xe3.md')" 2>/dev/null || true
( cd "$tmp" && zip -qr "$D/iota2-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D" 2>&1)"; rm -rf "$tmp"
assert_missing "нет Illegal byte sequence" "$OUT" "Illegal byte sequence"
git clone -q "$REMOTES/iota2-repo.git" "$SANDBOX/c34" 2>/dev/null
assert_eq "репа опубликована" "$(tag_tree_version "$SANDBOX/c34" 1.0.0)" "1.0.0"

# =============================================================================
printf '\n\033[1m── Итог\033[0m\n'
printf '  \033[32mпройдено: %s\033[0m\n' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '  \033[31mпровалено: %s\033[0m\n' "$FAIL"; exit 1; fi
printf '  \033[32mвсё зелено\033[0m\n'
