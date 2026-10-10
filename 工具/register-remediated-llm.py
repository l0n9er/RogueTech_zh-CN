import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'工具'/'dict-repair.tsv'
def main():
    rows=[]
    for p in (ROOT/'backup'/'llm-batches').glob('remediated-*.zh.json'):
        try: rows+=json.loads(p.read_text(encoding='utf8'))
        except: pass
    existing=OUT.read_text(encoding='utf-8-sig') if OUT.exists() else ''
    seen=set(); add=[]
    for r in rows:
        s=r.get('source',''); t=r.get('translation','')
        if s and t and s not in seen and s not in existing:
            seen.add(s); add.append(s+'\t'+t+'\tRemediated-LLM')
    if add:
        with OUT.open('a',encoding='utf8',newline='\n') as f: f.write('\n'+'\n'.join(add)+'\n')
    print(f'注册整段修复映射={len(add)}')
if __name__=='__main__': main()
