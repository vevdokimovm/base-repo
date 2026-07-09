#!/usr/bin/env python3
"""revision_check.py — runnable-гейт ревизии knowledge-репы (stdlib-only).

Автоматизированная часть протокола ревизии (21-revision-protocol.md).
Идея перенесена из FINPILOT (tools/revision/revision_check.py): часть осей
ревизии проверяется скриптом за секунды, а не глазами за час. Exit 0 = CLEAN
(или только warnings), exit 1 = DRIFT (есть FAIL; с --strict валят и warnings).

Проверки:
  1. Битые относительные ссылки в ЖИВЫХ .md (замороженные зоны пропускаются:
     история не переписывается — 21-revision-protocol.md §1).
  2. Порча имён `#Uxxxx` (Info-ZIP без UTF-8 флага — PIT-009) -> FAIL.
  3. Крупные файлы: > WARN_FILE_MB -> warning, > FAIL_FILE_MB -> FAIL
     (жёсткий лимит GitHub 100 МБ на файл).
  4. Суммарный размер дерева против порогов 01-repo-standard.md
     (цель 50 МБ -> warning, мягкий 100 МБ -> warning, жёсткий 500 МБ -> FAIL).
  5. Пустые папки -> warning (мусор структуры).
  6. Архивы/тяжёлые бинарники в git-дереве -> warning
     («zip — транспорт, а не версионируемый исходник», 15-gotchas §2).

Запуск из корня репы:
    python3 scripts/revision_check.py [--strict] [--root PATH]

Allowlist ссылок (по одной на строку, относительный путь как в ссылке):
    .revision_allowlist в корне репы.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

WARN_FILE_MB = 20
FAIL_FILE_MB = 95
REPO_TARGET_MB = 50
REPO_SOFT_MB = 100
REPO_HARD_MB = 500

FROZEN_DIRS = (
    "reports/incidents",
    "reports/investigations",
    "reports/merges",
    "reports/situations",
    "reports/releases",
    "reports/audits",
)
FROZEN_FILES = ("CHANGELOG.md",)
LINK_SKIP_DIRS = ("templates",)  # шаблоны содержат намеренные плейсхолдеры-ссылки
SKIP_DIRS = (".git", ".venv", "node_modules", "__pycache__")
ARCHIVE_SUFFIXES = (".zip", ".tar", ".gz", ".7z", ".rar", ".dmg", ".iso")

MD_LINK_RE = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
IMG_LINK_RE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)\)")
HEX_NAME_RE = re.compile(r"#U[0-9a-fA-F]{4}")


def is_frozen(rel: Path) -> bool:
    posix = rel.as_posix()
    if rel.name in FROZEN_FILES:
        return True
    return any(posix.startswith(d + "/") or posix == d for d in FROZEN_DIRS)


def iter_files(root: Path) -> list[Path]:
    files = []
    for path in root.rglob("*"):
        rel_parts = path.relative_to(root).parts
        if any(part in SKIP_DIRS for part in rel_parts):
            continue
        if path.is_file():
            files.append(path)
    return files


def load_allowlist(root: Path) -> set[str]:
    allow = root / ".revision_allowlist"
    if not allow.is_file():
        return set()
    lines = allow.read_text(encoding="utf-8", errors="replace").splitlines()
    return {ln.strip() for ln in lines if ln.strip() and not ln.startswith("#")}


def check_links(root: Path, files: list[Path], allowlist: set[str]) -> tuple[list[str], int, int]:
    broken: list[str] = []
    checked = 0
    frozen_skipped = 0
    for path in files:
        if path.suffix.lower() != ".md":
            continue
        rel = path.relative_to(root)
        if is_frozen(rel) or rel.parts[0] in LINK_SKIP_DIRS:
            frozen_skipped += 1
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        targets = MD_LINK_RE.findall(text) + IMG_LINK_RE.findall(text)
        for raw in targets:
            target = raw.split("#", 1)[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:", "tel:")):
                continue
            if raw in allowlist or target in allowlist:
                continue
            checked += 1
            candidate = (path.parent / target).resolve()
            if not candidate.exists():
                broken.append(f"{rel}: битая ссылка -> {raw}")
    return broken, checked, frozen_skipped


def check_names(root: Path, files: list[Path]) -> list[str]:
    bad = []
    for path in files:
        if HEX_NAME_RE.search(path.name):
            bad.append(str(path.relative_to(root)))
    return bad


def check_sizes(root: Path, files: list[Path]) -> tuple[list[str], list[str], float]:
    warns: list[str] = []
    fails: list[str] = []
    total = 0
    for path in files:
        size = path.stat().st_size
        total += size
        mb = size / 1024 / 1024
        rel = path.relative_to(root)
        if mb > FAIL_FILE_MB:
            fails.append(f"{rel}: {mb:.1f} МБ (> {FAIL_FILE_MB} МБ, лимит GitHub рядом)")
        elif mb > WARN_FILE_MB:
            warns.append(f"{rel}: {mb:.1f} МБ (> {WARN_FILE_MB} МБ — кандидат на сжатие, док 06)")
        if path.suffix.lower() in ARCHIVE_SUFFIXES:
            warns.append(f"{rel}: архив в дереве («zip — транспорт», 15-gotchas §2)")
    return warns, fails, total / 1024 / 1024


def check_empty_dirs(root: Path) -> list[str]:
    empty = []
    for path in root.rglob("*"):
        rel_parts = path.relative_to(root).parts
        if any(part in SKIP_DIRS for part in rel_parts):
            continue
        if path.is_dir() and not any(path.iterdir()):
            empty.append(str(path.relative_to(root)))
    return empty


def main() -> int:
    parser = argparse.ArgumentParser(description="Ревизионный гейт knowledge-репы")
    parser.add_argument("--root", default=".", help="корень репы (по умолчанию текущая папка)")
    parser.add_argument("--strict", action="store_true", help="warnings тоже валят гейт")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    files = iter_files(root)
    allowlist = load_allowlist(root)

    failures: list[str] = []
    warnings: list[str] = []

    broken, checked, frozen_skipped = check_links(root, files, allowlist)
    if broken:
        failures.extend(broken)
        print(f"[FAIL] Битые ссылки: {len(broken)}")
        for line in broken:
            print(f"    · {line}")
    else:
        print("[OK] Битые ссылки")
    print(f"    · проверено ссылок: {checked}; замороженных .md пропущено: {frozen_skipped}; allowlist: {len(allowlist)}")

    bad_names = check_names(root, files)
    if bad_names:
        failures.extend(bad_names)
        print(f"[FAIL] Имена с порчей #Uxxxx (PIT-009): {len(bad_names)}")
        for line in bad_names:
            print(f"    · {line}")
    else:
        print("[OK] Имена файлов (нет #Uxxxx-порчи)")

    size_warns, size_fails, total_mb = check_sizes(root, files)
    if size_fails:
        failures.extend(size_fails)
        print(f"[FAIL] Файлы у жёсткого лимита: {len(size_fails)}")
        for line in size_fails:
            print(f"    · {line}")
    if size_warns:
        warnings.extend(size_warns)
        print(f"[WARN] Тяжёлое в дереве: {len(size_warns)}")
        for line in size_warns:
            print(f"    · {line}")
    label = "OK"
    if total_mb > REPO_HARD_MB:
        failures.append(f"размер репы {total_mb:.1f} МБ > жёсткого порога {REPO_HARD_MB} МБ")
        label = "FAIL"
    elif total_mb > REPO_SOFT_MB:
        warnings.append(f"размер репы {total_mb:.1f} МБ > мягкого порога {REPO_SOFT_MB} МБ")
        label = "WARN"
    elif total_mb > REPO_TARGET_MB:
        warnings.append(f"размер репы {total_mb:.1f} МБ > целевого порога {REPO_TARGET_MB} МБ")
        label = "WARN"
    print(f"[{label}] Размер дерева: {total_mb:.1f} МБ (цель {REPO_TARGET_MB} / мягкий {REPO_SOFT_MB} / жёсткий {REPO_HARD_MB})")

    empty = check_empty_dirs(root)
    if empty:
        warnings.extend(f"пустая папка: {d}" for d in empty)
        print(f"[WARN] Пустые папки: {len(empty)}")
        for line in empty:
            print(f"    · {line}")
    else:
        print("[OK] Пустых папок нет")

    print()
    if failures or (args.strict and warnings):
        print(f"ИТОГ: DRIFT (fail: {len(failures)}, warn: {len(warnings)})")
        return 1
    if warnings:
        print(f"ИТОГ: CLEAN с предупреждениями (warn: {len(warnings)})")
        return 0
    print("ИТОГ: CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
