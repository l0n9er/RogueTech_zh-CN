"""统一清理单位长字段中残留的英文标签/术语，避免半中文半英文污染。"""
import json, re
from pathlib import Path
GAME=Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH"); MODS=GAME/'Mods'
ROOT=Path(__file__).resolve().parents[1]; BACK=ROOT/'backup'/'Mods-unit-terms'
PAT=re.compile(r'^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)',re.I)
FIELDS={'Details','YangsThoughts'}
REPL=[
 (r'(?<![A-Za-z])Drop Cost Multiplier\s*[:：]', '部署费用倍率：'),
 (r'(?<![A-Za-z])Arm Actuator Limits?\s*[:：]', '手臂驱动器限制：'),
 (r'(?<![A-Za-z])Quirk\s*[:：]', '特性：'),
 (r'(?<![A-Za-z])This unit can not deploy in Lunar or Martian biomes due to using an ICE\.', '该单位因使用内燃机，无法在月球或火星生物群系部署。'),
 (r'(?<![A-Za-z])This unit can not deploy in Lunar biomes\.', '该单位无法在月球生物群系部署。'),
 (r'(?<![A-Za-z])medium lasers(?<![A-Za-z])', '中型激光器'), (r'(?<![A-Za-z])medium laser(?<![A-Za-z])', '中型激光器'),
 (r'(?<![A-Za-z])guided missiles(?<![A-Za-z])', '制导导弹'), (r'(?<![A-Za-z])XL engine(?<![A-Za-z])', 'XL引擎'), (r'(?<![A-Za-z])XL Engine(?<![A-Za-z])', 'XL引擎'),
 (r'(?<![A-Za-z])Engine(?<![A-Za-z])', '引擎'), (r'(?<![A-Za-z])Torso Twist(?<![A-Za-z])', '躯干扭转'),
 (r'(?<![A-Za-z])OmniVehicle(?<![A-Za-z])', '全向载具'), (r'(?<![A-Za-z])Omni Vehicle(?<![A-Za-z])', '全向载具'),
 (r'(?<![A-Za-z])Values(?<![A-Za-z])', '数值'), (r'(?<![A-Za-z])Armor(?<![A-Za-z])', '装甲'), (r'(?<![A-Za-z])Structure(?<![A-Za-z])', '结构'),
 (r'(?<![A-Za-z])Fusion\s*:', '聚变：'), (r'(?<![A-Za-z])hexes(?<![A-Za-z])', '格'), (r'(?<![A-Za-z])meters(?<![A-Za-z])', '米'),
 (r'(?<![A-Za-z])Light Ferro(?<![A-Za-z])', '轻型铁纤维装甲'), (r'(?<![A-Za-z])Ferro-Fibrous(?<![A-Za-z])', '铁纤维装甲'),
 (r'(?<![A-Za-z])Artillery(?<![A-Za-z])', '火炮'), (r'(?<![A-Za-z])Heavy Tank(?<![A-Za-z])', '重型坦克'), (r'(?<![A-Za-z])Medium Tank(?<![A-Za-z])', '中型坦克'),
 (r'(?<![A-Za-z])Scout Tank(?<![A-Za-z])', '侦察坦克'), (r'(?<![A-Za-z])Combat Vehicle(?<![A-Za-z])', '战斗车辆'),
]
LITERAL=[('guided missiles','制导导弹'),('medium lasers','中型激光器'),('medium laser','中型激光器'),('XL engine','XL引擎'),('XL Engine','XL引擎'),('Drop Cost Multiplier:','部署费用倍率：'),('Arm Actuator Limits:','手臂驱动器限制：'),('Quirk:','特性：')]
compiled=[(re.compile(a,re.I),b) for a,b in REPL]
def walk(x):
 if isinstance(x,dict):
  for k,v in x.items():
   if k in FIELDS and isinstance(v,str): yield x,k,v
   yield from walk(v)
 elif isinstance(x,list):
  for y in x: yield from walk(y)
changed=files=0
for p in MODS.rglob('*.json'):
 if not PAT.match(p.name) or '.modtek' in str(p).lower(): continue
 try: obj=json.loads(p.read_text(encoding='utf8'))
 except: continue
 n=0
 for parent,key,value in walk(obj):
  new=value
  for rx,to in compiled:new=rx.sub(to,new)
  for old,to in LITERAL:new=new.replace(old,to)
  if new!=value:parent[key]=new;n+=1
 if n:
  old=p.read_text(encoding='utf8');dst=BACK/p.relative_to(MODS);dst.parent.mkdir(parents=True,exist_ok=True)
  if not dst.exists():dst.write_text(old,encoding='utf8')
  p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf8');files+=1;changed+=n
print(f'术语归一化：字段={changed} 文件={files}')
