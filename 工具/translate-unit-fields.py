#!/usr/bin/env python3
"""批量补全单位定义中的英文 Details/YangsThoughts。

只处理机甲、载具、武器和弹药定义；完整字段交给同一个翻译服务处理，
避免旧流程把零散术语嵌进英文长段落。翻译结果写入缓存和 TSV，后续安装
器通过 fold-apply 使用同一批完整映射。
"""
from __future__ import annotations
import hashlib, json, re, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

GAME = Path(r"H:\SteamLibrary\steamapps\common\BATTLETECH")
ROOT = Path(__file__).resolve().parents[1]
MODS = GAME / "Mods"
CACHE_PATH = ROOT / "backup" / "unit-translation-cache.json"
OUT_TSV = ROOT / "工具" / "dict-unit-auto.tsv"
BACKUP = ROOT / "backup" / "Mods-unit-auto"
TARGET = re.compile(r"^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)", re.I)
FIELDS = {"Details", "YangsThoughts"}
WORD = re.compile(r"\b[A-Za-z]{3,}\b")
HAN = re.compile(r"[\u3400-\u9fff]")
MIXED = re.compile(r"[A-Za-z]{2,}[\u3400-\u9fff]|[\u3400-\u9fff][A-Za-z]{2,}")
PROTECT = re.compile(r"<[^>]*>|\{[^{}]*\}|\[\[[\s\S]*?\]\]|\\[nrt]|\n")

def should_translate(s: str) -> bool:
    en = len(WORD.findall(s)); zh = len(HAN.findall(s))
    if en < 12:
        return False
    if zh == 0:
        return True
    # 已有中文但英文正文/标签仍混入时，整段重译，避免半翻译污染。
    return bool(MIXED.search(s) and (en >= 20 or re.search(r"\b(Quirk|Drop Cost Multiplier|Engine|medium lasers?|guided missiles?)\b", s, re.I)))

def protect(s: str):
    saved = []
    def repl(m):
        saved.append(m.group(0))
        return f"ZXQPH{len(saved)-1}QZX"
    return PROTECT.sub(repl, s), saved

def restore(s: str, saved):
    for i, value in enumerate(saved):
        s = s.replace(f"ZXQPH{i}QZX", value)
    return s

def google_translate(s: str) -> str:
    protected, saved = protect(s)
    q = urlencode({"client": "gtx", "sl": "en", "tl": "zh-CN", "dt": "t", "q": protected})
    last = None
    for attempt in range(4):
        try:
            req = Request("https://translate.googleapis.com/translate_a/single?" + q,
                          headers={"User-Agent": "Mozilla/5.0"})
            with urlopen(req, timeout=45) as r:
                data = json.loads(r.read().decode("utf-8"))
            text = "".join(part[0] for part in data[0] if part and part[0])
            text = restore(text, saved)
            if any(f"ZXQPH{i}QZX" in text for i in range(len(saved))):
                raise ValueError("placeholder lost")
            return text
        except Exception as exc:
            last = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"translation failed: {last}")

def walk(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in FIELDS and isinstance(v, str):
                yield obj, k, v
            yield from walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from walk(v)

def main():
    ROOT.joinpath("backup").mkdir(exist_ok=True)
    cache = json.loads(CACHE_PATH.read_text(encoding="utf-8")) if CACHE_PATH.exists() else {}
    files = [p for p in MODS.rglob("*.json") if TARGET.match(p.name) and ".modtek" not in str(p).lower()]
    candidates = {}
    locations = {}
    for p in files:
        try: obj = json.loads(p.read_text(encoding="utf-8"))
        except Exception: continue
        for parent, key, value in walk(obj):
            if should_translate(value):
                h = hashlib.sha1(value.encode("utf-8")).hexdigest()
                candidates.setdefault(h, value)
                locations.setdefault(h, []).append((p, parent, key))
    print(f"候选字段={sum(map(len, locations.values()))} 唯一文本={len(candidates)}")
    translated = {h: cache[h] for h in candidates if h in cache}
    pending = [(h, value) for h, value in candidates.items() if h not in cache]
    # 受控并行：公共接口允许少量并发，失败由 google_translate 自身重试。
    # 结果仍在主线程写缓存，避免并发写坏 JSON。
    with ThreadPoolExecutor(max_workers=8) as pool:
        jobs = {pool.submit(google_translate, value): h for h, value in pending}
        done = 0
        for future in as_completed(jobs):
            h = jobs[future]
            translated[h] = future.result()
            cache[h] = translated[h]
            done += 1
            if done % 10 == 0:
                CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
                print(f"已翻译 {done}/{len(pending)}")
    CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
    changed = 0
    touched = set()
    # 翻译完成后重新读取每个文件再应用映射，避免使用第一次遍历留下的
    # PSCustomObject/字典引用，保证实际写入的是当前 JSON 对象。
    for p in files:
        try: obj = json.loads(p.read_text(encoding="utf-8"))
        except Exception: continue
        file_changed = 0
        for parent, key, old in walk(obj):
            h = hashlib.sha1(old.encode("utf-8")).hexdigest()
            new = translated.get(h)
            if new and new != old and len(HAN.findall(new)) >= 2 and should_translate(old):
                parent[key] = new; file_changed += 1
        if file_changed:
            rel = p.relative_to(MODS); dst = BACKUP / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.exists(): dst.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
            p.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            touched.add(p); changed += file_changed
    with OUT_TSV.open("w", encoding="utf-8", newline="\n") as f:
        for h, value in candidates.items():
            if h in translated:
                f.write(value.replace("\n", "\\n") + "\t" + translated[h].replace("\n", "\\n") + "\tAutoGoogle\n")
    print(f"修改字段={changed} 文件={len(touched)} 输出={OUT_TSV}")

if __name__ == "__main__":
    main()
