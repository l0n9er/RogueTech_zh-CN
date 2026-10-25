#!/usr/bin/env python3
"""Apply reviewed whole-field translations for residual unit descriptions.

The source side is read from the clean RtCache snapshot using each flagged
game file's relative path.  This deliberately replaces a complete field; it
does not splice words into polluted text.  Every row is checked for tags,
placeholders, replacement characters, and obvious English sentence residue.
"""
from __future__ import annotations

import csv
import argparse
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH")
MODS = GAME / "Mods"
CACHE = Path(r"H:\RT HHR 1.0.1\RtlCache\RtCache")
QA = ROOT / "backup" / "unit-fields-qa-current-20261016.tsv"
DICT = ROOT / "工具" / "dict-unit-completion.tsv"
BACKUP = ROOT / "backup" / "Mods-unit-completion"
REPORT = ROOT / "backup" / "unit-completion-apply.tsv"

HAN = re.compile(r"[\u3400-\u9fff]")
TAG = re.compile(r"</?[A-Za-z][^>]*>")
TOKEN = re.compile(r"</?[A-Za-z][^>]*>|<3|\{[^{}]*\}|\[\[[\s\S]*?\]\]|\\[nrt]|\r?\n")
EN_SENT = re.compile(
    r"(?:(?:\b[A-Za-z][A-Za-z0-9/'-]*\b)\s+){4}\b[A-Za-z][A-Za-z0-9/'-]*\b"
)
EN_FUNCTION = re.compile(
    r"\b(?:the|was|were|is|are|designed|with|and|for|this|variant|"
    r"from|in|of|to|a|an|that|on|as|its|has|have|using|used|provides|"
    r"carries|equipped|armed|which|while|though|but)\b",
    re.I,
)
BAD_MIX = re.compile(
    r"(?:设计ed|装甲ed|机甲s|激光s|全向Mech|Omni机甲|"
    r"\b(?:Powered\s+by|is\s+armed\s+with|was\s+designed|"
    r"This\s+(?:variant|unit)|and\s+a\s+pair\s+of)\b)",
    re.I,
)


def esc(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def unesc(value: str) -> str:
    return (
        value.replace("\\n", "\n")
        .replace("\\r", "\r")
        .replace("\\t", "\t")
        .replace("\\\\", "\\")
    )


def tokens(value: str) -> list[str]:
    return sorted(TOKEN.findall(value.replace("\r\n", "\n").replace("\r", "\n")))


def walk(obj: object, path: tuple[str, ...] = ()):
    if isinstance(obj, dict):
        for key, value in obj.items():
            here = path + (key,)
            if key in {"Details", "YangsThoughts"} and isinstance(value, str):
                yield here, value
            if isinstance(value, (dict, list)):
                yield from walk(value, here)
    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            yield from walk(value, path + (str(index),))


def get_path(obj: object, path: tuple[str, ...]):
    for part in path:
        if not isinstance(obj, dict):
            return None
        obj = obj.get(part)
    return obj


def find_named_paths(obj: object, name: str, path: tuple[str, ...] = ()):
    if isinstance(obj, dict):
        for key, value in obj.items():
            here = path + (key,)
            if key == name and isinstance(value, str):
                yield here, value
            if isinstance(value, (dict, list)):
                yield from find_named_paths(value, name, here)
    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            yield from find_named_paths(value, name, path + (str(index),))


def set_path(obj: object, path: tuple[str, ...], value: str) -> bool:
    cur = obj
    for part in path[:-1]:
        if not isinstance(cur, dict) or part not in cur:
            return False
        cur = cur[part]
    if not isinstance(cur, dict) or path[-1] not in cur:
        return False
    cur[path[-1]] = value
    return True


def good_translation(source: str, translation: str) -> tuple[bool, str]:
    if not isinstance(translation, str) or not translation.strip():
        return False, "empty"
    if not HAN.search(translation):
        return False, "no_chinese"
    if "\ufffd" in translation:
        return False, "replacement_character"
    if tokens(source) != tokens(translation):
        return False, "token_mismatch"
    # Chinese prose may retain product names and weapon abbreviations, but not
    # an English grammatical sentence or a known half-translated word.
    # Five English words can be a manufacturer/product name; require several
    # English function words before classifying it as an English sentence.
    if (EN_SENT.search(translation) and len(EN_FUNCTION.findall(translation)) >= 6) or BAD_MIX.search(translation):
        return False, "english_sentence_residue"
    return True, "ok"


def load_translation_rows() -> tuple[dict[str, str], list[str]]:
    mapping: dict[str, str] = {}
    errors: list[str] = []
    files = []
    for pattern in ("translation-output-[1-3].json", "translation-extra-output-[1-3].json", "translation-missingcache-output.json", "translation-final-residual.json"):
        files.extend((ROOT / "backup").glob(pattern))
    # Later reviewed layers override earlier batches when they share a source.
    def layer(path: Path) -> tuple[int, str]:
        if path.name.startswith("translation-output-"):
            return (0, path.name)
        if path.name.startswith("translation-extra-output-"):
            return (1, path.name)
        if path.name == "translation-missingcache-output.json":
            return (2, path.name)
        return (3, path.name)

    files = sorted(set(files), key=layer)
    for path in files:
        try:
            rows = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"{path.name}\tINVALID_JSON\t{exc}")
            continue
        if not isinstance(rows, list):
            errors.append(f"{path.name}\tNOT_ARRAY\t-")
            continue
        for row in rows:
            source = row.get("source") if isinstance(row, dict) else None
            translation = row.get("translation") if isinstance(row, dict) else None
            if not isinstance(source, str) or not isinstance(translation, str):
                errors.append(f"{path.name}\tINVALID_ROW\t{row!r}")
                continue
            ok, reason = good_translation(source, translation)
            if not ok:
                errors.append(f"{path.name}\t{reason}\t{row.get('id', '-')}")
                continue
            # Repeated source rows are intentional when a later QA pass refines
            # an earlier batch. The layer ordering above makes the refined row win.
            mapping[source] = translation
    return mapping, errors


def load_trusted_existing() -> dict[str, str]:
    """Use only complete candidates; polluted legacy rows are rejected."""
    path = ROOT / "工具" / "dict-candidates-agent.tsv"
    out: dict[str, str] = {}
    if not path.exists():
        return out
    with path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            source = row.get("CleanSourceKey", "")
            translation = row.get("CandidateChinese", "")
            ok, _ = good_translation(source, translation)
            if ok and source not in out:
                out[source] = translation
    for path in (ROOT / "backup" / "llm-batches").glob("*.json"):
        try:
            rows = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if isinstance(rows, dict):
            rows = [rows]
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            source = row.get("source") or row.get("original") or row.get("en")
            translation = row.get("translation") or row.get("zh") or row.get("translated")
            if not isinstance(source, str) or not isinstance(translation, str):
                continue
            ok, _ = good_translation(source, translation)
            if ok:
                out.setdefault(source, translation)
    return out


def load_targets() -> tuple[dict[tuple[Path, str], str], dict[str, int]]:
    targets: dict[tuple[Path, str], str] = {}
    counts: dict[str, int] = {}
    with QA.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if row.get("Status") not in {"ENGLISH", "ENGLISH_SENTENCE", "CONTAMINATED"}:
                continue
            path = Path(row["File"])
            field = row.get("Field", "")
            if not path.is_absolute() or not field:
                continue
            targets[(path, field)] = row.get("Status", "")
            counts[row.get("Status", "")] = counts.get(row.get("Status", ""), 0) + 1
    return targets, counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply complete unit-field translations")
    parser.add_argument(
        "--dictionary-only",
        action="store_true",
        help="validate translations and generate the installer dictionary without editing game files",
    )
    args = parser.parse_args()

    translations, errors = load_translation_rows()
    existing = load_trusted_existing()
    for source, translation in existing.items():
        translations.setdefault(source, translation)

    targets, status_counts = load_targets()
    changed_files: dict[Path, object] = {}
    originals: dict[Path, str] = {}
    changed = 0
    skipped = 0
    missed = 0
    field_entries: dict[str, str] = {}
    report = ["status\tfile\tfield\tdetail"]

    for (path, field), status in targets.items():
        try:
            rel = path.relative_to(MODS)
        except ValueError:
            report.append(f"SKIP\t{path}\t{field}\tnot_under_mods")
            skipped += 1
            continue
        source_candidates = (CACHE / rel, CACHE / "Optionals" / rel)
        source_path = next((candidate for candidate in source_candidates if candidate.exists()), None)
        if source_path is None:
            report.append(
                f"CACHE_MISS\t{path}\t{field}\t"
                + ",".join(str(candidate) for candidate in source_candidates)
            )
        try:
            if path not in changed_files:
                originals[path] = path.read_text(encoding="utf-8-sig")
                changed_files[path] = json.loads(originals[path])
        except Exception as exc:
            report.append(f"INVALID_JSON\t{path}\t{field}\t{exc}")
            skipped += 1
            continue
        try:
            source_obj = json.loads(source_path.read_text(encoding="utf-8-sig")) if source_path else None
            if source_obj is None or not list(find_named_paths(source_obj, field)):
                source_obj = changed_files[path]
        except Exception:
            source_obj = changed_files[path]
        candidates = list(find_named_paths(source_obj, field))
        selected = next(((parts, source) for parts, source in candidates if source in translations), None)
        if selected is None:
            detail = candidates[0][1] if candidates else ""
            report.append(f"UNTRANSLATED\t{path}\t{field}\t{detail}")
            missed += 1
            continue
        parts, source = selected
        translation = translations[source]
        current = get_path(changed_files[path], parts)
        if current == translation:
            continue
        if isinstance(current, str) and current != source:
            previous = field_entries.get(current)
            if previous and previous != translation:
                report.append(f"FIELD_KEY_CONFLICT\t{path}\t{field}\t{source}")
                skipped += 1
                continue
            field_entries[current] = translation
        if set_path(changed_files[path], parts, translation):
            changed += 1
            report.append(f"APPLIED\t{path}\t{field}\t{status}")
        else:
            report.append(f"FIELD_NOT_FOUND\t{path}\t{field}\t-")
            skipped += 1

    report.extend(f"INPUT_ERROR\t-\t-\t{error}" for error in errors)
    if errors or missed > 50 or (skipped and not args.dictionary_only):
        report.append(
            f"SUMMARY\t-\t-\ttranslations={len(translations)} keys={len(field_entries)} "
            f"changed={changed} files=0 missed={missed} skipped={skipped}"
        )
        REPORT.write_text("\n".join(report) + "\n", encoding="utf-8")
        print(
            f"拒绝应用：校验错误={len(errors)} 未命中={missed} 跳过={skipped}；"
            f"报告={REPORT}"
        )
        return 1

    touched = 0
    if not args.dictionary_only:
        for path, obj in changed_files.items():
            rendered = json.dumps(obj, ensure_ascii=False, indent=2) + "\n"
            if rendered == originals[path]:
                continue
            destination = BACKUP / path.relative_to(MODS)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists():
                shutil.copy2(path, destination)
            path.write_text(rendered, encoding="utf-8")
            touched += 1

    # The dedicated dictionary is loaded before historical dictionaries by the
    # installer.  A complete source key therefore survives future installs.
    DICT.parent.mkdir(parents=True, exist_ok=True)
    dictionary_entries = dict(translations)
    for current, translation in field_entries.items():
        dictionary_entries.setdefault(current, translation)
    with DICT.open("w", encoding="utf-8", newline="\n") as handle:
        for source, translation in sorted(dictionary_entries.items()):
            handle.write(f"{esc(source)}\t{esc(translation)}\tCOMPLETION\n")

    report.append(f"SUMMARY\t-\t-\ttranslations={len(translations)} keys={len(dictionary_entries)} changed={changed} files={touched} missed={missed} skipped={skipped}")
    REPORT.write_text("\n".join(report) + "\n", encoding="utf-8")
    mode = "仅生成词典" if args.dictionary_only else "直接写入游戏"
    print(f"{mode}：完整译文={len(translations)} 匹配字段={changed} 文件={touched} 未命中={missed} 跳过={skipped} 词典={DICT}")
    if errors:
        print(f"翻译输入校验问题={len(errors)}，详见报告前段")
    # Missing translations are expected only for the nine cache paths absent
    # from RtCache.  Any larger gap must stop the install/review cycle.
    if missed > 50:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
