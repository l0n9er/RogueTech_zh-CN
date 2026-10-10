#!/usr/bin/env python3
"""Recover the 350 tail unit Details entries from the clean source key.

full-c-candidates.json contains a clean ``match`` key even when ``source`` is
contaminated.  This script resolves that key against the existing dictionaries,
rejecting replacement characters and incomplete English fragments.  It writes
location-aware rows for review; no loose fragment replacement is performed.
"""
from __future__ import annotations
import csv, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BATCH = ROOT / "backup" / "llm-batches" / "full-c-candidates.json"
OUT = ROOT / "backup" / "llm-batches" / "full-c-recovered.zh.json"
REPORT = ROOT / "backup" / "llm-batches" / "full-c-recovered.tsv"
DICT_FILES = [
    ROOT / "工具" / "dict-details-direct.tsv",
    ROOT / "工具" / "dict-runtime-extra.tsv",
    ROOT / "工具" / "dict-repair.tsv",
    ROOT / "工具" / "dict-history-recovered.tsv",
    ROOT / "工具" / "dict-unit-llm.tsv",
    ROOT / "工具" / "dict-all.tsv",
]
HAN = re.compile(r"[\u3400-\u9fff]")
TAG = re.compile(r"<[^>]*>")
TOKEN = re.compile(r"<[^>]*>|\\[nrt]|\n|\{[^{}]*\}|\[\[[\s\S]*?\]\]")
COMMON = re.compile(r"\b(?:the|this|that|was|were|with|and|from|into|used|designed|powered|carried|armed|is|are|can|not|left|right|front|rear|quirk|drop|cost|multiplier|armor|structure|laser|medium|small|large)\b", re.I)

def norm(v: str) -> str:
    return v.replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t")

def toks(v: str):
    return sorted(TOKEN.findall(norm(v)))

def quality(src: str, tr: str) -> tuple[int, str]:
    """Return a score; lower scores are rejected by the caller."""
    if not tr or "\ufffd" in tr or not HAN.search(tr):
        return (-10_000, "no-han-or-replacement")
    if toks(src) != toks(tr):
        return (-9_000, "token-mismatch")
    plain = TAG.sub(" ", tr)
    english = len(COMMON.findall(plain))
    # Full translated entries can keep proper nouns and equipment names, but
    # continuous English grammar indicates an old polluted value.
    if english >= 4:
        return (-8_000, "english-fragment")
    score = 0
    score += min(2_000, len(HAN.findall(tr)) * 5)
    score -= english * 500
    if "undefined" in tr.lower():
        score -= 4_000
    return (score, "ok")

def main() -> None:
    candidates = json.loads(BATCH.read_text(encoding="utf-8"))
    by_source: dict[str, list[tuple[str, str, int]]] = {}
    for path in DICT_FILES:
        if not path.exists():
            continue
        with path.open(encoding="utf-8-sig", newline="") as fh:
            for no, row in enumerate(csv.reader(fh, delimiter="\t"), 1):
                if len(row) < 2:
                    continue
                src, tr = norm(row[0]), norm(row[1])
                by_source.setdefault(src, []).append((tr, path.name, no))

    recovered, report = [], []
    for row in candidates:
        src = norm(row.get("match") or row.get("source") or "")
        options = by_source.get(src, [])
        ranked = []
        for tr, origin, no in options:
            score, reason = quality(src, tr)
            if score > 0:
                ranked.append((score, tr, origin, no))
        if ranked:
            score, tr, origin, no = max(ranked, key=lambda x: x[0])
            recovered.append({
                "file": row["file"], "field": row["field"],
                "source": src, "translation": tr,
                "origin": origin, "origin_line": no,
            })
            report.append(("RECOVERED", row["file"], row["field"], origin, str(no), str(score)))
        else:
            reason = "no-exact-dictionary" if not options else "all-candidates-rejected"
            report.append((reason, row["file"], row["field"], "", "", ""))

    OUT.write_text(json.dumps(recovered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with REPORT.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write("status\tfile\tfield\torigin\tline\tscore\n")
        for rec in report:
            fh.write("\t".join(rec) + "\n")
    print(json.dumps({"candidates": len(candidates), "recovered": len(recovered), "unresolved": len(candidates)-len(recovered), "output": str(OUT)}, ensure_ascii=False))

if __name__ == "__main__":
    main()
