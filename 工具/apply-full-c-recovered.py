#!/usr/bin/env python3
"""Apply the reviewed location-aware full-c recovery batch with a backup."""
import json, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROWS = ROOT / "backup" / "llm-batches" / "full-c-recovered.zh.json"
BACK = ROOT / "backup" / "Mods-full-c-recovered"

def set_field(obj, field, value):
    cur = obj
    parts = field.split(".")
    for p in parts[:-1]:
        cur = cur[p]
    cur[parts[-1]] = value

def main():
    rows = json.loads(ROWS.read_text(encoding="utf-8"))
    changed = 0
    files = 0
    for row in rows:
        path = Path(row["file"])
        if not path.exists():
            continue
        try:
            obj = json.loads(path.read_text(encoding="utf-8-sig"))
            cur = obj
            for p in row["field"].split("."):
                cur = cur[p]
            old = cur
            if old == row["translation"]:
                continue
            rel = Path(*path.parts[path.parts.index("Mods") + 1:])
            backup = BACK / rel
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                shutil.copy2(path, backup)
            set_field(obj, row["field"], row["translation"])
            path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            changed += 1
            files += 1
        except Exception as exc:
            print(f"SKIP {path}: {exc}")
    print(f"full-c recovered rows={len(rows)} changed_fields={changed} files={files}")

if __name__ == "__main__":
    main()
