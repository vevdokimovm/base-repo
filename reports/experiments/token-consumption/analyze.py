#!/usr/bin/env python3
"""
analyze.py — пересобирает модель расхода токенов из measurements.csv.

Часть системы-экспериментатора (методология — 00-infrastructure/28-empirical-experiment-methodology.md).
Читает лог опытов, считает калибровку, множители моделей (по OFAT-парам), OFAT-дельты по факторам и
(если есть numpy и достаточно данных) линейную регрессию. Печатает текущую лучшую оценку + уровни
доверия + что измерить дальше. Приорные значения используются там, где данных ещё нет.

Запуск:
    python3 analyze.py                      # берёт measurements.csv рядом
    python3 analyze.py path/to/log.csv
    python3 analyze.py --update-hypothesis  # дописать снимок оценки в hypothesis.md

Только стандартная библиотека (numpy — опционально, для регрессии).
"""
import csv
import os
import sys
import statistics as st

# --- приорные значения (живая гипотеза v0.1; уточняются данными) ---
PRIOR = {
    "session_tokens": 200_000,          # A2: окно контекста; A1: 45 сообщений × ~4.4K
    "tokens_per_1pct": 2_000,           # 1% сессии
    "week_sessions": (4, 8),            # A3: 4–8 полных сессий/неделю
    "model_mult": {                     # A4/A5: множитель расхода лимита (Opus=1.0)
        "opus": 1.0, "fable": 2.0, "sonnet": 0.4, "haiku": 0.15,
    },
    "short_msg_tokens": (3_000, 5_000), # 1 короткое сообщение
}
NUMERIC = ["input_tokens", "output_tokens", "tool_calls", "attachments",
           "tokens_measured", "pct_session", "pct_week"]


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            for k in NUMERIC:
                v = (r.get(k) or "").strip()
                r[k] = float(v) if v not in ("", None) else None
            rows.append(r)
    return rows


def calibrate(rows):
    """tokens_per_1% из строк, где есть и точные токены, и Δ% сессии."""
    pts = [(r["tokens_measured"], r["pct_session"]) for r in rows
           if r["tokens_measured"] and r["pct_session"]]
    if not pts:
        return None
    vals = [tok / pct for tok, pct in pts]
    return {
        "tokens_per_1pct": st.mean(vals),
        "session_tokens": st.mean(vals) * 100,
        "n": len(vals),
        "spread": (min(vals), max(vals)),
    }


def _key_except(r, factor, keys):
    return tuple((r.get(k) or "") for k in keys if k != factor)


def ofat_multiplier(rows, factor="model"):
    """Множитель по OFAT-парам: строки, различающиеся ТОЛЬКО значением factor
    и при одинаковом baseline_id. Возвращает отношения по значениям factor."""
    keys = ["surface", "effort", "baseline_id"]
    groups = {}
    for r in rows:
        if not r.get("baseline_id"):
            continue
        metric = r["tokens_measured"] or (
            r["pct_session"] * PRIOR["tokens_per_1pct"] if r["pct_session"] else None)
        if metric is None:
            continue
        groups.setdefault(_key_except(r, factor, keys), []).append((r.get(factor), metric))
    ratios = {}
    for _, items in groups.items():
        base = [m for v, m in items if v == "opus"]
        if not base:
            continue
        b = st.mean(base)
        for v, m in items:
            if v and v != "opus":
                ratios.setdefault(v, []).append(m / b)
    return {v: st.mean(rs) for v, rs in ratios.items()}


def ofat_deltas(rows, factor):
    """Δ по фактору: пары строк, идентичные кроме factor (по числовому результату)."""
    keys = ["surface", "model", "effort", "cache_state", "baseline_id"]
    groups = {}
    for r in rows:
        metric = r["tokens_measured"] or (
            r["pct_session"] * PRIOR["tokens_per_1pct"] if r["pct_session"] else None)
        if metric is None:
            continue
        groups.setdefault(_key_except(r, factor, keys), []).append((r.get(factor), metric))
    out = []
    for _, items in groups.items():
        if len({v for v, _ in items}) >= 2:
            out.append(sorted(items))
    return out


def regression(rows):
    """T ≈ a·input + b·output + c·tools + d·attach + intercept (нужен numpy и ≥6 полных строк)."""
    try:
        import numpy as np
    except ImportError:
        return None, "numpy не установлен — регрессия пропущена (pip install numpy)"
    feats = ["input_tokens", "output_tokens", "tool_calls", "attachments"]
    data = [r for r in rows if r["tokens_measured"] and all(r[f] is not None for f in feats)]
    if len(data) < 6:
        return None, f"регрессии нужно ≥6 полных строк, есть {len(data)} — копи данные"
    X = np.array([[r[f] for f in feats] + [1.0] for r in data])
    y = np.array([r["tokens_measured"] for r in data])
    coef, *_ = np.linalg.lstsq(X, y, rcond=None)
    names = feats + ["intercept"]
    return dict(zip(names, coef.tolist())), None


def conf(n):
    return "🟢 высокий" if n >= 5 else ("🟡 средний" if n >= 2 else "🔴 низкий (1 замер)")


def report(rows):
    L = []
    p = L.append
    p("=" * 70)
    p("МОДЕЛЬ РАСХОДА ТОКЕНОВ — текущая оценка (из measurements.csv)")
    p("=" * 70)
    p(f"Замеров в логе: {len(rows)}")
    p("")

    cal = calibrate(rows)
    p("1) КАЛИБРОВКА (размер сессии)")
    if cal:
        p(f"   tokens_per_1% = {cal['tokens_per_1pct']:.0f}  "
          f"(разброс {cal['spread'][0]:.0f}..{cal['spread'][1]:.0f}, n={cal['n']})")
        p(f"   → сессия ≈ {cal['session_tokens']:.0f} токенов   доверие: {conf(cal['n'])}")
        if abs(cal["session_tokens"] - PRIOR["session_tokens"]) / PRIOR["session_tokens"] < 0.15:
            p(f"   ✓ сходится с приором {PRIOR['session_tokens']:,} (два якоря) — сигнал сильный")
    else:
        p(f"   нет точных замеров → приор: сессия ≈ {PRIOR['session_tokens']:,}  доверие: 🔴")
        p("   ЧТО ИЗМЕРИТЬ: в Claude Code — свежая сессия, задача, снять 'N токенов + X%'.")
    p("")

    p("2) МНОЖИТЕЛИ МОДЕЛЕЙ (расход лимита, Opus=1.0)")
    mult = ofat_multiplier(rows, "model")
    for name, prior in PRIOR["model_mult"].items():
        if name in mult:
            p(f"   {name:7s} = {mult[name]:.2f}×  (измерено OFAT)   доверие: 🟢")
        elif name != "opus":
            p(f"   {name:7s} = {prior:.2f}×  (приор — OFAT-пары нет)  доверие: 🔴")
        else:
            p(f"   {name:7s} = 1.00×  (база)")
    if not mult:
        p("   ЧТО ИЗМЕРИТЬ: один и тот же baseline на Opus и Fable → снять Δ% на каждом.")
    p("")

    p("3) OFAT-ДЕЛЬТЫ ПО ФАКТОРАМ")
    any_delta = False
    for f in ["effort", "attachments", "tool_calls", "cache_state", "turn_pos", "surface"]:
        d = ofat_deltas(rows, f)
        if d:
            any_delta = True
            for pair in d:
                seq = " → ".join(f"{v}:{m:.0f}" for v, m in pair)
                p(f"   {f}: {seq}")
    if not any_delta:
        p("   пока нет OFAT-пар (строк, отличающихся ровно одним фактором).")
        p("   ЧТО ИЗМЕРИТЬ: повтори эталон, меняя по одному: effort off/high; +вложение; +N tool calls.")
    p("")

    p("4) ЛИНЕЙНАЯ ДЕКОМПОЗИЦИЯ (регрессия)")
    coef, err = regression(rows)
    if coef:
        for k, v in coef.items():
            p(f"   {k:14s}: {v:+.3f} токен/ед.")
    else:
        p(f"   {err}")
    p("")

    p("5) ПРАКТИЧЕСКИЕ ПЕРЕВОДЫ (текущие)")
    tp1 = cal["tokens_per_1pct"] if cal else PRIOR["tokens_per_1pct"]
    p(f"   1% сессии ≈ {tp1:.0f} токенов")
    p(f"   1 короткое сообщение ≈ {PRIOR['short_msg_tokens'][0]:,}–{PRIOR['short_msg_tokens'][1]:,} токенов")
    p(f"   сессий в неделю ≈ {PRIOR['week_sessions'][0]}–{PRIOR['week_sessions'][1]}")
    p("")
    p("СЛЕДУЮЩИЙ ШАГ: закрыть 🔴-пункты выше замерами (лучше в Claude Code — точный счётчик).")
    p("Добавь строки в measurements.csv и прогони скрипт снова — модель уточнится.")
    return "\n".join(L)


def main():
    # Позиционный аргумент считаем путём к логу ТОЛЬКО если это реально .csv/существующий файл.
    # Мусор (например залётный '#' от комментария в строке, если в zsh выключен interactive_comments)
    # молча игнорируем и берём measurements.csv рядом. Так скрипт не падает от копипаста с комментарием.
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "measurements.csv")
    for a in sys.argv[1:]:
        if a.startswith("--"):
            continue
        if os.path.isfile(a) or a.lower().endswith(".csv"):
            path = a
            break
    if not os.path.exists(path):
        sys.exit(f"нет файла лога: {path}\n"
                 f"положи measurements.csv рядом со скриптом или укажи путь к .csv явно.")
    rows = load(path)
    text = report(rows)
    print(text)
    if "--update-hypothesis" in sys.argv:
        hp = os.path.join(os.path.dirname(path), "hypothesis.md")
        block = "\n\n## Автоснимок оценки (analyze.py)\n\n```\n" + text + "\n```\n"
        with open(hp, "a", encoding="utf-8") as f:
            f.write(block)
        print(f"\n[записан снимок в {hp}]")


if __name__ == "__main__":
    main()
