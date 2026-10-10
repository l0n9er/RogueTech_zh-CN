#!/usr/bin/env python3
"""修复运行时整段载具/机甲本地化条目。

这些条目由运行时把 Details、统计表和武器列表拼成一个字符串后查 CSV。
旧版批量合并时把 newlinenewline 压成了空格，并残留少量英文标签；JSON
字段本身正常，因此必须在 CSV 这条链路上修复。
"""
from __future__ import annotations

import csv
import re
import argparse
from pathlib import Path


PACK = Path(__file__).resolve().parents[1]


def replace_terms(text: str) -> str:
    # 仅处理运行时 Details 中明确属于界面标签/通用单位类别的词，保留武器型号、
    # 派系、公司和机甲专名，避免把合法专名误译成普通中文。
    terms = [
        # 运行时详情中仍会直接透出的一批通用英文短语。机型、厂商等专名保留，
        # 这里仅替换确定属于界面文本或通用描述的部分。
        (r"\bThe Morningstar City Command Vehicle\b", "晨星城市指挥车"),
        (r"\bThe Morningstar\b", "晨星"),
        (r"\bMachine Gun\b", "机枪"),
        (r"\bMachinegun\b", "机枪"),
        (r"\bAnti Missile System\b", "反导弹系统"),
        (r"\bQuick Off The Line\b", "启动迅速"),
        (r"\brelegated to the pages of history\b", "成为历史"),
        (r"\bJES II Strategic Missile Carrier\b", "JES II战略导弹运载车"),
        (r"\bR10 Mechanized Infantry Combat Vehicle \(ICV\)\b", "R10机械化步兵战车（ICV）"),
        (r"\bThe Schrek II-X\b", "Schrek II-X"),
        (r"\bThe Scapha Hovertank\b", "Scapha悬浮坦克"),
        (r"\bScapha Hovertank\b", "Scapha悬浮坦克"),
        (r"\bvenerable combat vehicle\b", "久负盛名的战斗载具"),
        (r"\bvenerable SRM/LRM carriers\b", "久负盛名的SRM/LRM运载车"),
        (r"\bExtra-Extralight Fusion Engine\b", "超超轻型聚变引擎"),
        (r"\bExtra-Extralight Fusion\b", "超超轻型聚变"),
        (r"\bRepublic Standing Guard\b", "共和国常备卫队"),
        (r"\bPrefectures\b", "行政区"),
        (r"\bPod space\b", "吊舱空间"),
        (r"\bPodspace\b", "吊舱空间"),
        (r"\bModel O Class LB\b", "O型LB"),
        (r"\bThe Yellow Jacket\b", "黄蜂"),
        (r"\bmedium lasers\b", "中型激光"),
        (r"\bmedium laser\b", "中型激光"),
        (r"\bguided missiles\b", "制导导弹"),
        (r"\bsalvaged wrecks\b", "打捞残骸"),
        (r"\bclantech\b", "氏族技术"),
        (r"\bFusion Engine\b", "聚变引擎"),
        (r"\bFusion\s+Engine\b", "聚变引擎"),
        (r"\bHeavy Hover APC\b", "重型气垫装甲运兵车"),
        (r"\bHeavy Tracked APC\b", "重型履带式装甲运兵车"),
        (r"\bFoot Infantry\b", "徒步步兵"),
        (r"\bMotorized Infantry\b", "摩托化步兵"),
        (r"\bJump Infantry\b", "跳跃步兵"),
        (r"\bMotorized\b", "摩托化"),
        (r"\bJump Infantry\b", "跳跃步兵"),
        (r"\bInfantry Bay\b", "步兵舱"),
        (r"\bMachine Guns?\b", "机枪"),
        (r"\bStar League\b", "星际联盟"),
        (r"\bBiome Restrictions?\b", "生物群系限制"),
        (r"\bMovement\b", "移动"),
        (r"\bArmor\b", "装甲"),
        (r"\bStructure\b", "结构"),
        (r"\bValues\b", "数值"),
        (r"\bFront\b", "正面"),
        (r"\bLeft\b", "左侧"),
        (r"\bRight\b", "右侧"),
        (r"\bRear\b", "后方"),
        (r"\bTotal\b", "总计"),
        (r"\bQuirk\b", "特性"),
        (r"\bRugged\b", "坚固"),
        (r"\bCan Resupply/Repair\b", "可补给/维修"),
        (r"\bHas firing ports\b", "设有射击孔"),
        (r"\bLunar\b", "月球"),
        (r"\bMartian\b", "火星"),
        (r"\bICE\b", "内燃机"),
        (r"\bAmmunition\b", "弹药"),
        (r"\bEquipment\b", "装备"),
        (r"\bEngine\b", "引擎"),
        (r"\bStandard Fusion\b", "标准聚变"),
        (r"\bStandard Fusion Engine\b", "标准聚变引擎"),
    ]
    # \b 在 Python 的 Unicode 正则中会把汉字视为“单词字符”，因此英文短语
    # 紧邻汉字时（例如 ``JES II ...是``）无法命中。先做一次字面量替换，
    # 再用正则处理被空格/标点包围的情况。
    literal_terms = {
        "JES II Strategic Missile Carrier": "JES II战略导弹运载车",
        "Scimitar Mk II Hover Combat Vehicle (HCV)": "Scimitar Mk II悬浮战斗载具（HCV）",
        "Type Sierra LB-X AC": "Sierra型LB-X自动炮",
        "FireFire LSR-Launcher XX LRM-20": "FireFire LSR发射器XX LRM-20",
        "House Liao": "廖氏",
        "Quick Off The Line": "启动迅速",
        "The Morningstar City Command Vehicle": "晨星城市指挥车",
        "The Morningstar": "晨星",
        "Machine Gun": "机枪",
        "Machinegun": "机枪",
        "Anti Missile System": "反导弹系统",
        "medium lasers": "中型激光",
        "medium laser": "中型激光",
        "relegated to the pages of history": "成为历史",
        "venerable combat vehicle": "久负盛名的战斗载具",
        "Extra-Extralight Fusion Engine": "超超轻型聚变引擎",
        "Extra-Extralight Fusion": "超超轻型聚变",
        "Republic Standing Guard": "共和国常备卫队",
        "Prefectures": "行政区",
        "Pod space": "吊舱空间",
        "Podspace": "吊舱空间",
        "garrison": "驻军",
        "assault tank": "突击坦克",
        "depleted": "被削弱的",
        "guided missiles": "制导导弹",
        "artillery rounds": "炮兵炮弹",
        "ferro-fibrous": "铁纤维",
        "counterparts": "同类车辆",
        "periphery": "外围",
        "reloads": "再装填弹药",
        "stealth": "隐形",
        "overhaul": "大修",
        "necessity": "必需品",
        "relegated": "降为二线",
        "amphibious": "两栖",
        "hull mounted": "车体安装的",
        "hull-mounted": "车体安装的",
        "ICE": "内燃机",
        "Lunar": "月球",
        "Martian": "火星",
        "Fusion Engine": "聚变引擎",
        "XL Engine": "XL引擎",
        "Standard Fusion": "标准聚变",
        "rated": "额定",
        "venerable": "久负盛名的",
        "boondoggle": "无意义的浪费项目",
        "carrier": "运载车",
        "downgrade": "降级",
        "hex": "格",
        "mech": "机甲",
        "crippling": "致命的",
        "jihad": "圣战",
        "firepower": "火力",
        "companion": "搭档",
        "hull": "车体",
        "Fire and Forget": "发射后不管",
        "Advanced Optics": "高级光学",
        "Cavalry Attack Helicopter": "骑兵攻击直升机",
        "Morningstar City Command Vehicle": "晨星城市指挥车",
        "Urban Assault Vehicle": "城市突击载具",
        "Heavy Hover APC": "重型气垫装甲运兵车",
        "Heavy Tracked APC": "重型履带式装甲运兵车",
        "Foot Infantry": "徒步步兵",
        "Motorized Infantry": "摩托化步兵",
        "Jump Infantry": "跳跃步兵",
        "Star League": "星际联盟",
        "Infantry Bay": "步兵舱",
        "Support Transport Vehicle": "支援运输车",
        "Hover Scout": "悬浮侦察车",
        "Advanced Scout Vehicle": "高级侦察载具",
        "Assault Hover Craft": "突击气垫船",
        "Assault VTOL": "突击VTOL",
        "Weapons Bay": "武器舱",
        "Infantry Transport Bay": "步兵运输舱",
        "Schrek PPC carrier": "Schrek PPC运载车",
        "PPC carrier": "PPC运载车",
        "Schrek PPC Carrier": "Schrek PPC运载车",
        "Partisan Hull Defense": "Partisan车体防御坦克",
        "Partisan Hull": "Partisan车体",
        "MHI Amphibious APC": "MHI两栖装甲运兵车",
        "Stealth Assault Bomber": "隐形攻击轰炸机",
        "Laser Carrier": "激光运载车",
        "Karnov (BA Stealth)": "Karnov（战甲隐形）",
        "Hellespont 'Mech Works": "Hellespont机甲工厂",
        "The Yellow Jacket": "黄蜂",
        "Yellow Jacket": "黄蜂",
        "combat vehicle": "战斗载具",
        "combat vehicles": "战斗载具",
        "Assault mech": "突击机甲",
        "battlemechs": "战斗机甲",
        "fighter mechs": "战斗机甲",
        "Rocket": "火箭",
        "inner Sphere": "内层星域",
        "Inner Sphere": "内层星域",
    }
    for source, value in literal_terms.items():
        text = text.replace(source, value)
    for pattern, value in terms:
        text = re.sub(pattern, value, text, flags=re.IGNORECASE)
    # 典型 LLM 混杂短语。
    text = text.replace("hostile 和 exotic", "敌对和异域")
    text = text.replace(" hostile and exotic ", " 敌对和异域 ")
    return text


def add_layout(text: str, key: str) -> str:
    """按原始 key 的 newlinenewline/newline 结构恢复可见换行。"""
    fs = chr(31)
    text = re.sub(r"\s*" + re.escape(fs) + r"\s*", fs, text)
    # 0x1F 在 CSV 中只应作为 [[别名<0x1F>{字段}]] 的内部分隔符。
    # 旧批次把它错误地写进了单位正文，导致正文中出现控制字符；保护别名块，
    # 将正文中的 0x1F 还原为空格。
    chunks = re.split(r"(\[\[.*?\]\])", text, flags=re.DOTALL)
    for i in range(0, len(chunks), 2):
        chunks[i] = chunks[i].replace(fs, " ")
    text = "".join(chunks)
    text = text.replace("#Weapons:", "#武器:")

    # CSV 值使用字面量 \\n，而不是物理换行，避免破坏逐行本地化表。
    nl = r"\n"
    # 首个统计块前的段落分隔；旧条目常被压成两个空格。
    if (
        ("newlinenewline" in key or "*biomerestrictions:" in key or "*movement:" in key)
        and nl not in text
    ):
        text = re.sub(r"\s*(<b><color=)", lambda m: nl + nl + m.group(1), text, count=1)
    # 旧版条目在第一个色块后保留了 </b>，形成 </color></b>  <b>；
    # 新版条目则通常只有 </color>。两种格式都要恢复段落换行。
    text = re.sub(r"</color></b>\s{2,}<b><color=", lambda m: "</color></b>" + nl + nl + "<b><color=", text)
    text = re.sub(r"</color>\s{2,}<b><color=", lambda m: "</color>" + nl + nl + "<b><color=", text)
    text = re.sub(r"</color></b>\s{2,}<color=", lambda m: "</color></b>" + nl + nl + "<color=", text)
    text = re.sub(r"</color>\s{2,}<color=", lambda m: "</color>" + nl + nl + "<color=", text)
    text = re.sub(r"</color></b>\s{2,}#武器:", lambda m: "</color></b>" + nl + "#武器:", text)
    text = re.sub(r"</color>\s{2,}#武器:", lambda m: "</color>" + nl + "#武器:", text)

    # 装甲统计表中的每个 <b> 行必须单独占一行。只处理富文本区块，避免
    # 影响正文中的普通标签。
    def color_block(match: re.Match[str]) -> str:
        block = match.group(0)
        block = re.sub(r"\s+(?=<b>)", lambda m: nl, block)
        return block

    text = re.sub(r"<color=[^>]+>.*?</color>", color_block, text, flags=re.DOTALL)
    # 已有换行条目也统一规范 #武器 标题。
    text = text.replace("  #武器:", nl + "#武器:")
    return text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", default=str(PACK / "strings_zh-CN.csv"))
    args = parser.parse_args()
    csv_path = Path(args.csv)
    raw = csv_path.read_text(encoding="utf-8-sig")
    lines = raw.splitlines(keepends=True)
    changed = 0
    targeted = 0
    out: list[str] = []
    for line in lines:
        body = line.rstrip("\r\n")
        eol = line[len(body):]
        pos = body.find(",")
        if pos <= 0:
            out.append(line)
            continue
        key, value = body[:pos], body[pos + 1 :]
        # 仅处理实际包含单位详情统计块的键。单独的 newlinenewline
        # 也出现在事件、教程和剧情文本中，不能把它们误当作单位详情。
        is_runtime_unit = (
            "#weapons" in key.lower()
            or "*biomerestrictions:" in key
            or "*movement:" in key
            or "*armor:" in key
        )
        if not is_runtime_unit:
            out.append(line)
            continue
        targeted += 1
        new_value = add_layout(replace_terms(value), key)
        if new_value != value:
            changed += 1
        out.append(key + "," + new_value + eol)
    csv_path.write_text("".join(out), encoding="utf-8", newline="")
    print(f"运行时条目: {targeted}，已修复: {changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
