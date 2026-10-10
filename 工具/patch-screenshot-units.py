import json, shutil
from pathlib import Path
GAME=Path(r'H:\\SteamLibrary\\steamapps\\common\\BATTLETECH'); ROOT=Path(__file__).resolve().parents[1]; BACK=ROOT/'backup'/'Mods-screenshot-units'
def put(p, details, thoughts=None):
    d=json.loads(p.read_text(encoding='utf-8-sig')); old=p.read_text(encoding='utf-8'); BACK.joinpath(p.relative_to(GAME/'Mods')).parent.mkdir(parents=True,exist_ok=True); b=BACK/p.relative_to(GAME/'Mods')
    if not b.exists(): shutil.copy2(p,b)
    d['Description']['Details']=details
    if thoughts is not None: d['YangsThoughts']=thoughts
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
mad=('掠夺者 II 于 3012 年问世，是经典掠夺者的重新设计，把 75 吨重型机甲变成 100 吨突击机甲。它最初是狼之龙骑兵的专属机甲，直到 3030 年第四次继承战争之后才流传到龙骑兵之外。MAD-6C 型掠夺者 II 由一台额定 300 的聚变核心驱动，装备三门增程粒子加农炮和两门增程中型激光器。')
blocks='\n\n<b><color=#e62e00>特性：窄小低矮轮廓</color></b>\n\n<b><color=#e62e00>部署费用倍率：1.18</color></b>\n\n<color=#FFEF00>手臂驱动器限制：左下臂、右下臂</color>'
for p in [GAME/'Mods/Eras/DarkAge3131-/Base/chassis/chassisdef_marauder_ii_MAD-6C.json',GAME/'Mods/Eras/DarkAge3131-/Base/mech/mechdef_marauder_ii_MAD-6C.json']:
    if p.exists(): put(p,mad+blocks,mad)
for p in [GAME/'Mods/Eras/ClanInvasion3061/Base/chassis/chassisdef_falcon_hawk_FNHK-9K1A.json',GAME/'Mods/Eras/ClanInvasion3061/Base/mech/mechdef_falcon_hawk_FNHK-9K1A.json']:
    if p.exists():
        d=json.loads(p.read_text(encoding='utf-8-sig')); s=d['Description']['Details'].replace('Falcon Hawk','隼鹰'); d['Description']['Details']=s; d['YangsThoughts']=d.get('YangsThoughts','').replace('Falcon Hawk','隼鹰'); p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('截图单位已修正')
