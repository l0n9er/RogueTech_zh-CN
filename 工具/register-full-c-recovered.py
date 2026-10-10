#!/usr/bin/env python3
"""Register full-c location repairs in dict-repair for repeatable installs."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROWS = ROOT / "backup" / "llm-batches" / "full-c-recovered.zh.json"
BACK = ROOT / "backup" / "Mods-full-c-recovered"
OUT = ROOT / "工具" / "dict-repair.tsv"

def get_field(obj, field):
    for p in field.split("."):
        obj = obj[p]
    return obj

def esc(s):
    return s.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n").replace("\t", " ")

def main():
    rows = json.loads(ROWS.read_text(encoding="utf-8"))
    existing = set()
    if OUT.exists():
        for line in OUT.read_text(encoding="utf-8-sig").splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                existing.add((parts[0], parts[1]))
    added = 0
    with OUT.open("a", encoding="utf-8", newline="\n") as fh:
        for row in rows:
            path = Path(row["file"])
            try:
                rel = Path(*path.parts[path.parts.index("Mods") + 1:])
                backup = BACK / rel
                obj = json.loads(backup.read_text(encoding="utf-8-sig"))
                old = get_field(obj, row["field"])
            except Exception:
                continue
            key = (esc(old), esc(row["translation"]))
            if key in existing:
                continue
            fh.write(key[0] + "\t" + key[1] + "\tFull-C-Recovered\n")
            existing.add(key)
            added += 1
    print(f"registered={added} rows in {OUT}")

if __name__ == "__main__":
    main()
