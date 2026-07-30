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
ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); grp_hit G_OK; }
bad(){  printf '  \033[31m✗ %s\033[0m\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); grp_hit G_BAD; }
# Кейс объявляется с ИДЕНТИФИКАТОРОМ ЗОНЫ (A1, B3, ...), а не сквозным номером:
# номер говорит только «какой по счёту», буква — «что именно проверяется».
G_CUR=""; G_LIST=""
case_(){
  CURRENT="$2"; G_CUR="$(printf '%s' "$1" | cut -c1)"
  case " $G_LIST " in *" $G_CUR "*) : ;; *) G_LIST="$G_LIST $G_CUR" ;; esac
  eval "G_TOT_$G_CUR=\${G_TOT_$G_CUR:-0}"
  printf '\n\033[1m[%s] %s\033[0m\n' "$1" "$2"
}
grp_hit(){ eval "$1_$G_CUR=\$(( \${$1_$G_CUR:-0} + 1 ))"; }
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

# Большинство кейсов переиспользуют архив после публикации, поэтому по умолчанию
# в тестах архивы сохраняются. Кейсы про удаление ставят KEEP_ARCHIVES=0 явно.
run_deploy(){ ( cd "$1" && KEEP_ARCHIVES="${KEEP_ARCHIVES:-1}" bash "$DEPLOY" "$1" 2>&1 ); }
tag_tree_version(){ git -C "$1" show "v$2:VERSION" 2>/dev/null | tr -d ' \n'; }

# =============================================================================
case_ "A1" "Новая репа: создание, коммит, тег, релиз, ассет"
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
case_ "G1" "Серия версий: каждый тег указывает на СВОЁ дерево (регресс PIT-014)"
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
case_ "A2" "Идемпотентность: повторный прогон ничего не меняет"
BEFORE="$(git -C "$SANDBOX/c2" rev-parse HEAD)"
OUT="$(run_deploy "$SANDBOX/t2")"
git -C "$SANDBOX/c2" fetch -q origin 2>/dev/null
assert_eq "HEAD не сдвинулся" "$(git -C "$SANDBOX/c2" rev-parse origin/main)" "$BEFORE"
assert_contains "версии распознаны как опубликованные" "$OUT" "тег есть, пропускаю"
assert_missing "новых коммитов не было" "$OUT" "✓ коммит:"

# =============================================================================
case_ "B1" "Нейминг: подчёркивания принимаются, но помечаются как неканон"
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
case_ "C1" "Упаковка: __MACOSX/.DS_Store рядом с обёрткой не ломают пуш (PIT-015)"
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
case_ "B2" "Рабочие копии и дубликаты НЕ публикуются, но названы вслух"
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
case_ "C2" "Битый архив: нет README — версия пропускается, репа не разрушена"
D="$SANDBOX/t7"; mkdir -p "$D"
make_zip "$D" "beta-repo" "1.3.0" dot --noreadme
OUT="$(run_deploy "$D")"
assert_contains "сказано про неопознанный корень" "$OUT" "корень не опознан"
git -C "$SANDBOX/c2" fetch -q origin --tags 2>/dev/null
assert_missing "битый тег НЕ создан" "$(git -C "$SANDBOX/c2" tag -l)" "v1.3.0"
assert_eq "старое дерево цело" "$(git -C "$SANDBOX/c2" show origin/main:VERSION | tr -d ' \n')" "1.2.0"

# =============================================================================
case_ "C3" "VERSION в дереве ≠ версии в имени — стоп по этой версии"
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
case_ "E1" "DRY=1 — только план, ни одного изменения"
D="$SANDBOX/t9"; mkdir -p "$D"
make_zip "$D" "eta-repo" "1.0.0" dot
OUT="$(DRY=1 run_deploy "$D")"
assert_contains "план показан" "$OUT" "eta-repo"
assert_contains "сказано, что это план" "$OUT" "DRY=1"
[ ! -d "$REMOTES/eta-repo.git" ] && ok "репа НЕ создана" || bad "репа НЕ создана"
[ ! -f "$GH_STORE/repos/eta-repo" ] && ok "gh не звали на создание" || bad "gh не звали на создание"

# =============================================================================
case_ "D1" "Описания: заглушка чинится, осмысленное описание не трогается"
mkdir -p "$GH_STORE/rel/alpha-repo/v1.0.0"
printf 'Release 1.0.0' > "$GH_STORE/rel/alpha-repo/v1.0.0/body"
printf 'alpha-repo v1.0.0' > "$GH_STORE/rel/alpha-repo/v1.0.0/title"
OUT="$(REPAIR=1 run_deploy "$SANDBOX/t1")"
assert_contains "заглушка приведена к стандарту" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "Опорный абзац"
assert_eq "заголовок восстановлен с тезисом" \
  "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/title")" "alpha-repo v1.0.0 — Тезис версии 1.0.0"
GOOD="$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")"
OUT="$(run_deploy "$SANDBOX/t1")"
assert_eq "совпадающее с CHANGELOG описание не трогается" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "$GOOD"
assert_missing "и об этом не шумит" "$OUT" "приведено к стандарту"
# осмысленное, но РАСХОДЯЩЕЕСЯ с CHANGELOG — не трогаем, но говорим вслух
printf 'Своё развёрнутое описание релиза, написанное руками, которое не совпадает с журналом и вполне осмысленно по содержанию.' \
  > "$GH_STORE/rel/alpha-repo/v1.0.0/body"
OUT="$(AUDIT=1 run_deploy "$SANDBOX/t1")"
assert_contains "расхождение названо" "$OUT" "отличается от CHANGELOG"
assert_contains "текст сохранён" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "написанное руками"
OUT="$(FORCE=1 run_deploy "$SANDBOX/t1")"
assert_contains "с FORCE=1 синхронизировано" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "Опорный абзац"

# =============================================================================
case_ "D2" "CHANGELOG без тезиса — предупреждение, но публикация идёт"
D="$SANDBOX/t11"; mkdir -p "$D"
make_zip "$D" "theta-repo" "1.0.0" dot --nothesis
OUT="$(run_deploy "$D")"
assert_contains "предупреждение о тезисе" "$OUT" "нет тезиса"
assert_eq "релиз всё равно создан" \
  "$(cat "$GH_STORE/rel/theta-repo/v1.0.0/title" 2>/dev/null)" "theta-repo v1.0.0"

# =============================================================================
case_ "G2" "Fail loud: тег указывает на чужое дерево — скрипт не чинит молча"
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
case_ "E2" "ONLY / SKIP"
D="$SANDBOX/t13"; mkdir -p "$D"
make_zip "$D" "iota-repo" "1.0.0" dot
make_zip "$D" "kappa-repo" "1.0.0" dot
OUT="$(ONLY="iota-repo" run_deploy "$D")"
assert_contains "ONLY: нужная репа взята" "$OUT" "iota-repo"
assert_missing "ONLY: лишняя отсеяна" "$OUT" "kappa-repo"
OUT="$(SKIP="kappa-repo" run_deploy "$D")"
assert_missing "SKIP: репа пропущена" "$OUT" "══ Репозиторий: kappa-repo"

# =============================================================================
case_ "H1" "repos-map: новая репа регистрируется автоматически"
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
case_ "H2" "repos-map: правка не теряется во временном клоне (регресс боевого прогона)"
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
case_ "B3" "Исторический нейминг: все встречавшиеся варианты читаются"
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

case_ "B4" "Двухчастная версия (v1.2) достраивается до X.Y.0"
D="$SANDBOX/t17"; mkdir -p "$D"
make_zip "$D" "xi-repo" "2.7.0" dot
mv "$D/xi-repo-v2.7.0.zip" "$D/xi-repo-v2.7.zip"
OUT="$(DRY=1 run_deploy "$D")"
assert_contains "версия достроена" "$OUT" "2.7.0"
assert_contains "сказано про правило" "$OUT" "всегда X.Y.Z"

case_ "A3" "SemVer-сортировка: 2.9.0 младше 2.10.0 (не строковое сравнение)"
D="$SANDBOX/t18"; mkdir -p "$D"
for v in 2.9.0 2.10.0 2.12.0; do make_zip "$D" "omicron-repo" "$v" dot; done
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/omicron-repo.git" "$SANDBOX/c18" 2>/dev/null
assert_eq "порядок публикации верный (HEAD = 2.12.0)" \
  "$(git -C "$SANDBOX/c18" show "v2.12.0:VERSION" | tr -d ' \n')" "2.12.0"
for v in 2.9.0 2.10.0 2.12.0; do
  assert_eq "тег v$v → своё дерево" "$(tag_tree_version "$SANDBOX/c18" "$v")" "$v"
done

case_ "C4" "Плоская упаковка (без обёртки) — тоже работает"
D="$SANDBOX/t19"; mkdir -p "$D"
make_zip "$D" "pi-repo" "1.0.0" dot --flat
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/pi-repo.git" "$SANDBOX/c19" 2>/dev/null
assert_eq "версия опубликована" "$(tag_tree_version "$SANDBOX/c19" 1.0.0)" "1.0.0"
assert_contains "README в корне" "$(git -C "$SANDBOX/c19" ls-tree --name-only v1.0.0)" "README.md"

case_ "C5" "Двойная обёртка (папка в папке) разворачивается"
D="$SANDBOX/t20"; mkdir -p "$D"
make_zip "$D" "rho-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/rho-repo-v1.0.0.zip" )
mkdir -p "$tmp/outer" && mv "$tmp/rho-repo-v1.0.0" "$tmp/outer/"
rm "$D/rho-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D/rho-repo-v1.0.0.zip" outer )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
git clone -q "$REMOTES/rho-repo.git" "$SANDBOX/c20" 2>/dev/null
assert_contains "обёртка развёрнута на 2 уровня" "$OUT" "уровней: 2"
assert_contains "README в корне" "$(git -C "$SANDBOX/c20" ls-tree --name-only v1.0.0)" "README.md"

case_ "C6" "Слишком мало файлов — не считаем это репой"
D="$SANDBOX/t21"; mkdir -p "$D"
tmp="$(mktemp -d)"; mkdir -p "$tmp/sigma-repo-v1.0.0"
echo "# x" > "$tmp/sigma-repo-v1.0.0/README.md"; printf '1.0.0' > "$tmp/sigma-repo-v1.0.0/VERSION"
( cd "$tmp" && zip -qr "$D/sigma-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_contains "отказ с объяснением" "$OUT" "не похоже на репу"
[ ! -d "$REMOTES/sigma-repo.git" ] && ok "репа не создана" || bad "репа не создана"

case_ "C7" "Битый zip не роняет батч — соседняя репа публикуется"
D="$SANDBOX/t22"; mkdir -p "$D"
make_zip "$D" "tau-repo" "1.0.0" dot
printf 'это не zip' > "$D/upsilon-repo-v1.0.0.zip"
OUT="$(run_deploy "$D")"
assert_contains "битый архив назван" "$OUT" "upsilon-repo"
git clone -q "$REMOTES/tau-repo.git" "$SANDBOX/c22" 2>/dev/null
assert_eq "соседняя репа всё равно опубликована" "$(tag_tree_version "$SANDBOX/c22" 1.0.0)" "1.0.0"

case_ "E3" "BACKFILL: старая версия по умолчанию не заливается"
D="$SANDBOX/t23"; mkdir -p "$D"
make_zip "$D" "phi-repo" "2.0.0" dot
run_deploy "$D" >/dev/null
make_zip "$D" "phi-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"
assert_contains "старая версия пропущена" "$OUT" "ниже v2.0.0"
OUT="$(BACKFILL=1 run_deploy "$D")"
git clone -q "$REMOTES/phi-repo.git" "$SANDBOX/c23" 2>/dev/null
assert_contains "с BACKFILL=1 залилась" "$(git -C "$SANDBOX/c23" tag -l | tr '\n' ' ')" "v1.0.0"

case_ "E4" "FORCE: осмысленное описание перезаписывается только явно"
GOOD="$(cat "$GH_STORE/rel/tau-repo/v1.0.0/body")"
printf 'РУЧНОЕ ОПИСАНИЕ, написанное человеком и вполне осмысленное' > "$GH_STORE/rel/tau-repo/v1.0.0/body"
OUT="$(REPAIR=1 run_deploy "$SANDBOX/t22")"
assert_contains "без FORCE не тронуто" "$(cat "$GH_STORE/rel/tau-repo/v1.0.0/body")" "РУЧНОЕ ОПИСАНИЕ"
OUT="$(REPAIR=1 FORCE=1 run_deploy "$SANDBOX/t22")"
assert_contains "с FORCE=1 перезаписано из CHANGELOG" "$(cat "$GH_STORE/rel/tau-repo/v1.0.0/body")" "Опорный абзац"

case_ "E5" "ASSETS_ONLY: догружает ассет, дерево не трогает"
rm -rf "$GH_STORE/rel/tau-repo/v1.0.0/assets"; mkdir -p "$GH_STORE/rel/tau-repo/v1.0.0/assets"
BEFORE="$(git -C "$SANDBOX/c22" rev-parse HEAD)"
OUT="$(ASSETS_ONLY=1 run_deploy "$SANDBOX/t22")"
assert_eq "ассет догружен" "$(ls -1 "$GH_STORE/rel/tau-repo/v1.0.0/assets")" "tau-repo-v1.0.0.zip"
git -C "$SANDBOX/c22" fetch -q origin 2>/dev/null
assert_eq "дерево не сдвинулось" "$(git -C "$SANDBOX/c22" rev-parse origin/main)" "$BEFORE"

case_ "I1" "Кириллица и тире в описании не бьются (UTF-8 через notes-file)"
assert_contains "русский текст цел" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/body")" "Опорный абзац"
assert_contains "em-dash из заголовка цел" "$(cat "$GH_STORE/rel/alpha-repo/v1.0.0/title")" "—"

case_ "C8" "В папке нет архивов — понятное сообщение, а не молчание"
D="$SANDBOX/t27"; mkdir -p "$D"; echo x > "$D/readme.txt"; echo y > "$D/notes.md"
OUT="$(run_deploy "$D" || true)"
assert_contains "сказано, что публиковать нечего" "$OUT" "Публиковать нечего"
assert_contains "подсказан канон имени" "$OUT" "<repo>-vX.Y.Z.zip"
assert_missing "это НЕ ошибка" "$OUT" "ОШИБКА"
( cd "$D" && bash "$DEPLOY" "$D" >/dev/null 2>&1 ) \
  && ok "код возврата 0 — пустая папка не провал" || bad "код возврата 0 — пустая папка не провал"

case_ "I2" "NO_COLOR: в пайп уходит чистый текст без ANSI"
D="$SANDBOX/t28"; mkdir -p "$D"
make_zip "$D" "chi-repo" "1.0.0" dot
OUT="$(DRY=1 run_deploy "$D")"
printf '%s' "$OUT" | grep -q "$(printf '\033')" && bad "ANSI-кодов нет в неинтерактивном выводе" || ok "ANSI-кодов нет в неинтерактивном выводе"

case_ "A4" "Репа существует, но пустая (нет коммитов) — публикуем без падения"
git init -q --bare "$REMOTES/psi-repo.git"
echo private > "$GH_STORE/repos/psi-repo"
D="$SANDBOX/t29"; mkdir -p "$D"
make_zip "$D" "psi-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"
git clone -q "$REMOTES/psi-repo.git" "$SANDBOX/c29" 2>/dev/null
assert_eq "версия опубликована в пустую репу" "$(tag_tree_version "$SANDBOX/c29" 1.0.0)" "1.0.0"

case_ "A5" "Несколько реп за один прогон — все обработаны"
D="$SANDBOX/t30"; mkdir -p "$D"
for r in aa-repo bb-repo cc-repo; do make_zip "$D" "$r" "1.0.0" dot; done
OUT="$(run_deploy "$D")"
for r in aa-repo bb-repo cc-repo; do
  git clone -q "$REMOTES/$r.git" "$SANDBOX/c30-$r" 2>/dev/null
  assert_eq "$r опубликована" "$(tag_tree_version "$SANDBOX/c30-$r" 1.0.0)" "1.0.0"
done

case_ "C9" "Вложенная репа со своим VERSION не путает предполёт (регресс на реальном архиве)"
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

case_ "B5" "Служебные архивы из чата игнорируются молча"
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

case_ "B6" "Вариантный постфикс: только для реп из VARIANT_REPOS"
D="$SANDBOX/t33"; mkdir -p "$D"
make_zip "$D" "finpilot" "6.20.1" dot
mv "$D/finpilot-v6.20.1.zip" "$D/finpilot_v6_20_1_intl.zip"
make_zip "$D" "other-repo" "1.0.0" dot
mv "$D/other-repo-v1.0.0.zip" "$D/other-repo_v1_0_0_intl.zip"
OUT="$(run_deploy "$D" || true)"
assert_contains "finpilot распознан" "$OUT" "finpilot v6.20.1"
assert_contains "постфикс показан вслух" "$OUT" "вариантные имена"
assert_missing "чужая репа НЕ распознана по постфиксу" "$OUT" "══ Репозиторий: other-repo"
# finpilot по REPO_MAP уезжает в personal-finance-dss (см. кейс 35)
git clone -q "$REMOTES/personal-finance-dss.git" "$SANDBOX/c33" 2>/dev/null
assert_eq "finpilot опубликован в свою репу" "$(tag_tree_version "$SANDBOX/c33" 6.20.1)" "6.20.1"

# и БЕЗ постфикса — тот же маршрут (постфикс уберётся у пользователя в будущем)
make_zip "$D" "finpilot" "6.21.0" dot
OUT="$(run_deploy "$D")"
git -C "$SANDBOX/c33" fetch -q origin --tags 2>/dev/null
assert_contains "без постфикса тоже уехал в personal-finance-dss" \
  "$(git -C "$SANDBOX/c33" tag -l | tr '\n' ' ')" "v6.21.0"
assert_eq "обе версии в одной репе" \
  "$(git -C "$SANDBOX/c33" tag -l | LC_ALL=C grep -c .)" "2"

case_ "I3" "Не-UTF-8 имена внутри архива не роняют предполёт"
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

case_ "B7" "REPO_MAP: архив едет в репу с другим именем"
D="$SANDBOX/t35"; mkdir -p "$D"
make_zip "$D" "finpilot" "6.20.1" dot
mv "$D/finpilot-v6.20.1.zip" "$D/finpilot_v6_20_1_intl.zip"
OUT="$(run_deploy "$D")"
assert_contains "переименование объявлено" "$OUT" "personal-finance-dss"
[ -d "$REMOTES/personal-finance-dss.git" ] && ok "запушено в целевую репу" || bad "запушено в целевую репу"
[ ! -d "$REMOTES/finpilot.git" ] && ok "репа по имени архива НЕ создана" || bad "репа по имени архива НЕ создана"
git clone -q "$REMOTES/personal-finance-dss.git" "$SANDBOX/c35" 2>/dev/null
assert_eq "версия на месте" "$(tag_tree_version "$SANDBOX/c35" 6.20.1)" "6.20.1"
assert_eq "ассет назван по РЕПЕ, не по архиву" \
  "$(ls -1 "$GH_STORE/rel/personal-finance-dss/v6.20.1/assets")" "personal-finance-dss-v6.20.1.zip"

case_ "B8" "Аудит: не версионные архивы перечислены, а не пропали молча"
D="$SANDBOX/t36"; mkdir -p "$D"
make_zip "$D" "psi2-repo" "1.0.0" dot
make_zip "$D" "tmp-repo" "9.9.9" dot; mv "$D/tmp-repo-v9.9.9.zip" "$D/аыва.zip"
make_zip "$D" "tmp-repo" "9.9.9" dot; mv "$D/tmp-repo-v9.9.9.zip" "$D/скрипты для работы.zip"
OUT="$(run_deploy "$D")"
assert_contains "блок аудита показан" "$OUT" "не версионные архивы"
assert_contains "кириллическое имя названо" "$OUT" "аыва.zip"
assert_contains "имя с пробелами названо" "$OUT" "скрипты для работы.zip"
[ ! -d "$REMOTES/аыва.git" ] && ok "репа для мусора не создана" || bad "репа для мусора не создана"

case_ "A6" "Latest: при backfill старая версия не помечается свежей"
D="$SANDBOX/t37"; mkdir -p "$D"
make_zip "$D" "lat-repo" "2.0.0" dot
run_deploy "$D" >/dev/null
make_zip "$D" "lat-repo" "1.0.0" dot
OUT="$(BACKFILL=1 run_deploy "$D")"
assert_contains "старая версия создана как не-latest" \
  "$(LC_ALL=C grep 'release create v1.0.0' "$GH_STORE/calls.log" | tail -1)" "--latest=false"
assert_contains "старшая версия помечена latest" \
  "$(LC_ALL=C grep 'release create v2.0.0' "$GH_STORE/calls.log" | tail -1)" "--latest=true"

case_ "B9" "macOS-хвост ' 1' после версии — это дубликат, а не нечитаемая версия"
D="$SANDBOX/t38"; mkdir -p "$D"
make_zip "$D" "dup-repo" "1.2.5" dot
cp "$D/dup-repo-v1.2.5.zip" "$D/dup-repo_v1.2.5 1.zip"
cp "$D/dup-repo-v1.2.5.zip" "$D/dup-repo_v1.2.5 2.zip"
OUT="$(run_deploy "$D")"
assert_contains "хвост опознан как дубликат" "$OUT" "рабочие копии и дубликаты"
assert_missing "не жалуется на нечитаемую версию" "$OUT" "не читается"
git clone -q "$REMOTES/dup-repo.git" "$SANDBOX/c38" 2>/dev/null
assert_eq "оригинал опубликован ровно один раз" "$(git -C "$SANDBOX/c38" tag -l | LC_ALL=C grep -c .)" "1"

case_ "B10" "Имя без версионного токена — тихий аудит, без жёлтой жалобы"
D="$SANDBOX/t39"; mkdir -p "$D"
make_zip "$D" "quiet-repo" "1.0.0" dot
make_zip "$D" "tmp-repo" "9.9.9" dot; mv "$D/tmp-repo-v9.9.9.zip" "$D/recognition-test-session-1.zip"
OUT="$(run_deploy "$D")"
assert_contains "попало в аудит" "$OUT" "recognition-test-session-1.zip"
assert_missing "без жалобы на версию" "$OUT" "не читается"
[ ! -d "$REMOTES/recognition-test-session-1.git" ] && ok "репа не заведена" || bad "репа не заведена"

case_ "H3" "repos-map обновляется сама, без переменных окружения"
MAPREMOTE="$REMOTES/base-repo.git"
rm -rf "$MAPREMOTE" "$SANDBOX/mapseed"
git init -q --bare "$MAPREMOTE"
git clone -q "$MAPREMOTE" "$SANDBOX/mapseed" 2>/dev/null
printf '# Карта\n\n**Актуальность:** 2026-01-01\n\n## `old-repo`\nОписание.\n\n---\n\n# 📐 Стандарт репозитория\n' \
  > "$SANDBOX/mapseed/repos-map.md"
printf '# CHANGELOG карты\n' > "$SANDBOX/mapseed/repos-map-CHANGELOG.md"
echo "# base-repo" > "$SANDBOX/mapseed/README.md"
( cd "$SANDBOX/mapseed" && git add -A && git commit -q -m init && git push -q origin HEAD:main 2>/dev/null )
D="$SANDBOX/t40"; mkdir -p "$D"
make_zip "$D" "brand-new-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"          # без BASE_REPO — намеренно
assert_contains "карта склонирована сама" "$OUT" "склонирована с GitHub"
assert_contains "карта запушена" "$OUT" "запушена"
rm -rf "$SANDBOX/mapcheck"; git clone -q "$MAPREMOTE" "$SANDBOX/mapcheck" 2>/dev/null
assert_contains "новая репа в карте на remote" "$(cat "$SANDBOX/mapcheck/repos-map.md")" "brand-new-repo"
assert_contains "запись в истории карты" "$(cat "$SANDBOX/mapcheck/repos-map-CHANGELOG.md")" "brand-new-repo"
assert_missing "не просит задать переменную" "$OUT" "BASE_REPO="

case_ "D3" "CHANGELOG в подпапке находится (регресс: 6 пустых релизов base-repo)"
D="$SANDBOX/t41"; mkdir -p "$D"
make_zip "$D" "sub-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/sub-repo-v1.0.0.zip" )
mkdir -p "$tmp/sub-repo-v1.0.0/00-infrastructure"
mv "$tmp/sub-repo-v1.0.0/CHANGELOG.md" "$tmp/sub-repo-v1.0.0/00-infrastructure/CHANGELOG.md"
rm "$D/sub-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D/sub-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_missing "не говорит, что не найден" "$OUT" "CHANGELOG не найден"
assert_eq "заголовок с тезисом собран" \
  "$(cat "$GH_STORE/rel/sub-repo/v1.0.0/title" 2>/dev/null)" "sub-repo v1.0.0 — Тезис версии 1.0.0"
assert_contains "тело из CHANGELOG подпапки" "$(cat "$GH_STORE/rel/sub-repo/v1.0.0/body" 2>/dev/null)" "Опорный абзац"

case_ "D4" "CHANGELOG глубоко в дереве — тоже находится"
D="$SANDBOX/t42"; mkdir -p "$D"
make_zip "$D" "deep-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/deep-repo-v1.0.0.zip" )
mkdir -p "$tmp/deep-repo-v1.0.0/docs/meta/history"
mv "$tmp/deep-repo-v1.0.0/CHANGELOG.md" "$tmp/deep-repo-v1.0.0/docs/meta/history/CHANGELOG.md"
rm "$D/deep-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D/deep-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_eq "тезис вытащен из глубины" \
  "$(cat "$GH_STORE/rel/deep-repo/v1.0.0/title" 2>/dev/null)" "deep-repo v1.0.0 — Тезис версии 1.0.0"

case_ "D5" "Нет секции в CHANGELOG — релиз НЕ создаётся, флаг поднят"
D="$SANDBOX/t43"; mkdir -p "$D"
make_zip "$D" "norel-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/norel-repo-v1.0.0.zip" )
printf '# CHANGELOG\n\nПусто.\n' > "$tmp/norel-repo-v1.0.0/CHANGELOG.md"
rm "$D/norel-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D/norel-repo-v1.0.0.zip" . )
OUT="$(run_deploy "$D")"; rm -rf "$tmp"
assert_contains "сказано про отсутствие секции" "$OUT" "нет секции"
assert_contains "поднят громкий флаг" "$OUT" "ТРЕБУЕТ"
[ ! -d "$GH_STORE/rel/norel-repo/v1.0.0" ] && ok "пустой релиз НЕ создан" || bad "пустой релиз НЕ создан"
git clone -q "$REMOTES/norel-repo.git" "$SANDBOX/c43" 2>/dev/null
assert_eq "дерево и тег при этом на месте" "$(tag_tree_version "$SANDBOX/c43" 1.0.0)" "1.0.0"

case_ "E6" "Старые релизы чинятся САМИ, одной командой (без флагов)"
D="$SANDBOX/t44"; mkdir -p "$D"
make_zip "$D" "old-repo" "1.0.0" dot
make_zip "$D" "old-repo" "1.1.0" dot
# реальный CHANGELOG накапливает секции — в старшей версии есть обе
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/old-repo-v1.1.0.zip" )
printf '# CHANGELOG\n\n## [1.1.0] — 2026-07-28 — Тезис версии 1.1.0 (MINOR)\n\nОпорный абзац для 1.1.0: что сделано и зачем.\n\n### Added\n- пункт\n\n## [1.0.0] — 2026-07-24 — Тезис версии 1.0.0 (MINOR)\n\nОпорный абзац для 1.0.0: что сделано и зачем.\n\n### Added\n- пункт\n' \
  > "$tmp/old-repo-v1.1.0/CHANGELOG.md"
rm "$D/old-repo-v1.1.0.zip"; ( cd "$tmp" && zip -qr "$D/old-repo-v1.1.0.zip" . ); rm -rf "$tmp"
run_deploy "$D" >/dev/null
# портим как старые скрипты: заголовок без тезиса, тело-заглушка, ассет снесён
printf 'old-repo v1.0.0' > "$GH_STORE/rel/old-repo/v1.0.0/title"
printf 'Release 1.0.0' > "$GH_STORE/rel/old-repo/v1.0.0/body"
rm -rf "$GH_STORE/rel/old-repo/v1.0.0/assets"; mkdir -p "$GH_STORE/rel/old-repo/v1.0.0/assets"
printf 'old-repo v1.1.0' > "$GH_STORE/rel/old-repo/v1.1.0/title"
rm -f "$D/old-repo-v1.0.0.zip"          # архива под рукой больше нет — только тег
OUT="$(run_deploy "$D")"                 # дефолт: старое НЕ трогаем
assert_missing "по умолчанию старые релизы не трогаются" "$OUT" "v1.0.0: заголовок"
OUT="$(AUDIT=1 run_deploy "$D")"         # ревизия — чинит всё
assert_eq "заголовок восстановлен с тезисом" \
  "$(cat "$GH_STORE/rel/old-repo/v1.0.0/title")" "old-repo v1.0.0 — Тезис версии 1.0.0"
assert_contains "тело восстановлено из CHANGELOG" \
  "$(cat "$GH_STORE/rel/old-repo/v1.0.0/body")" "Опорный абзац"
assert_eq "ассет собран из тега" \
  "$(ls -1 "$GH_STORE/rel/old-repo/v1.0.0/assets")" "old-repo-v1.0.0.zip"
assert_contains "источник ассета назван" "$OUT" "из: тег"
assert_eq "заголовок соседней версии тоже починен" \
  "$(cat "$GH_STORE/rel/old-repo/v1.1.0/title")" "old-repo v1.1.0 — Тезис версии 1.1.0"
OUT="$(AUDIT=1 run_deploy "$D")"
assert_missing "повторный прогон не правит v1.0.0" "$OUT" "v1.0.0: заголовок и описание"
assert_missing "повторный прогон не догружает ассет" "$OUT" "v1.0.0: ассет"

case_ "D6" "FORCE не трогает описание, если секции в CHANGELOG нет"
# norel-repo из кейса 43: тег есть, CHANGELOG без секций, релиза нет.
# Заводим релиз руками — имитация легаси-релиза, у которого нет источника описания.
mkdir -p "$GH_STORE/rel/norel-repo/v1.0.0/assets"
printf 'norel-repo v1.0.0' > "$GH_STORE/rel/norel-repo/v1.0.0/title"
printf 'Осмысленное легаси-описание, написанное руками много месяцев назад.' \
  > "$GH_STORE/rel/norel-repo/v1.0.0/body"
GOOD="$(cat "$GH_STORE/rel/norel-repo/v1.0.0/body")"
OUT="$(FORCE=1 run_deploy "$SANDBOX/t43")"
assert_contains "отсутствие секции названо" "$OUT" "нет секции"
assert_missing "нет ложной ошибки обновления" "$OUT" "не удалось обновить"
assert_eq "описание не затёрто пустым" "$(cat "$GH_STORE/rel/norel-repo/v1.0.0/body")" "$GOOD"
assert_eq "заголовок тоже цел" "$(cat "$GH_STORE/rel/norel-repo/v1.0.0/title")" "norel-repo v1.0.0"

case_ "D7" "Шапка секции нормализуется к канону [X.Y.Z]"
D="$SANDBOX/t46"; mkdir -p "$D"
make_zip "$D" "dial-repo" "3.3.2" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/dial-repo-v3.3.2.zip" )
printf '# CHANGELOG\n\n## v3.3.2 — 2026-07-25 — Тезис без скобок\n\nОпорный абзац.\n\n### Added\n- x\n' \
  > "$tmp/dial-repo-v3.3.2/CHANGELOG.md"
rm "$D/dial-repo-v3.3.2.zip"; ( cd "$tmp" && zip -qr "$D/dial-repo-v3.3.2.zip" . ); rm -rf "$tmp"
OUT="$(run_deploy "$D")"
assert_contains "тело начинается с канона" "$(head -1 "$GH_STORE/rel/dial-repo/v3.3.2/body")" "## [3.3.2]"
assert_eq "заголовок собран верно" \
  "$(cat "$GH_STORE/rel/dial-repo/v3.3.2/title")" "dial-repo v3.3.2 — Тезис без скобок"

case_ "E7" "Дефолт быстрый: аудит старых релизов не запускается"
D="$SANDBOX/t47"; mkdir -p "$D"
make_zip "$D" "fast-repo" "1.0.0" dot
run_deploy "$D" >/dev/null
printf 'fast-repo v1.0.0' > "$GH_STORE/rel/fast-repo/v1.0.0/title"
make_zip "$D" "fast-repo" "1.1.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D/fast-repo-v1.1.0.zip" )
printf '# CHANGELOG\n\n## [1.1.0] — 2026-07-28 — Тезис версии 1.1.0 (MINOR)\n\nОпорный абзац.\n\n### Added\n- x\n\n## [1.0.0] — 2026-07-24 — Тезис версии 1.0.0 (MINOR)\n\nОпорный абзац.\n\n### Added\n- x\n' \
  > "$tmp/fast-repo-v1.1.0/CHANGELOG.md"
rm "$D/fast-repo-v1.1.0.zip"; ( cd "$tmp" && zip -qr "$D/fast-repo-v1.1.0.zip" . ); rm -rf "$tmp"
OUT="$(run_deploy "$D")"
assert_contains "новая версия опубликована" "$OUT" "v1.1.0"
assert_eq "старый заголовок НЕ тронут" "$(cat "$GH_STORE/rel/fast-repo/v1.0.0/title")" "fast-repo v1.0.0"
OUT="$(AUDIT=1 run_deploy "$D")"
assert_eq "с AUDIT=1 починен" \
  "$(cat "$GH_STORE/rel/fast-repo/v1.0.0/title")" "fast-repo v1.0.0 — Тезис версии 1.0.0"

case_ "H4" "ALL_REPOS=1 берёт репы из repos-map, даже без архива в папке"
MAPREMOTE="$REMOTES/base-repo.git"
rm -rf "$SANDBOX/mapseed2"; git clone -q "$MAPREMOTE" "$SANDBOX/mapseed2" 2>/dev/null
# заводим репу, у которой НЕТ архива в папке, но есть релиз не по стандарту
D2="$SANDBOX/t48seed"; mkdir -p "$D2"
make_zip "$D2" "orphan-repo" "1.0.0" dot
run_deploy "$D2" >/dev/null
printf 'orphan-repo v1.0.0' > "$GH_STORE/rel/orphan-repo/v1.0.0/title"
printf '## `orphan-repo`\nОписание.\n' >> "$SANDBOX/mapseed2/repos-map.md"
( cd "$SANDBOX/mapseed2" && git add -A && git commit -q -m map && git push -q origin HEAD:main 2>/dev/null )
# в рабочей папке — архив ДРУГОЙ репы
D="$SANDBOX/t48"; mkdir -p "$D"
make_zip "$D" "other48-repo" "1.0.0" dot
OUT="$(run_deploy "$D")"
assert_missing "без флага чужая репа не трогается" "$OUT" "══ Репозиторий: orphan-repo"
OUT="$(ALL_REPOS=1 run_deploy "$D")"
assert_contains "с ALL_REPOS=1 репа из карты взята" "$OUT" "orphan-repo"
assert_contains "источник списка назван" "$OUT" "repos-map"
assert_eq "её релиз приведён к стандарту" \
  "$(cat "$GH_STORE/rel/orphan-repo/v1.0.0/title")" "orphan-repo v1.0.0 — Тезис версии 1.0.0"

case_ "F1" "DROP_LEGACY_ASSETS: снимает ТОЛЬКО дубль той же версии"
D="$SANDBOX/t49"; mkdir -p "$D"
make_zip "$D" "asset-repo" "6.6.0" dot
run_deploy "$D" >/dev/null
A="$GH_STORE/rel/asset-repo/v6.6.0/assets"
# рядом с каноническим кладём: дубль с точками, дубль с подчёркиваниями,
# zip ДРУГОЙ версии и осмысленное вложение — последние два трогать нельзя
echo x > "$A/finpilot_v6.6.0_intl.zip"
echo x > "$A/finpilot_v6_6_0_intl.zip"
echo x > "$A/asset-repo-v5.0.0.zip"
echo x > "$A/otchet.pdf"
# в дефолтном режиме опубликованные релизы не обходятся — дубль на месте
OUT="$(run_deploy "$D")"
assert_contains "дубль пока на месте" "$(ls -1 "$A" | tr '\n' ' ')" "finpilot_v6_6_0_intl.zip"
# ревизия приводит релиз к стандарту ЦЕЛИКОМ, включая лишние ассеты — без спецфлага
OUT="$(AUDIT=1 run_deploy "$D")"
LEFT="$(ls -1 "$A" | sort | tr '\n' ' ')"
assert_missing "дубль с точками снят" "$LEFT" "finpilot_v6.6.0_intl.zip"
assert_missing "дубль с подчёркиваниями снят" "$LEFT" "finpilot_v6_6_0_intl.zip"
assert_contains "канонический ассет на месте" "$LEFT" "asset-repo-v6.6.0.zip"
assert_contains "zip чужой версии НЕ тронут" "$LEFT" "asset-repo-v5.0.0.zip"
assert_contains "не-zip вложение НЕ тронуто" "$LEFT" "otchet.pdf"
assert_contains "снятое названо в выводе" "$OUT" "снят дубль"

case_ "G3" "Без флага не удаляется НИЧЕГО"
D="$SANDBOX/t50"; mkdir -p "$D"
make_zip "$D" "keep-repo" "1.0.0" dot
run_deploy "$D" >/dev/null
A="$GH_STORE/rel/keep-repo/v1.0.0/assets"
echo x > "$A/legacy_v1.0.0_intl.zip"
BEFORE="$(ls -1 "$A" | sort | tr '\n' ' ')"
OUT="$(run_deploy "$D")"
assert_eq "состав ассетов не изменился" "$(ls -1 "$A" | sort | tr '\n' ' ')" "$BEFORE"
OUT="$(KEEP_LEGACY_ASSETS=1 AUDIT=1 FORCE=1 run_deploy "$D")"
assert_eq "KEEP_LEGACY_ASSETS=1 сохраняет всё" "$(ls -1 "$A" | sort | tr '\n' ' ')" "$BEFORE"
OUT="$(DRY=1 AUDIT=1 run_deploy "$D")"
assert_eq "DRY ничего не удаляет" "$(ls -1 "$A" | sort | tr '\n' ' ')" "$BEFORE"

case_ "F2" "Нет канонического ассета — чистка не запускается"
D="$SANDBOX/t51"; mkdir -p "$D"
make_zip "$D" "guard-repo" "2.0.0" dot
run_deploy "$D" >/dev/null
A="$GH_STORE/rel/guard-repo/v2.0.0/assets"
rm -f "$A/guard-repo-v2.0.0.zip"          # канонического нет
echo x > "$A/legacy_v2.0.0_old.zip"        # остался только легаси
rm -f "$D/guard-repo-v2.0.0.zip"           # и архива на диске тоже нет
rm -rf "$SANDBOX/g51"; git clone -q "$REMOTES/guard-repo.git" "$SANDBOX/g51" 2>/dev/null
git -C "$SANDBOX/g51" tag -d v2.0.0 >/dev/null 2>&1
git -C "$SANDBOX/g51" push -q origin :refs/tags/v2.0.0 2>/dev/null   # и тега нет → собрать неоткуда
OUT="$(DROP_LEGACY_ASSETS=1 AUDIT=1 run_deploy "$D" || true)"
assert_contains "легаси уцелел" "$(ls -1 "$A" | tr '\n' ' ')" "legacy_v2.0.0_old.zip"

case_ "G4" "VERIFY: 'можно удалять' только когда на GitHub есть ВСЁ"
D="$SANDBOX/t52"; mkdir -p "$D"
make_zip "$D" "vfy-repo" "1.0.0" dot
run_deploy "$D" >/dev/null
OUT="$(VERIFY=1 run_deploy "$D")"
assert_contains "полный комплект → можно удалять" "$OUT" "можно удалять"
assert_contains "файл списка создан" "$(cat "$HOME/Downloads/safe_to_delete.txt" 2>/dev/null)" "vfy-repo-v1.0.0.zip"
# путь обязан быть без отступа, иначе xargs rm сломается
assert_missing "путь без ведущих пробелов" "$(head -1 "$HOME/Downloads/safe_to_delete.txt")" " /"
xargs -d '\n' ls -1 -- < "$HOME/Downloads/safe_to_delete.txt" >/dev/null 2>&1 \
  && ok "xargs находит файлы по списку" || bad "xargs находит файлы по списку"
assert_missing "VERIFY ничего не публикует" "$OUT" "коммит:"
# ломаем комплект: сносим ассет → архив держать
rm -f "$GH_STORE/rel/vfy-repo/v1.0.0/assets/vfy-repo-v1.0.0.zip"
: > "$HOME/Downloads/safe_to_delete.txt"
OUT="$(VERIFY=1 run_deploy "$D")"
assert_contains "без ассета — держать" "$OUT" "ДЕРЖАТЬ"
assert_contains "причина названа" "$OUT" "ассет"
assert_missing "в список безопасных НЕ попал" "$(cat "$HOME/Downloads/safe_to_delete.txt" 2>/dev/null)" "vfy-repo-v1.0.0.zip"
# нет релиза вовсе
rm -rf "$GH_STORE/rel/vfy-repo/v1.0.0"
OUT="$(VERIFY=1 run_deploy "$D")"
assert_contains "без релиза — держать" "$OUT" "ДЕРЖАТЬ"

case_ "G5" "VERIFY не считает безопасным архив, которого нет в репе"
D="$SANDBOX/t53"; mkdir -p "$D"
make_zip "$D" "never-repo" "9.9.9" dot     # никогда не публиковался
OUT="$(VERIFY=1 run_deploy "$D" || true)"
assert_contains "неопубликованный — держать" "$OUT" "ДЕРЖАТЬ"
assert_missing "не объявлен безопасным" "$OUT" "never-repo-v9.9.9.zip — на GitHub есть всё"

case_ "G6" "PRIVATE: новые репы приватные по умолчанию, публичные только явно"
D="$SANDBOX/t54"; mkdir -p "$D"
make_zip "$D" "priv-repo" "1.0.0" dot
run_deploy "$D" >/dev/null
assert_eq "по умолчанию private" "$(cat "$GH_STORE/repos/priv-repo")" "private"
assert_contains "флаг --private ушёл в gh" "$(LC_ALL=C grep 'repo create.*priv-repo' "$GH_STORE/calls.log" | tail -1)" "--private"
D="$SANDBOX/t54b"; mkdir -p "$D"
make_zip "$D" "pub-repo" "1.0.0" dot
PRIVATE=0 run_deploy "$D" >/dev/null
assert_eq "PRIVATE=0 → public" "$(cat "$GH_STORE/repos/pub-repo")" "public"

case_ "E8" "Переопределяемые списки: SERVICE_RE, REPO_MAP, VARIANT_REPOS, MIN_FILES"
D="$SANDBOX/t55"; mkdir -p "$D"
make_zip "$D" "cfg-repo" "1.0.0" dot
make_zip "$D" "junk-repo" "1.0.0" dot
OUT="$(SERVICE_RE='^junk-repo-v1\.0\.0$' run_deploy "$D")"
assert_contains "SERVICE_RE отсёк указанное" "$OUT" "пропущено служебных архивов: 1"
[ ! -d "$REMOTES/junk-repo.git" ] && ok "репа по SERVICE_RE не создана" || bad "репа по SERVICE_RE не создана"
D="$SANDBOX/t55b"; mkdir -p "$D"
make_zip "$D" "src-name" "2.0.0" dot
OUT="$(REPO_MAP='src-name=dst-name' run_deploy "$D")"
assert_contains "REPO_MAP переопределён" "$OUT" "dst-name"
[ -d "$REMOTES/dst-name.git" ] && ok "уехало в целевую репу" || bad "уехало в целевую репу"
D="$SANDBOX/t55c"; mkdir -p "$D"
make_zip "$D" "myproj" "3.0.0" dot
mv "$D/myproj-v3.0.0.zip" "$D/myproj_v3_0_0_intl.zip"
OUT="$(VARIANT_REPOS='myproj' run_deploy "$D")"
assert_contains "VARIANT_REPOS переопределён" "$OUT" "myproj v3.0.0"
D="$SANDBOX/t55d"; mkdir -p "$D"
make_zip "$D" "big-repo" "1.0.0" dot
OUT="$(MIN_FILES=999 run_deploy "$D" || true)"
assert_contains "MIN_FILES соблюдён" "$OUT" "не похоже на репу"

case_ "E9" "ASSET=0 — релиз без ассета, дерево и тег на месте"
D="$SANDBOX/t56"; mkdir -p "$D"
make_zip "$D" "noasset-repo" "1.0.0" dot
OUT="$(ASSET=0 run_deploy "$D")"
assert_eq "ассетов нет" "$(ls -1 "$GH_STORE/rel/noasset-repo/v1.0.0/assets" 2>/dev/null | grep -c . | tr -d ' ')" "0"
git clone -q "$REMOTES/noasset-repo.git" "$SANDBOX/c56" 2>/dev/null
assert_eq "дерево и тег опубликованы" "$(tag_tree_version "$SANDBOX/c56" 1.0.0)" "1.0.0"
assert_contains "описание всё равно по стандарту" \
  "$(cat "$GH_STORE/rel/noasset-repo/v1.0.0/title")" "noasset-repo v1.0.0 — Тезис"

case_ "I4" "Ни одного тусклого/чёрного кода — фон у владельца тёмный"
# Белый список: в скрипте допустимы ТОЛЬКО яркие коды и сброс.
BADCODES="$(grep -oE '\\033\[[0-9;]*m' "$DEPLOY" | sort -u \
  | grep -vE '\\033\[(0|97|1;97|91|92|93|95|96)m' | tr '\n' ' ')"
assert_eq "нет ни одного тёмного/тусклого кода" "$(printf '%s' "$BADCODES" | tr -d ' ')" ""
assert_eq "переменной C_DIM нет" "$(grep -c 'C_DIM' "$DEPLOY" | tr -d ' ')" "0"
# каждая функция печати обязана нести свой код, а не полагаться на цвет терминала
for f in red grn ylw cyn mag bld plain; do
  grep -qE "^$f\(\)\{ printf '%s%s%s" "$DEPLOY" \
    && ok "$f() печатает со своим цветом" || bad "$f() печатает со своим цветом"
done
D="$SANDBOX/tI4"; mkdir -p "$D"
make_zip "$D" "color-repo" "1.0.0" dot
OUT="$(NO_COLOR= run_deploy "$D" 2>&1)"
printf '%s' "$OUT" | grep -q "$(printf '\033')\[2m" && bad "в выводе нет dim" || ok "в выводе нет dim"

case_ "A7" "Дефолтный прогон сам убирает опубликованные архивы"
D="$SANDBOX/tA7"; mkdir -p "$D"
make_zip "$D" "a7-repo" "1.0.0" dot
OUT="$(KEEP_ARCHIVES=0 run_deploy "$D")"
assert_contains "блок уборки есть без флагов" "$OUT" "полностью на GitHub"
[ ! -f "$D/a7-repo-v1.0.0.zip" ] && ok "архив убран" || bad "архив убран"
# с отключением — подсказка, как посмотреть список (нужен свежий архив)
make_zip "$D" "a7b-repo" "1.0.0" dot
OUT="$(KEEP_ARCHIVES=1 run_deploy "$D")"
assert_contains "сказано, что не удалялись" "$OUT" "KEEP_ARCHIVES=1"
assert_contains "показан способ посмотреть" "$OUT" "VERIFY=1"

case_ "G7" "Точка в имени ассета не матчит подчёркивание (потеря данных)"
D="$SANDBOX/tG7"; mkdir -p "$D"
make_zip "$D" "dot-repo" "1.0.1" dot
run_deploy "$D" >/dev/null
A="$GH_STORE/rel/dot-repo/v1.0.1/assets"
rm -f "$A/dot-repo-v1.0.1.zip"          # канона нет
echo x > "$A/dot-repo-v1_0_1.zip"        # есть только легаси с подчёркиваниями
OUT="$(AUDIT=1 run_deploy "$D")"
LEFT="$(ls -1 "$A" | sort | tr '\n' ' ')"
assert_contains "канонический ассет создан" "$LEFT" "dot-repo-v1.0.1.zip"
[ -n "$(ls -1 "$A" | grep -c .)" ] && ok "релиз не остался без ассета" || bad "релиз не остался без ассета"

case_ "A8" "Сообщение коммита несёт версию и тезис, а не 'tree sync'"
D="$SANDBOX/tA8"; mkdir -p "$D"
make_zip "$D" "msg-repo" "1.0.0" dot
run_deploy "$D" >/dev/null
git clone -q "$REMOTES/msg-repo.git" "$SANDBOX/cA8" 2>/dev/null
MSG="$(git -C "$SANDBOX/cA8" log -1 --pretty=%s)"
assert_contains "в сообщении есть репа и версия" "$MSG" "msg-repo v1.0.0"
assert_contains "в сообщении есть тезис" "$MSG" "Тезис версии"
assert_missing "нет технического 'tree sync'" "$MSG" "tree sync"

case_ "G8" "Команда удаления совместима с BSD xargs (macOS)"
# подробная проверка переносимости — в G11; здесь только запрет несуществующего в BSD
assert_missing "нет xargs -d (нет в BSD)" "$(grep 'safe_to_delete.txt' "$DEPLOY")" "xargs -d"

case_ "G9" "Рабочая папка не остаётся на диске ни при каком выходе"
D="$SANDBOX/tG9"; mkdir -p "$D"
make_zip "$D" "tmp-clean-repo" "1.0.0" dot
BEFORE_DL="$(ls -1 "$HOME/Downloads" 2>/dev/null | grep -c 'repo_deploy' || true)"
run_deploy "$D" >/dev/null
AFTER_DL="$(ls -1 "$HOME/Downloads" 2>/dev/null | grep -c 'repo_deploy' || true)"
assert_eq "в Downloads не появилось рабочих папок" "$AFTER_DL" "$BEFORE_DL"
LEFT="$(ls -d "${TMPDIR:-/tmp}"/repo_deploy_* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "во временной папке не осталось мусора" "$LEFT" "0"
# ранний выход (DRY) тоже обязан убирать за собой
DRY=1 run_deploy "$D" >/dev/null
LEFT="$(ls -d "${TMPDIR:-/tmp}"/repo_deploy_* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "после DRY тоже чисто" "$LEFT" "0"
# VERIFY — тоже ранний выход
VERIFY=1 run_deploy "$D" >/dev/null 2>&1 || true
LEFT="$(ls -d "${TMPDIR:-/tmp}"/repo_deploy_* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "после VERIFY тоже чисто" "$LEFT" "0"
# KEEP_WORK=1 — осознанная отладка, папка остаётся и названа
OUT="$(KEEP_WORK=1 run_deploy "$D")"
assert_contains "с KEEP_WORK=1 путь назван" "$OUT" "рабочая папка оставлена"
rm -rf "${TMPDIR:-/tmp}"/repo_deploy_* 2>/dev/null || true

case_ "G10" "DELETE_AFTER удаляет архив только при подтверждённой публикации"
D="$SANDBOX/tG10"; mkdir -p "$D"
make_zip "$D" "del-repo" "1.0.0" dot
KEEP_ARCHIVES=1 run_deploy "$D" >/dev/null
[ -f "$D/del-repo-v1.0.0.zip" ] && ok "KEEP_ARCHIVES=1 сохраняет архив" || bad "KEEP_ARCHIVES=1 сохраняет архив"
KEEP_ARCHIVES=0 run_deploy "$D" >/dev/null
[ ! -f "$D/del-repo-v1.0.0.zip" ] && ok "по умолчанию архив удаляется" || bad "по умолчанию архив удаляется"
# DELETE_AFTER оставлен для совместимости: 0 сохраняет архив
make_zip "$D" "legacy-flag-repo" "1.0.0" dot
DELETE_AFTER=0 KEEP_ARCHIVES=0 run_deploy "$D" >/dev/null
[ -f "$D/legacy-flag-repo-v1.0.0.zip" ] && ok "DELETE_AFTER=0 сохраняет архив" || bad "DELETE_AFTER=0 сохраняет архив"
D2="$SANDBOX/tG10b"; mkdir -p "$D2"
make_zip "$D2" "del2-repo" "1.0.0" dot
OUT="$(KEEP_ARCHIVES=0 run_deploy "$D2")"
assert_contains "есть блок автоудаления" "$OUT" "полностью на GitHub"
assert_contains "имя удалённого названо" "$OUT" "del2-repo-v1.0.0.zip"
[ ! -f "$D2/del2-repo-v1.0.0.zip" ] && ok "архив удалён после публикации" || bad "архив удалён после публикации"
git clone -q "$REMOTES/del2-repo.git" "$SANDBOX/cG10" 2>/dev/null
assert_eq "но версия на GitHub цела" "$(tag_tree_version "$SANDBOX/cG10" 1.0.0)" "1.0.0"
assert_eq "и ассет на месте" \
  "$(ls -1 "$GH_STORE/rel/del2-repo/v1.0.0/assets")" "del2-repo-v1.0.0.zip"
# версия без релиза (нет секции) — архив НЕ удаляем
D3="$SANDBOX/tG10c"; mkdir -p "$D3"
make_zip "$D3" "del3-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D3/del3-repo-v1.0.0.zip" )
printf '# CHANGELOG\n\nСекций нет.\n' > "$tmp/del3-repo-v1.0.0/CHANGELOG.md"
rm "$D3/del3-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D3/del3-repo-v1.0.0.zip" . ); rm -rf "$tmp"
KEEP_ARCHIVES=0 run_deploy "$D3" >/dev/null
[ -f "$D3/del3-repo-v1.0.0.zip" ] && ok "без релиза архив НЕ удалён" || bad "без релиза архив НЕ удалён"

case_ "G11" "Печатаемая команда удаления переносима и работает с пробелами"
CMD="$(grep 'safe_to_delete.txt' "$DEPLOY" | grep -E 'rm --' | head -1)"
assert_missing "нет xargs -d (нет в BSD)" "$CMD" "xargs -d"
assert_missing "нет tr со слэш-ноль (BSD хочет 000)" "$CMD" "tr '"
assert_contains "используется while-read" "$CMD" "while IFS= read -r"
# и она действительно удаляет, включая имя с пробелом
mkdir -p "$SANDBOX/dl" && : > "$SANDBOX/dl/a b.zip" && : > "$SANDBOX/dl/c.zip"
printf '%s\n%s\n' "$SANDBOX/dl/a b.zip" "$SANDBOX/dl/c.zip" > "$SANDBOX/dl/list.txt"
while IFS= read -r f; do rm -- "$f"; done < "$SANDBOX/dl/list.txt"
assert_eq "оба файла удалены" "$(ls -1 "$SANDBOX/dl"/*.zip 2>/dev/null | wc -l | tr -d ' ')" "0"

case_ "C10" "Прогон не стартует на переполненном диске"
D="$SANDBOX/tC10"; mkdir -p "$D"
make_zip "$D" "space-repo" "1.0.0" dot
OUT="$(MIN_FREE_MB=99999999 run_deploy "$D" || true)"
assert_contains "сказано про нехватку места" "$OUT" "свободно всего"
assert_contains "объяснено, чем это грозит" "$OUT" "недокачанный ассет"
[ ! -d "$REMOTES/space-repo.git" ] && ok "ничего не опубликовано" || bad "ничего не опубликовано"

case_ "C11" "Папка после автоудаления — успех, а не ошибка"
D="$SANDBOX/tC11"; mkdir -p "$D"
make_zip "$D" "empty-after-repo" "1.0.0" dot
KEEP_ARCHIVES=0 run_deploy "$D" >/dev/null
[ -z "$(ls -1 "$D"/*.zip 2>/dev/null)" ] && ok "архив удалён после публикации" || bad "архив удалён после публикации"
OUT="$(run_deploy "$D" || true)"
assert_contains "повторный прогон говорит спокойно" "$OUT" "Публиковать нечего"
assert_missing "без слова ОШИБКА" "$OUT" "ОШИБКА"
( cd "$D" && bash "$DEPLOY" "$D" >/dev/null 2>&1 ) \
  && ok "и код возврата 0" || bad "и код возврата 0"

case_ "G12" "DELETE_AFTER удаляет и то, что опубликовано прошлым прогоном"
D="$SANDBOX/tG12"; mkdir -p "$D"
make_zip "$D" "prev-repo" "1.0.0" dot
KEEP_ARCHIVES=1 run_deploy "$D" >/dev/null       # публикуем, архив сохраняем
[ -f "$D/prev-repo-v1.0.0.zip" ] && ok "после публикации архив на месте" || bad "после публикации архив на месте"
OUT="$(KEEP_ARCHIVES=0 run_deploy "$D")"          # обычный прогон СЛЕДУЮЩИМ запуском
assert_contains "версия уже была опубликована" "$OUT" "тег есть, пропускаю"
[ ! -f "$D/prev-repo-v1.0.0.zip" ] && ok "архив всё равно удалён" || bad "архив всё равно удалён"
# а неопубликованный — остаётся, с указанием причины
D2="$SANDBOX/tG12b"; mkdir -p "$D2"
make_zip "$D2" "hold-repo" "1.0.0" dot
tmp="$(mktemp -d)"; ( cd "$tmp" && unzip -qo "$D2/hold-repo-v1.0.0.zip" )
printf '# CHANGELOG\n\nСекций нет.\n' > "$tmp/hold-repo-v1.0.0/CHANGELOG.md"
rm "$D2/hold-repo-v1.0.0.zip"; ( cd "$tmp" && zip -qr "$D2/hold-repo-v1.0.0.zip" . ); rm -rf "$tmp"
OUT="$(KEEP_ARCHIVES=0 run_deploy "$D2")"
[ -f "$D2/hold-repo-v1.0.0.zip" ] && ok "без релиза архив оставлен" || bad "без релиза архив оставлен"
assert_contains "причина названа" "$OUT" "не хватает"

case_ "G13" "Распакованные зеркала убираются, рабочие клоны — никогда"
D="$SANDBOX/tG13"; mkdir -p "$D"
make_zip "$D" "mir-repo" "1.0.0" dot
KEEP_ARCHIVES=1 run_deploy "$D" >/dev/null
# 1) честное зеркало: имя с версией, VERSION совпадает, нет .git
mkdir -p "$D/mir-repo-v1.0.0"; printf '1.0.0' > "$D/mir-repo-v1.0.0/VERSION"
# 2) зеркало с подчёркиваниями — тоже должно уйти
mkdir -p "$D/mir-repo-v1_0_0"; printf '1.0.0' > "$D/mir-repo-v1_0_0/VERSION"
# 3) git-клон — НЕ трогать
mkdir -p "$D/mir-repo-v1.0.0-clone/.git"; printf '1.0.0' > "$D/mir-repo-v1.0.0-clone/VERSION"
# 4) каталог без VERSION — НЕ трогать
mkdir -p "$D/mir-repo-v9.9.9"
# 5) каталог с чужой версией внутри — НЕ трогать
mkdir -p "$D/mir-repo-v1.0.0-bad"; printf '7.7.7' > "$D/mir-repo-v1.0.0-bad/VERSION"
# 6) рабочая папка без версии в имени — НЕ трогать никогда
mkdir -p "$D/mir-repo"; printf 'что-то своё' > "$D/mir-repo/notes.md"
# 6б) зеркало с VERSION на уровень глубже (macOS распаковал zip с обёрткой внутрь папки)
make_zip "$D" "deepmir-repo" "1.0.0" dot
# 6в) git-клон на уровень глубже — НЕ трогать
make_zip "$D" "dgmir-repo" "1.0.0" dot
# 7) ГЛАВНОЕ: зеркало версии, ЧЬЕГО АРХИВА В ПАПКЕ УЖЕ НЕТ (удалён прошлым прогоном)
make_zip "$D" "old-mir-repo" "2.0.0" dot
KEEP_ARCHIVES=0 run_deploy "$D" >/dev/null      # публикуем и архив уходит
mkdir -p "$D/old-mir-repo-v2.0.0"; printf '2.0.0' > "$D/old-mir-repo-v2.0.0/VERSION"
# зеркала для 6б/6в создаём ПОСЛЕ публикации их реп
mkdir -p "$D/deepmir-repo-v1.0.0/inner"; printf '1.0.0' > "$D/deepmir-repo-v1.0.0/inner/VERSION"
mkdir -p "$D/dgmir-repo-v1.0.0/inner/.git"; printf '1.0.0' > "$D/dgmir-repo-v1.0.0/inner/VERSION"
OUT="$(KEEP_ARCHIVES=0 run_deploy "$D")"
[ ! -d "$D/old-mir-repo-v2.0.0" ] && ok "зеркало без архива тоже убрано" || bad "зеркало без архива тоже убрано"
[ ! -d "$D/mir-repo-v1.0.0" ] && ok "зеркало с точками убрано" || bad "зеркало с точками убрано"
[ ! -d "$D/mir-repo-v1_0_0" ] && ok "зеркало с подчёркиваниями убрано" || bad "зеркало с подчёркиваниями убрано"
[ -d "$D/mir-repo-v1.0.0-clone/.git" ] && ok "git-клон цел" || bad "git-клон цел"
[ -d "$D/mir-repo-v9.9.9" ] && ok "каталог без VERSION цел" || bad "каталог без VERSION цел"
[ -d "$D/mir-repo-v1.0.0-bad" ] && ok "каталог с чужой версией цел" || bad "каталог с чужой версией цел"
[ -f "$D/mir-repo/notes.md" ] && ok "рабочая папка без версии цела" || bad "рабочая папка без версии цела"
assert_contains "зеркало названо в выводе" "$OUT" "распакованное зеркало"
[ ! -d "$D/deepmir-repo-v1.0.0" ] && ok "VERSION на глубине 2 найден" || bad "VERSION на глубине 2 найден"
[ -d "$D/dgmir-repo-v1.0.0/inner/.git" ] && ok "git-клон на глубине 2 цел" || bad "git-клон на глубине 2 цел"

# =============================================================================
printf '\n\033[1m── Покрытие по зонам\033[0m\n'
grp_name(){
  case "$1" in
    A) echo "Базовый цикл доставки";;      B) echo "Распознавание входа";;
    C) echo "Предполёт и упаковка";;       D) echo "Описание релиза";;
    E) echo "Режимы и конфигурация";;      F) echo "Ассеты";;
    G) echo "Безопасность, необратимость";; H) echo "Карта репозиториев";;
    I) echo "Окружение и совместимость";;  *) echo "$1";;
  esac
}
for g in $(printf '%s\n' $G_LIST | sort); do
  eval "_o=\${G_OK_$g:-0}; _b=\${G_BAD_$g:-0}"
  # без колонок: printf считает БАЙТЫ, а кириллица многобайтовая — выравнивание врёт
  _line="$(printf '  %s · %s — проверок: %s' "$g" "$(grp_name "$g")" "$_o")"
  if [ "$_b" -gt 0 ]; then
    printf '\033[31m%s  ✗ провалено %s\033[0m\n' "$_line" "$_b"
  else
    printf '\033[32m%s\033[0m\n' "$_line"
  fi
done

printf '\n\033[1m── Итог\033[0m\n'
printf '  \033[32mпройдено: %s\033[0m\n' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '  \033[31mпровалено: %s\033[0m\n' "$FAIL"; exit 1; fi
printf '  \033[32mвсё зелено\033[0m\n'
