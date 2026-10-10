#!/usr/bin/env python3
"""Apply reviewed LLM translations by file and field, never by loose fragments."""
import json, re, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; GAME=Path(r'H:\SteamLibrary\steamapps\common\BATTLETECH'); MODS=GAME/'Mods'; BACK=ROOT/'backup'/'Mods-llm-location'; BATCH=ROOT/'backup'/'llm-batches'
HAN=re.compile(r'[\u3400-\u9fff]'); TOK=re.compile(r'<[^>]*>|\\[nrt]|\n|\{[^{}]*\}|\[\[[\s\S]*?\]\]')
def toks(s): return sorted(TOK.findall(s))
def setfield(obj,field,val):
 p=field.split('.'); x=obj
 for k in p[:-1]: x=x[k]
 x[p[-1]]=val
def main():
 mp={}; bad=[]
 for p in sorted([BATCH/'full-a.zh.json', BATCH/'full-b.zh.json', BATCH/'remaining-1.zh.json', BATCH/'remaining-3.zh.json', BATCH/'remaining-final-1.zh.json', BATCH/'remaining-final-2.zh.json', BATCH/'remaining-mixed.zh.json']):
  if not p.exists(): continue
  try: arr=json.loads(p.read_text(encoding='utf8'))
  except: continue
  for row in arr:
   src=row.get('source',''); tr=row.get('translation',''); fn=row.get('file',''); field=row.get('field','')
   if not fn or not field or not src or not tr or not HAN.search(tr): continue
   if re.search(r'\b(?:Powered by|is armed with|was designed|The\s+\w+\s+is|This variant|Left Lower|Right Lower)\b|\ufffd', tr, re.I): continue
   if toks(src)!=toks(tr): bad.append((p.name,fn,field,'token')); continue
   # Absolute paths are stored in previous batches; normalize to current path.
   fp=Path(fn)
   if not fp.is_absolute(): fp=MODS/fp
   key=(str(fp).lower(),field)
   mp[key]=tr
 changed=files=0
 for p in MODS.rglob('*.json'):
  keyprefix=str(p).lower()
  entries=[(k[1],v) for k,v in mp.items() if k[0]==keyprefix]
  if not entries: continue
  try: obj=json.loads(p.read_text(encoding='utf-8-sig'))
  except: continue
  old=p.read_text(encoding='utf8'); n=0
  for field,tr in entries:
   try:
    parts=field.split('.'); x=obj
    for q in parts[:-1]: x=x[q]
    if isinstance(x.get(parts[-1]),str) and x[parts[-1]]!=tr:
     x[parts[-1]]=tr; n+=1
   except: pass
  if n:
   dst=BACK/p.relative_to(MODS); dst.parent.mkdir(parents=True,exist_ok=True)
   if not dst.exists(): shutil.copy2(p,dst)
   p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf8'); changed+=n;files+=1
 print(f'location mappings={len(mp)} bad_tokens={len(bad)} changed_fields={changed} files={files}')
 (ROOT/'backup'/'llm-location-bad.tsv').write_text('\n'.join('\t'.join(x) for x in bad),encoding='utf8')
if __name__=='__main__': main()
