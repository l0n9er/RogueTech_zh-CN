import json, shutil
from pathlib import Path
GAME=Path(r'H:\\SteamLibrary\\steamapps\\common\\BATTLETECH'); ROOT=Path(__file__).resolve().parents[1]; BACK=ROOT/'backup'/'Mods-mackie-sticker'
for p in [*GAME.glob('Mods/Optionals/PirateTech/Base/chassis/*mackie_MSK-P.json'),*GAME.glob('Mods/Optionals/PirateTech/Base/mech/*mackie_MSK-P.json')]:
    if not p.exists(): continue
    d=json.loads(p.read_text(encoding='utf-8-sig')); s=d.get('Description',{}).get('Details','')
    if '<3大自然' not in s: continue
    b=BACK/p.relative_to(GAME/'Mods'); b.parent.mkdir(parents=True,exist_ok=True)
    if not b.exists(): shutil.copy2(p,b)
    d['Description']['Details']=s.replace('<3大自然','＜3大自然')
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('fixed',p)
