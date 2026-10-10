import json,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; MODS=Path(r'H:\\SteamLibrary\\steamapps\\common\\BATTLETECH\\Mods'); BACK=ROOT/'backup'/'Mods-remediated-llm'
HAN=re.compile(r'[\u3400-\u9fff]'); BAD=re.compile(r'\b(?:Powered by|is armed with|was designed|This variant|The\s+\w+\s+is|Left Lower|Right Lower)\b|\ufffd',re.I); TOK=re.compile(r'<[^>]*>|\\[nrt]|\n|\{[^{}]*\}|\[\[[\s\S]*?\]\]')
def toks(s): return sorted(TOK.findall(s))
def setv(o,f,v):
 x=o; p=f.split('.')
 for k in p[:-1]: x=x[k]
 x[p[-1]]=v
def main():
 rows=[]; bad=0
 for p in ROOT.joinpath('backup','llm-batches').glob('remediated-*.zh.json'):
  try: rows+=json.loads(p.read_text(encoding='utf8'))
  except: pass
 changed=files=0
 for r in rows:
  fn=r.get('file',''); f=r.get('field',''); s=r.get('source',''); t=r.get('translation','')
  if not fn or not f or not s or not t or not HAN.search(t) or BAD.search(t) or toks(s)!=toks(t): bad+=1; continue
  p=Path(fn); p=Path(str(p).replace('H:\\SteamLibrary\\steamapps\\common\\BATTLETECH\\Mods',str(MODS))) if p.is_absolute() else MODS/p
  if not p.exists(): continue
  try:o=json.loads(p.read_text(encoding='utf-8-sig')); cur=o
  except: continue
  try:
   for k in f.split('.'): cur=cur[k]
   if cur==t: continue
   b=BACK/p.relative_to(MODS); b.parent.mkdir(parents=True,exist_ok=True)
   if not b.exists(): shutil.copy2(p,b)
   setv(o,f,t); p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf8'); changed+=1; files+=1
  except: continue
 print(f'待审条目={len(rows)} 拒绝={bad} 回写字段={changed} 文件={files}')
if __name__=='__main__':main()
