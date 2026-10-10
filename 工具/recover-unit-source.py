#!/usr/bin/env python3
"""Recover complete unit text from the pre-fold backup and apply trusted ZH overlays.

This deliberately replaces whole fields. It never splices individual English words into
the current value, which was the source of the mixed-language corruption.
"""
import json, re, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH")
MODS = GAME / "Mods"
BASE = ROOT / "backup" / "Mods-defs"
REPORT = ROOT / "backup" / "unit-scan-focus.jsonl"
BACKUP = ROOT / "backup" / "Mods-source-recovery"
TARGET = re.compile(r"^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)", re.I)
FIELDS = {"Details", "YangsThoughts"}

def walk(x):
    if isinstance(x, dict):
        for k, v in x.items():
            if k in FIELDS and isinstance(v, str): yield x, k, v
            yield from walk(v)
    elif isinstance(x, list):
        for y in x: yield from walk(y)

def get_field(obj, dotted):
    v = obj
    for part in dotted.split('.'):
        v = v[part]
    return v

def norm(s):
    return s.replace('\\r\\n', '\\n').replace('\\n', '\n').replace('\r\n', '\n').strip()

def load_overlays():
    """Map basename.field to a trusted CULTURE_ZH_CN value."""
    out = {}
    for p in MODS.rglob('Localization.json'):
        if '\\localization\\' not in str(p).lower() and not p.name.lower() == 'localization.json':
            continue
        try: rows = json.loads(p.read_text(encoding='utf-8-sig'))
        except Exception: continue
        if not isinstance(rows, list): continue
        for row in rows:
            name = str(row.get('Name',''))
            loc = row.get('Localization') or {}
            zh = loc.get('CULTURE_ZH_CN')
            if not isinstance(zh, str) or not zh.strip(): continue
            tail = name.rsplit('.', 1)
            if len(tail) != 2 or tail[1] not in FIELDS: continue
            key = tail[0].split('.', 1)[-1] + '.' + tail[1]
            # Only accept a ZH value that is not an unchanged English source.
            if re.search(r'[\u3400-\u9fff]', zh): out[key] = zh
    return out

def main():
    overlays = load_overlays()
    rows = [json.loads(x) for x in REPORT.read_text(encoding='utf-8').splitlines() if x.strip()]
    changed = trusted = recovered = 0; files = set(); missing=[]
    for row in rows:
        if row.get('type') != 'mixed_sentence': continue
        p = Path(row['file']); rel = p.relative_to(MODS); srcp = BASE / rel
        if not srcp.exists(): missing.append(str(rel)); continue
        try:
            cur = json.loads(p.read_text(encoding='utf-8-sig'))
            src = json.loads(srcp.read_text(encoding='utf-8-sig'))
            old = get_field(cur, row['field']); original = get_field(src, row['field'])
        except Exception: continue
        if not isinstance(original, str) or not original.strip(): continue
        replacement = None
        key = ('chassisdef_' if p.name.startswith('chassisdef_') else
               'mechdef_' if p.name.startswith('mechdef_') else
               'vehiclechassisdef_' if p.name.startswith('vehiclechassisdef_') else
               'vehicledef_' if p.name.startswith('vehicledef_') else
               'weapondef_' if p.name.startswith('weapondef_') else
               'ammunitionBoxDef_' if p.name.startswith('ammunitionBoxDef_') else '')
        key = key + p.stem[len(key):] + '.' + row['field'].split('.')[-1]
        if key in overlays and len(re.findall(r'[\u3400-\u9fff]', overlays[key])) >= 2:
            replacement = overlays[key]; trusted += 1
        # Source recovery is intentionally recorded but not written as English.
        # It gives the LLM batch a clean source and prevents further corruption.
        if replacement is None:
            recovered += 1
            continue
        if norm(old) == norm(replacement): continue
        obj = cur; parts = row['field'].split('.')
        for part in parts[:-1]: obj = obj[part]
        obj[parts[-1]] = replacement
        bak = BACKUP / rel; bak.parent.mkdir(parents=True, exist_ok=True)
        if not bak.exists(): shutil.copy2(p, bak)
        p.write_text(json.dumps(cur, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        changed += 1; files.add(p)
    (ROOT/'backup'/'unit-source-missing.tsv').write_text('\n'.join(missing)+'\n', encoding='utf-8')
    print(f'可信 ZH overlay={trusted} 可恢复英文源待翻译={recovered} 已回写字段={changed} 文件={len(files)} 缺少基线={len(missing)}')

if __name__ == '__main__': main()
