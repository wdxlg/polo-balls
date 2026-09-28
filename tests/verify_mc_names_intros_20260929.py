"""Check Minecraft name/armor-introduction coverage and localization consistency.
Optional --baseline points to the pre-edit checkpoint and proves combat bodies unchanged.
"""
from pathlib import Path
import csv,json,re,sys,argparse,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--baseline',type=Path);args=ap.parse_args()
    checks=0
    def check(ok,message):
        nonlocal checks
        checks+=1
        if not ok: raise AssertionError(message)
    with (ROOT/'translations.csv').open(encoding='utf-8-sig',newline='') as f: rows=list(csv.DictReader(f))
    table={r['keys']:r for r in rows}
    check(len(table)==len(rows),'unique translation keys')
    world=(ROOT/'scripts/world.gd').read_text(encoding='utf-8-sig')
    mapping=dict(re.findall(r'"(res://scripts/characters/我的世界/[^"]+)":"(MC_ARMOR_INTRO_[A-Z0-9_]+)"',world))
    custom=[];count=0
    forbidden=['WASD','左键','右键','中键','手控','操控','残影','材质','贴图','音效','旧版','翻倍（最新','0dB']
    for scene in sorted((ROOT/'scenes/characters/我的世界').glob('*.tscn')):
        name=scene.stem;check(name in table,name+' registered name')
        check(bool(table[name]['en'].strip()) and not re.search('[\u3400-\u9fff]',table[name]['en']),name+' English name')
        script=re.search(r'path="(res://scripts/characters/我的世界/[^"]+\.gd)"',scene.read_text(encoding='utf-8-sig')).group(1)
        check(script in mapping,name+' registered introduction')
        key=mapping[script];check(key in table,name+' translation key')
        row=table[key]
        check(0<len(row['zh'])<=220,name+' concise Chinese prose')
        check(bool(row['en']) and not re.search('[\u3400-\u9fff]',row['en']),name+' full English prose')
        check(not any(word in row['zh'] for word in forbidden),name+' combat-only text')
        source=(ROOT/script[6:]).read_text(encoding='utf-8-sig')
        match=re.search(r'^func get_armor_test_effect_summary\(\) -> String:\n(?:\t[^\n]*\n|\n)*',source,re.M)
        if match:
            custom.append(script[6:]);check(match[0].strip().endswith('return Game.t("'+key+'")'),name+' custom description uses same catalog')
        count+=1
    check(len(mapping)==count and count>=46,'all MC scenes covered exactly once')
    check(table['凋灵骷髅']['en']=='Wither Skeleton','vanilla Wither Skeleton name')
    check(table['石矛']['en']=='Stone Spear','vanilla Stone Spear name')
    check(table['钻石长矛']['en']=='Diamond Spear','vanilla Diamond Spear name')
    for key,words in {
        'MC_ARMOR_INTRO_SULFUR_CUBE':['冰','岩浆','蜂蜜','铁','紫晶','TNT','自伤'],
        'MC_ARMOR_INTRO_SKELETON':['射速','斩杀'],
        'MC_ARMOR_INTRO_WANDERING_TRADER':['羊驼','净化','隐身','入墙','补回'],
        'MC_ARMOR_INTRO_HAOCHEN':['贡献','属性减半','后代','存续'],
        'MC_ARMOR_INTRO_MACE':['上限','伤害仍可继续增长'],
    }.items():
        for word in words:check(word in table[key]['zh'],key+' includes '+word)
    if args.baseline:
        pattern=r'^func get_armor_test_effect_summary\(\) -> String:\n(?:\t[^\n]*\n|\n)*'
        for p in custom:
            before=(args.baseline/p).read_text(encoding='utf-8-sig');after=(ROOT/p).read_text(encoding='utf-8-sig')
            check(re.sub(pattern,'',before,flags=re.M).rstrip()==re.sub(pattern,'',after,flags=re.M).rstrip(),p+' gameplay unchanged')
        with (args.baseline/'translations.csv').open(encoding='utf-8-sig',newline='') as f: old=list(csv.DictReader(f))
        for row in old:check(table[row['keys']]==row,'preexisting CSV translation preserved: '+row['keys'])
    subprocess.run([sys.executable,str(ROOT/'scripts/training/sync_translation_catalog.py'),'--check'],check=True)
    print(f'MC_NAMES_INTROS_STATIC roles={count} checks={checks} failures=0')
if __name__=='__main__':main()
