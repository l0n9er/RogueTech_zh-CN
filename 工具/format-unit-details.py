#!/usr/bin/env python3
import json, re, shutil
from pathlib import Path
GAME=Path(r'H:\\SteamLibrary\\steamapps\\common\\BATTLETECH'); MODS=GAME/'Mods'; ROOT=Path(__file__).resolve().parents[1]; BACK=ROOT/'backup'/'Mods-format-details'
PAT=re.compile(r'^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)',re.I)
def walk(x):
    if isinstance(x,dict):
        for k,v in x.items():
            if k in ('Details','YangsThoughts') and isinstance(v,str): yield x,k,v
            yield from walk(v)
    elif isinstance(x,list):
        for y in x: yield from walk(y)
def fmt(s):
    s=re.sub(r'\s*<<NL>\s*', '\\n\\n', s)
    s=re.sub(r'[ \t]+(<b><color=)',r'\n\n\1',s)
    s=re.sub(r'[ \t]+(<color=#FFEF00>)',r'\n\n\1',s)
    s=re.sub(r'(?<!\n)(<b><color=)',r'\n\n\1',s)
    s=re.sub(r'\n{3,}','\n\n',s)
    for a,b in [('Left Lower','左下臂'),('Right Lower','右下臂'),('Left Upper','左上臂'),('Right Upper','右上臂')]: s=re.sub(r'(?i)\b'+a+r'\b',b,s)
    return s.strip()
def main():
    changed=files=0
    for p in MODS.rglob('*.json'):
        if not PAT.match(p.name) or '.modtek' in str(p).lower(): continue
        try: obj=json.loads(p.read_text(encoding='utf-8-sig'))
        except: continue
        n=0
        for par,k,v in walk(obj):
            z=fmt(v)
            if z!=v: par[k]=z; n+=1
        if n:
            dst=BACK/p.relative_to(MODS); dst.parent.mkdir(parents=True,exist_ok=True)
            if not dst.exists(): shutil.copy2(p,dst)
            p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); changed+=n; files+=1
    print(f'格式化字段={changed} 文件={files}')
if __name__=='__main__': main()
