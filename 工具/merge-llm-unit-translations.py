#!/usr/bin/env python3
"""合并子智能体翻译并写回单位定义；严格校验占位符/标签后才落盘。"""
import json, re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
GAME=Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH")
MODS=GAME/'Mods'; BATCH=ROOT/'backup'/'llm-batches'; BACKUP=ROOT/'backup'/'Mods-llm'
OUT=ROOT/'工具'/'dict-unit-llm.tsv'; REPORT=ROOT/'backup'/'llm-merge-report.tsv'
TARGET=re.compile(r'^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)',re.I)
FIELDS={'Details','YangsThoughts'}
HAN=re.compile(r'[\u3400-\u9fff]')
TOKEN=re.compile(r'<[^>]*>|\{[^{}]*\}|\[\[[\s\S]*?\]\]|\\[nrt]|\n')

def walk(x):
    if isinstance(x,dict):
        for k,v in x.items():
            if k in FIELDS and isinstance(v,str): yield x,k,v
            yield from walk(v)
    elif isinstance(x,list):
        for y in x: yield from walk(y)

def tokens(s): return sorted(TOKEN.findall(s))

def main():
    mapping={}; bad=[]; total=0
    for p in sorted(list(BATCH.glob('batch-*.zh.json')) + list(BATCH.glob('remaining-*.zh.json')) + list(BATCH.glob('remaining-final-*.zh.json')) + list(BATCH.glob('remaining-mixed.zh.json'))):
        try: arr=json.loads(p.read_text(encoding='utf-8'))
        except Exception as e: bad.append((p.name,'invalid json',str(e))); continue
        for row in arr:
            total+=1; src=row.get('source',''); tr=row.get('translation','')
            if not src or not tr or not HAN.search(tr): bad.append((p.name,row.get('id'),'empty/non-Chinese')); continue
            if tokens(src)!=tokens(tr): bad.append((p.name,row.get('id'),'placeholder mismatch')); continue
            if src in mapping and mapping[src]!=tr: bad.append((p.name,row.get('id'),'duplicate source')); continue
            mapping[src]=tr
    candidates={}
    for p in MODS.rglob('*.json'):
        if not TARGET.match(p.name) or '.modtek' in str(p).lower(): continue
        try: obj=json.loads(p.read_text(encoding='utf-8'))
        except Exception: continue
        for parent,key,value in walk(obj):
            if value in mapping: candidates.setdefault(p,[]).append((parent,key,value))
    changed=0; files=0
    for p,items in candidates.items():
        old=p.read_text(encoding='utf-8'); obj=json.loads(old); n=0
        # 重新遍历当前对象，不能使用首次扫描的旧引用。
        for parent,key,value in walk(obj):
            if value in mapping:
                parent[key]=mapping[value]; n+=1
        if n:
            dst=BACKUP/p.relative_to(MODS); dst.parent.mkdir(parents=True,exist_ok=True)
            if not dst.exists(): dst.write_text(old,encoding='utf-8')
            p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            changed+=n; files+=1
    OUT.parent.mkdir(exist_ok=True)
    with OUT.open('w',encoding='utf-8',newline='\n') as f:
        for s,t in mapping.items(): f.write(s.replace('\n','\\n')+'\t'+t.replace('\n','\\n')+'\tLLM\n')
    with REPORT.open('w',encoding='utf-8',newline='\n') as f:
        f.write('status\tfile_or_id\tdetail\n')
        for row in bad: f.write('\t'.join(map(str,row))+'\n')
    print(f'翻译条目={len(mapping)} 输入条目={total} 无效={len(bad)} 修改字段={changed} 修改文件={files}')
    if bad: print(f'未合并清单: {REPORT}')

if __name__=='__main__': main()
