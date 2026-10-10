import json,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MODS=Path(r'H:\\SteamLibrary\\steamapps\\common\\BATTLETECH\\Mods')
BACK=ROOT/'backup'/'Mods-safe-batch'
HAN=re.compile(r'[\u3400-\u9fff]')
BAD=re.compile(r'\b(?:Powered by|is armed with|was designed|This variant|The\s+\w+\s+is|Left Lower|Right Lower)\b|\ufffd',re.I)
TOK=re.compile(r'<[^>]*>|\\[nrt]|\n|\{[^{}]*\}|\[\[[\s\S]*?\]\]')
def toks(s): return sorted(TOK.findall(s))
def walk(x):
    if isinstance(x,dict):
        for k,v in x.items():
            if k in ('Details','YangsThoughts') and isinstance(v,str): yield x,k,v
            yield from walk(v)
    elif isinstance(x,list):
        for y in x: yield from walk(y)
def main():
    mp={}
    for p in (ROOT/'backup'/'llm-batches').glob('*.zh.json'):
        try: a=json.loads(p.read_text(encoding='utf8'))
        except: continue
        for x in a:
            s=x.get('source',''); t=x.get('translation','')
            if s and t and HAN.search(t) and not BAD.search(t) and toks(s)==toks(t): mp[s]=t
    changed=files=0
    for p in MODS.rglob('*.json'):
        if not re.match(r'^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)',p.name,re.I): continue
        try: o=json.loads(p.read_text(encoding='utf8-sig'))
        except: continue
        n=0
        for par,k,v in walk(o):
            if v in mp and mp[v]!=v: par[k]=mp[v]; n+=1
        if n:
            b=BACK/p.relative_to(MODS); b.parent.mkdir(parents=True,exist_ok=True)
            if not b.exists(): shutil.copy2(p,b)
            p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf8'); changed+=n; files+=1
    print(f'安全整段词典={len(mp)} 回写字段={changed} 文件={files}')
if __name__=='__main__': main()
