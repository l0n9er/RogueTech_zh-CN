#!/usr/bin/env python3
"""Apply reviewed whole-field unit translations to every referenced game JSON.

Input shards are keyed by the canonical source id and carry the concrete file
references produced by the QA extraction step.  The script never performs
substring replacement: each target field is replaced as one complete value.
"""
from __future__ import annotations
import json, re, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME_MODS = Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH\Mods")
BACK = ROOT / "backup" / "Mods-final-wholefield"
HAN = re.compile(r"[\u3400-\u9fff]")
BAD = re.compile(r"\b(?:Powered\s+by|is\s+armed\s+with|was\s+designed|This\s+(?:variant|unit|configuration)|The\s+[A-Za-z][A-Za-z -]{2,80}\s+is|Left\s+Lower|Right\s+Lower)\b|\ufffd", re.I)
TOK = re.compile(r"<[^>]*>|\\[nrt]|\r?\n|\{[^{}]*\}|\[\[[\s\S]*?\]\]")

def tokens(s: str) -> list[str]:
    return sorted(TOK.findall(s.replace("\\r\\n", "\n").replace("\r\n", "\n").replace("\r", "\n")))

def valid(src: str, tr: str) -> tuple[bool, str]:
    if not isinstance(tr, str) or not tr.strip(): return False, "empty"
    if not HAN.search(tr): return False, "no-chinese"
    if BAD.search(tr): return False, "english-or-replacement"
    if tokens(src) != tokens(tr): return False, "token-mismatch"
    return True, "ok"

def set_field(obj, field, value):
    cur = obj
    parts = field.split(".")
    for p in parts[:-1]: cur = cur[p]
    cur[parts[-1]] = value

def main() -> None:
    rows = []
    for p in sorted((ROOT / "backup" / "llm-batches").glob("final-output-*.json")):
        if "final-output-1b" not in p.name and p.name.endswith(".json"):
            pass
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if isinstance(data, list): rows.extend(data)
    # Outputs that carry references can be applied directly.  Outputs keyed by
    # id are joined against the corresponding final-input shard.
    inputs = {}
    for p in sorted((ROOT / "backup" / "llm-batches").glob("final-input-*.json")):
        try:
            for row in json.loads(p.read_text(encoding="utf-8")):
                inputs.setdefault(row.get("id"), []).append(row)
        except Exception: pass
    changed = rejected = missing = 0
    seen = set()
    for row in rows:
        tr = row.get("translation", "")
        candidates = inputs.get(row.get("id"), [])
        inp = next((x for x in candidates if x.get("source") == row.get("source")), None)
        if inp is None: inp = row
        src = row.get("source", inp.get("source", ""))
        ok, why = valid(src, tr)
        if not ok:
            rejected += 1; continue
        refs = row.get("references") or inp.get("references") or []
        for ref in refs:
            fn, field = ref.get("file", ""), ref.get("field", "")
            if not fn or not field: continue
            p = Path(fn)
            if not p.exists(): missing += 1; continue
            try: obj = json.loads(p.read_text(encoding="utf-8-sig"))
            except Exception: continue
            try:
                cur = obj
                for k in field.split("."): cur = cur[k]
            except Exception: continue
            if cur == tr: continue
            key = (str(p).lower(), field)
            if key in seen: continue
            seen.add(key)
            rel = p.relative_to(GAME_MODS)
            bak = BACK / rel
            bak.parent.mkdir(parents=True, exist_ok=True)
            if not bak.exists(): shutil.copy2(p, bak)
            set_field(obj, field, tr)
            p.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            changed += 1
    print(f"whole-field translations={len(rows)} rejected={rejected} changed={changed} missing={missing}")

if __name__ == "__main__": main()
