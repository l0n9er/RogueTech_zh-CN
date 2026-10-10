#!/usr/bin/env python3
"""从 Mods-defs 英文基线和已有词典/Localization 恢复混杂单位字段。

此脚本只生成恢复清单，不直接改写游戏 JSON。这样可以在应用前审阅映射，
避免把污染词典再次写回单位定义。
"""
from __future__ import annotations
import csv, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKUP = ROOT / "backup"
BASE = BACKUP / "Mods-defs"
FOCUS = BACKUP / "unit-scan-focus.jsonl"
OUT = BACKUP / "focus-recovered-mappings.jsonl"
UNRES = BACKUP / "focus-unresolved-top100.jsonl"
GAME = Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH")

FIELDS = {"Details", "YangsThoughts", "StockRole", "UIName", "Name", "Description"}
BAD = re.compile(r"[�]|(?:^|\b)(?:Powered\s+by|The\s+|This\s+variant|is\s+armed\s+with|was\s+designed|and\s+a\s+pair\s+of|Left\s+Lower|Right\s+Lower|Quirk:|Drop\s+Cost\s+Multiplier)(?:\b|:)", re.I)

def clean(v: str) -> bool:
    if not isinstance(v, str) or not v.strip() or "\ufffd" in v:
        return False
    # 接受型号、武器缩写和标签中的英文；拒绝明显整句/半句英文污染。
    plain = re.sub(r"<[^>]+>", " ", v)
    if BAD.search(plain):
        return False
    if re.search(r"[\u4e00-\u9fff].*[A-Za-z]{3,}.*[A-Za-z]{3,}", plain):
        # 单独的专名/型号允许，连续英文词组不允许
        words = re.findall(r"[A-Za-z]{3,}", plain)
        if len(words) >= 5:
            return False
    return True

def walk_strings(x, path=()):
    if isinstance(x, dict):
        for k, v in x.items():
            p = path + (k,)
            if isinstance(v, str):
                yield p, v
            else:
                yield from walk_strings(v, p)
    elif isinstance(x, list):
        for i, v in enumerate(x):
            yield from walk_strings(v, path + (str(i),))

def get_path(x, path):
    for p in path:
        if isinstance(x, dict): x = x.get(p)
        elif isinstance(x, list): x = x[int(p)]
        else: return None
    return x

def rel_from_game(fn: str):
    s = fn.replace("/", "\\")
    marker = "\\Mods\\"
    if marker in s:
        return Path(s.split(marker, 1)[1])
    if "Mods\\" in s:
        return Path(s.split("Mods\\", 1)[1])
    return None

def load_pairs():
    # source -> list[(translation, source_file, line)]，后加载的专项词典优先。
    pairs = {}
    files = ["dict-all.tsv", "dict-repair.tsv", "dict-details-direct.tsv",
             "dict-runtime-extra.tsv", "dict-unit-llm.tsv"]
    for fn in files:
        p = ROOT / "工具" / fn
        if not p.exists(): continue
        with p.open(encoding="utf-8-sig", newline="") as f:
            for no, row in enumerate(csv.reader(f, delimiter="\t"), 1):
                if len(row) < 2: continue
                src, dst = row[0], row[1]
                if clean(dst): pairs.setdefault(src, []).append((dst, fn, no))
    # Localization overlay 是最可靠的完整字段来源，加入最高优先级。
    for p in ROOT.glob("Mods/**/Localization/**/Localization.json"):
        try: data = json.loads(p.read_text(encoding="utf-8-sig"))
        except Exception: continue
        for item in data if isinstance(data, list) else []:
            loc = item.get("Localization", {}) if isinstance(item, dict) else {}
            src, dst = loc.get("CULTURE_EN_US"), loc.get("CULTURE_ZH_CN")
            if isinstance(src, str) and isinstance(dst, str) and clean(dst):
                pairs.setdefault(src, []).insert(0, (dst, str(p), item.get("Name", "")))
    return pairs

def main():
    pairs = load_pairs()
    unresolved, results = [], []
    seen = set()
    if not FOCUS.exists(): raise SystemExit(f"missing {FOCUS}")
    for line in FOCUS.read_text(encoding="utf-8-sig").splitlines():
        if not line.strip(): continue
        rec = json.loads(line)
        fn, field = rec.get("file", ""), rec.get("field", "")
        key = (fn, field)
        if key in seen: continue
        seen.add(key)
        rel = rel_from_game(fn)
        base = BASE / rel if rel else None
        source = None; status = "baseline_missing"
        if base and base.exists():
            try:
                data = json.loads(base.read_text(encoding="utf-8-sig"))
                source = get_path(data, tuple(field.split(".")))
                status = "baseline_ok"
            except Exception as e:
                status = "baseline_error:" + str(e)
        if not isinstance(source, str) or not source.strip():
            unresolved.append({"file": fn, "field": field, "status": status, "current": rec.get("value", ""), "source": source or ""})
            continue
        options = pairs.get(source, [])
        chosen = next(((dst, src, no) for dst, src, no in options if clean(dst)), None)
        if chosen:
            dst, origin, no = chosen
            results.append({"file": fn, "field": field, "source": source, "translation": dst, "origin": origin, "origin_line": no})
        else:
            unresolved.append({"file": fn, "field": field, "status": "no_exact_translation", "source": source, "current": rec.get("value", "")})
    OUT.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in results) + "\n", encoding="utf-8")
    # 优先把包含整句英文、乱码、候选最长的条目交给模型；只输出前100条。
    unresolved.sort(key=lambda x: ("�" not in x.get("current", ""), -len(x.get("source", ""))))
    UNRES.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in unresolved[:100]) + "\n", encoding="utf-8")
    print(json.dumps({"focus_unique": len(seen), "recovered": len(results), "unresolved": len(unresolved), "output": str(OUT), "top100": str(UNRES)}, ensure_ascii=False))

if __name__ == "__main__": main()
