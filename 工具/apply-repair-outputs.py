#!/usr/bin/env python3
"""Apply whole-field LLM repair outputs to the game and installation dictionary.

The repair batches contain the exact polluted value currently present in a unit
field.  This tool validates formatting tokens, backs up each changed JSON once,
updates referenced fields, and replaces duplicate dictionary keys with the
latest reviewed translation so a later install cannot select an older fragment.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH")
MODS = GAME / "Mods"
BATCH_DIR = ROOT / "backup" / "llm-batches"
BACKUP = ROOT / "backup" / "Mods-repair-wholefield"
DICT = ROOT / "工具" / "dict-unit-llm.tsv"
REPORT = ROOT / "backup" / "llm-repair-apply.tsv"

TOKEN_RE = re.compile(r"<[^>]*>|\{[^{}]*\}|\[\[[\s\S]*?\]\]|\\[nrt]|\r?\n")
HAN_RE = re.compile(r"[\u3400-\u9fff]")


def tokens(value: str) -> list[str]:
    # JSON rows may carry CRLF while the model output uses LF.  They are the
    # same visible line breaks and must not be treated as a placeholder loss.
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    return sorted(TOKEN_RE.findall(value))


def esc(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def unesc(value: str) -> str:
    return value.replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t").replace("\\\\", "\\")


def get_field(obj: object, path: str):
    cur = obj
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def set_field(obj: object, path: str, value: str) -> bool:
    parts = path.split(".")
    cur = obj
    for part in parts[:-1]:
        if not isinstance(cur, dict) or part not in cur:
            return False
        cur = cur[part]
    if not isinstance(cur, dict) or parts[-1] not in cur:
        return False
    cur[parts[-1]] = value
    return True


def load_rows() -> tuple[list[dict], list[str]]:
    rows: list[dict] = []
    errors: list[str] = []
    for path in sorted(BATCH_DIR.glob("repair-output-*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"{path.name}\tINVALID_JSON\t{exc}")
            continue
        if not isinstance(data, list):
            errors.append(f"{path.name}\tNOT_ARRAY\t-")
            continue
        for row in data:
            source = row.get("source") if isinstance(row, dict) else None
            translation = row.get("translation") if isinstance(row, dict) else None
            if not isinstance(source, str) or not isinstance(translation, str):
                errors.append(f"{path.name}\tINVALID_ROW\t{row!r}")
                continue
            if not translation.strip() or not HAN_RE.search(translation):
                errors.append(f"{path.name}\tNO_CHINESE\t{row.get('id', '-')}")
                continue
            if tokens(source) != tokens(translation):
                errors.append(f"{path.name}\tTOKEN_MISMATCH\t{row.get('id', '-')}")
                continue
            refs = row.get("references") or []
            if not refs:
                errors.append(f"{path.name}\tNO_REFERENCES\t{row.get('id', '-')}")
                continue
            row["_batch"] = path.name
            rows.append(row)
    return rows, errors


def main() -> int:
    rows, errors = load_rows()
    mapping: dict[str, str] = {}
    conflicts: list[str] = []
    for row in rows:
        source = row["source"]
        translation = row["translation"]
        if source in mapping and mapping[source] != translation:
            conflicts.append(f"CONFLICT\t{row['_batch']}\t{row.get('id', '-')}")
        mapping[source] = translation

    changed_files: dict[Path, dict] = {}
    touched: set[Path] = set()
    applied = 0
    already = 0
    mismatches: list[str] = []
    for row in rows:
        source = row["source"]
        translation = mapping[source]
        for ref in row.get("references", []):
            path = Path(ref.get("file", ""))
            field = ref.get("field", "")
            if not path.is_absolute():
                path = GAME / path
            if not path.exists():
                mismatches.append(f"{row['_batch']}\tMISSING_FILE\t{path}\t{field}")
                continue
            if path not in changed_files:
                try:
                    changed_files[path] = json.loads(path.read_text(encoding="utf-8"))
                except Exception as exc:
                    mismatches.append(f"{row['_batch']}\tINVALID_GAME_JSON\t{path}\t{exc}")
                    continue
            obj = changed_files[path]
            current = get_field(obj, field)
            if current == translation:
                already += 1
            elif current == source:
                if set_field(obj, field, translation):
                    applied += 1
                    touched.add(path)
                else:
                    mismatches.append(f"{row['_batch']}\tFIELD_NOT_FOUND\t{path}\t{field}")
            else:
                # Earlier broken passes sometimes replaced the entire field
                # with a generic sentence such as “配置说明已完整汉化…”.
                # It contains Chinese and therefore cannot be recognized as
                # English contamination, but it has discarded the source
                # facts.  A reviewed whole-field row is authoritative here.
                generic = isinstance(current, str) and re.search(
                    r"完整汉化|原文所述|配置说明已|保留原文", current
                )
                if generic:
                    if set_field(obj, field, translation):
                        applied += 1
                        touched.add(path)
                    else:
                        mismatches.append(f"{row['_batch']}\tFIELD_NOT_FOUND\t{path}\t{field}")
                    continue
                # A previous manual repair may already have produced a better
                # complete translation.  Preserve it and use it for this
                # source key in the installer dictionary; otherwise a later
                # install would regress the field to the batch wording.
                long_english = re.search(r"(?:(?:\b[A-Za-z][A-Za-z0-9/-]*\b)\s+){4}\b[A-Za-z][A-Za-z0-9/-]*\b", str(current))
                if isinstance(current, str) and HAN_RE.search(current) and not long_english:
                    if source in mapping and mapping[source] != current:
                        conflicts.append(f"CURRENT_CONFLICT\t{row['_batch']}\t{row.get('id', '-')}")
                    else:
                        mapping[source] = current
                    already += 1
                else:
                    mismatches.append(f"{row['_batch']}\tSOURCE_MISMATCH\t{path}\t{field}")

    for path, obj in changed_files.items():
        original = path.read_text(encoding="utf-8")
        # Only back up files that actually contain an applied change.
        rendered = json.dumps(obj, ensure_ascii=False, indent=2) + "\n"
        if path not in touched or rendered == original:
            continue
        rel = path.relative_to(MODS)
        dst = BACKUP / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists():
            dst.write_text(original, encoding="utf-8")
        path.write_text(rendered, encoding="utf-8")

    # Replace same-key rows in the unit dictionary, preserving unrelated history.
    old_lines = DICT.read_text(encoding="utf-8").splitlines() if DICT.exists() else []
    keys = set(mapping)
    kept: list[str] = []
    replaced = 0
    for line in old_lines:
        raw_key = line.split("\t", 1)[0] if "\t" in line else ""
        if unesc(raw_key) in keys:
            replaced += 1
            continue
        kept.append(line)
    for source, translation in mapping.items():
        kept.append(f"{esc(source)}\t{esc(translation)}\tLLM-REPAIR")
    DICT.write_text("\n".join(kept) + "\n", encoding="utf-8")

    report_lines = ["status\tdetail"]
    report_lines.extend(errors)
    report_lines.extend(conflicts)
    report_lines.extend(mismatches)
    REPORT.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print(f"批次条目={len(rows)} 唯一字段={len(mapping)} 写回字段={applied} 已是译文={already} 文件={len(changed_files)}")
    print(f"词典替换旧键={replaced} 报告={REPORT}")
    # CURRENT_CONFLICT means the same polluted source occurred in files whose
    # dynamic numeric suffixes were already repaired differently.  Keeping the
    # current per-file values is intentional; only hard validation/ref errors
    # should fail the batch application.
    hard = errors + mismatches
    if conflicts:
        print(f"提示：保留已有逐文件译文，动态字段冲突={len(conflicts)}")
    if hard:
        print(f"异常={len(hard)}，请检查报告")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
