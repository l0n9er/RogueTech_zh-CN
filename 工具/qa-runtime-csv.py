#!/usr/bin/env python3
"""运行时载具/机甲详情 CSV 审计。

JSON 字段审计无法覆盖由运行时拼接后查表的单位详情，因此这里直接检查
strings_zh-CN.csv 中的 biomerestrictions/movement/armor/weapons 条目。
"""
from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


PACK = Path(__file__).resolve().parents[1]
UNIT_MARKERS = ("*biomerestrictions:", "*movement:", "*armor:", "#weapons:")
GENERIC_ENGLISH = re.compile(
    r"\b(?:garrison|assault\s+tank|guided\s+missiles|artillery\s+rounds|"
    r"ferro-fibrous|counterparts|periphery|reloads|stealth|overhaul|"
    r"necessity|relegated|amphibious|hull(?:\s*-?mounted)?|carrier|"
    r"downgrade|\bhex\b|\bmech\b|crippling|\bjihad\b|firepower|"
    r"companion|Cavalry\s+Attack\s+Helicopter|Urban\s+Assault\s+Vehicle|"
    r"Heavy\s+(?:Hover|Tracked)\s+APC|Support\s+Transport(?:\s+Vehicle)?|"
    r"Hover\s+Scout|Advanced\s+Scout\s+Vehicle|Assault\s+Hover\s+Craft|"
    r"Weapons\s+Bay|Infantry\s+Transport\s+Bay|PPC\s+carrier|"
    r"Morningstar\s+City\s+Command\s+Vehicle|The\s+Yellow\s+Jacket)\b",
    re.IGNORECASE,
)
LONG_ENGLISH = re.compile(r"(?:\b[A-Za-z][A-Za-z0-9/-]*\b\s+){3}\b[A-Za-z][A-Za-z0-9/-]*\b")


def has_orphan_fs(text: str) -> bool:
    parts = re.split(r"(\[\[.*?\]\])", text, flags=re.DOTALL)
    return any(chr(31) in parts[i] for i in range(0, len(parts), 2))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=str(PACK / "strings_zh-CN.csv"))
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    rows = []
    targeted = 0
    issues: list[tuple[str, int, str]] = []
    with open(args.csv, encoding="utf-8-sig", newline="") as fh:
        for no, row in enumerate(csv.reader(fh), 1):
            if len(row) < 2:
                continue
            key, value = row[0], row[1]
            if not any(marker in key.lower() for marker in UNIT_MARKERS):
                continue
            targeted += 1
            plain = re.sub(r"<[^>]+>|\\r|\\n|\x1f", " ", value)
            checks = []
            if "newlinenewline" in value.lower():
                checks.append("残留newlinenewline")
            if "#weapons:" in value.lower():
                checks.append("残留#Weapons")
            if has_orphan_fs(value):
                checks.append("正文控制字符")
            if re.search(r"</color></b>\s{2,}<b>|</color>\s{2,}<b>", value):
                checks.append("段落间空格未换行")
            if LONG_ENGLISH.search(plain):
                checks.append("连续英文短语")
            if GENERIC_ENGLISH.search(plain):
                checks.append("通用英文残留")
            if checks:
                issues.append(("、".join(checks), no, plain[:260]))
            rows.append((no, key))
    lines = [
        f"运行时 CSV 审计：条目={targeted}，问题={len(issues)}",
        "状态：通过" if not issues else "状态：失败",
    ]
    for kind, no, sample in issues[:100]:
        lines.append(f"{kind}\trow {no}\t{sample}")
    report = "\n".join(lines) + "\n"
    if args.out:
        Path(args.out).write_text(report, encoding="utf-8")
    print(report, end="")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
