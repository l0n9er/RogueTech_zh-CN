import json, re, importlib.util
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = Path(__file__).resolve().parents[1]
B = ROOT / 'backup'
src = json.loads((B / 'translation-extra-input-3.json').read_text(encoding='utf-8'))
map_path = B / 'translation-extra-output-3-translations.json'
translations = json.loads(map_path.read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('gt', ROOT / '工具' / 'translate-unit-fields.py')
gt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gt)

def valid_tokens(source, value):
    tag = re.compile(r'</?[A-Za-z][^>]*>')
    return sorted(tag.findall(source)) == sorted(tag.findall(value)) and source.count('\\n') == value.count('\\n')

def run(row):
    value = gt.google_translate(row['source'])
    if not valid_tokens(row['source'], value):
        raise ValueError('token mismatch ' + row['id'])
    return row['id'], value

pending = [row for row in src if row['id'] not in translations]
print('pending', len(pending))
with ThreadPoolExecutor(max_workers=8) as pool:
    jobs = {pool.submit(run, row): row['id'] for row in pending}
    done = 0
    for future in as_completed(jobs):
        ident, value = future.result()
        translations[ident] = value
        done += 1
        if done % 10 == 0:
            map_path.write_text(json.dumps(translations, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            print(done, '/', len(pending))
map_path.write_text(json.dumps(translations, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

out = []
for row in src:
    value = translations[row['id']]
    if not valid_tokens(row['source'], value):
        raise ValueError('final token mismatch ' + row['id'])
    item = {k: row[k] for k in row if k != 'translation'}
    item['translation'] = value
    out.append(item)
(B / 'translation-extra-output-3.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('output', len(out))
