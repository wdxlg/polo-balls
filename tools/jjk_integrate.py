"""咒术回战四角色注册（幂等）。从项目根运行：python tools/jjk_integrate.py
- classes/combat_classification_catalog.gd  SCENES / SCRIPTS
- global/translation_catalog.gd + translations.csv
- tests/manual_control_inventory.csv
- tests/test_manual_control_roster_extensions.gd
"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[1]
S = "res://scripts/characters/动漫/咒术回战/"
REVIEW = "see docs/JJK_CHARACTERS.md"

def row(kind, modes, carriers, damage, review, root_script=None):
    d = {"entity_kind": kind, "attack_modes": modes, "carriers": carriers, "damage_kinds": damage, "review": review}
    if root_script: d["root_script"] = root_script
    return d

SCENES = {
    "res://scenes/characters/动漫/五条悟.tscn": row("character", ["ranged", "melee"], ["projectile", "ray_beam", "area", "body_contact"], ["magic", "ordinary"], "infinity_blocks_non_sure_hit; blue_pull; red; purple_line; unlimited_void_closed_barrier; " + REVIEW, S + "gojo.gd"),
    "res://scenes/characters/动漫/宿傩.tscn": row("character", ["melee", "ranged"], ["ray_beam", "area", "projectile", "body_contact"], ["ordinary", "fire"], "dismantle_cleave_fuga; malevolent_shrine_whole_map; one_time_1hp_lock_world_slash; summons; " + REVIEW, S + "sukuna.gd"),
    "res://scenes/characters/动漫/魔虚罗.tscn": row("character", ["melee"], ["weapon_sweep", "area"], ["ordinary"], "adaptation_wheel_per_phenomenon; " + REVIEW, S + "mahoraga.gd"),
    "res://scenes/characters/动漫/嵌合暗兽.tscn": row("character", ["melee", "ranged"], ["body_contact", "area"], ["ordinary", "magic"], "rct_heal_aura; nue_thunder; round_deer_cleanse; " + REVIEW, S + "agito.gd"),
}
SCRIPTS = {
    S + "gojo.gd": SCENES["res://scenes/characters/动漫/五条悟.tscn"],
    S + "sukuna.gd": SCENES["res://scenes/characters/动漫/宿傩.tscn"],
    S + "mahoraga.gd": SCENES["res://scenes/characters/动漫/魔虚罗.tscn"],
    S + "agito.gd": SCENES["res://scenes/characters/动漫/嵌合暗兽.tscn"],
    S + "jjk_base.gd": row("component", [], [], [], "shared_cursed_energy_rct_black_flash_rpc_layer; " + REVIEW),
    S + "jjk_common.gd": row("component", [], [], [], "static_context_damage_helpers_and_audio_bank; " + REVIEW),
    S + "jjk_fx.gd": row("visual", [], [], [], "pure_visual_one_shot_fx; " + REVIEW),
    S + "jjk_projectile.gd": row("projectile", ["ranged"], ["projectile"], ["ordinary_or_contextual"], "authority_swept_red_and_fuga; " + REVIEW),
    S + "jjk_domain.gd": row("effect", ["area"], ["area"], ["ordinary", "magic"], "domain_expansion_sure_hit; closed_barrier_is_terrain_layer; " + REVIEW),
}
for v in list(SCENES.values()) + list(SCRIPTS.values()):
    for k in ("root_script",):
        pass
SCRIPTS = {k: {kk: vv for kk, vv in v.items() if kk != "root_script"} for k, v in SCRIPTS.items()}

def fmt(key, value):
    return "  " + json.dumps(key, ensure_ascii=False) + ": " + json.dumps(value, ensure_ascii=False, separators=(",", ":")) + ","

cat_path = root / "classes/combat_classification_catalog.gd"
text = cat_path.read_text(encoding="utf-8-sig")
scene_marker = "const SCENES:Dictionary = {"
script_marker = "const SCRIPTS:Dictionary = {"
changed = []
if S + "gojo.gd" not in text:
    a = text.index(scene_marker) + len(scene_marker)
    text = text[:a] + "\n" + "\n".join(fmt(k, v) for k, v in SCENES.items()) + text[a:]
    b = text.index(script_marker) + len(script_marker)
    text = text[:b] + "\n" + "\n".join(fmt(k, v) for k, v in SCRIPTS.items()) + text[b:]
    cat_path.write_text(text, encoding="utf-8", newline="\n")
    changed.append("catalog")
# 解析校验
json.loads(text.split("const SCENES:Dictionary = ", 1)[1].split("const SCRIPTS:Dictionary = ", 1)[0].strip())
json.loads(text.split("const SCRIPTS:Dictionary = ", 1)[1].strip())

# ---------------- 翻译
TR = [
    ("五条悟", "Satoru Gojo"), ("宿傩", "Ryomen Sukuna"), ("魔虚罗", "Mahoraga"), ("嵌合暗兽", "Agito"),
    ("咒术", "Jujutsu"), ("领域", "Domain"), ("超模", "Overpowered"), ("咒力消耗", "Cursed Energy Drain"),
    ("被封印", "Sealable"), ("式神", "Shikigami"), ("适应", "Adaptation"), ("茈", "Hollow Purple"),
    ("远程", "Ranged"), ("近战", "Melee"), ("召唤", "Summon"), ("治疗", "Healing"), ("脆弱", "Fragile"),
]
csv_path = root / "translations.csv"
csv_text = csv_path.read_text(encoding="utf-8-sig")
keys = {line.split(",", 1)[0] for line in csv_text.splitlines()}
add_csv = [f"{zh},{zh},{en}" for zh, en in TR if zh not in keys]
if add_csv:
    lines = csv_text.splitlines()
    idx = next((i for i, l in enumerate(lines) if l.startswith("菜月昴,")), len(lines) - 1)
    lines[idx + 1:idx + 1] = add_csv
    csv_path.write_text("keys,zh,en\n" + "\n".join(lines[1:]) + "\n" if lines[0].startswith("keys") else "\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    changed.append("translations.csv+%d" % len(add_csv))

tc_path = root / "global/translation_catalog.gd"
tc = tc_path.read_text(encoding="utf-8-sig")
zh_anchor = '\t\t"菜月昴": "菜月昴",\n'
en_anchor = '\t\t"菜月昴": "Natsuki Subaru",\n'
assert zh_anchor in tc and en_anchor in tc, "translation anchors missing"
zh_block, en_block = tc.split(en_anchor, 1)[0], None
missing_tr = [(zh, en) for zh, en in TR if ('\t\t"%s": "%s",\n' % (zh, zh)) not in tc]
if missing_tr:
    zh_add = "".join('\t\t"%s": "%s",\n' % (zh, zh) for zh, en in missing_tr)
    en_add = "".join('\t\t"%s": "%s",\n' % (zh, en) for zh, en in missing_tr)
    tc = tc.replace(zh_anchor, zh_anchor + zh_add, 1)
    tc = tc.replace(en_anchor, en_anchor + en_add, 1)
    tc_path.write_text(tc, encoding="utf-8", newline="\n")
    changed.append("translation_catalog+%d" % len(missing_tr))

# ---------------- 手动操控清单
inv_path = root / "tests/manual_control_inventory.csv"
inv = inv_path.read_text(encoding="utf-8-sig")
ROWS = [
    ("五条悟", "gojo", "controlled_attack_action,controlled_skill_action,controlled_middle_action,controlled_teleport,controlled_domain,controlled_instant_domain,controlled_barrier_flip", "左：苍（长按牵引点跟随鼠标）；右：赫（长按蓄力）；中：茈（长按2.4秒200%）；1瞬移 2无量空处 3 0.2秒无量空处 4结界翻转；专项见JJK_CHARACTERS.md"),
    ("宿傩", "sukuna", "controlled_attack_action,controlled_skill_action,controlled_middle_action,controlled_amplification,controlled_domain,controlled_mahoraga,controlled_agito,controlled_world_slash", "左：解（长按蜘蛛网/展延中拳脚）；右：捌；中：开；1领域展延 2伏魔御厨子（再按缩小）3魔虚罗 4嵌合暗兽 5世界斩；专项见JJK_CHARACTERS.md"),
    ("魔虚罗", "mahoraga", "controlled_attack_action,controlled_skill_action,controlled_middle_action", "左：退魔之剑；右：突进斩；中：咆哮；适应被动自动；专项见JJK_CHARACTERS.md"),
    ("嵌合暗兽", "agito", "controlled_attack_action,controlled_skill_action,controlled_middle_action", "左：撕咬；右：鵺落雷；中：圆鹿反转治疗；专项见JJK_CHARACTERS.md"),
]
add_inv = []
for name, key, actions, note in ROWS:
    scene = f"scenes/characters/动漫/{name}.tscn"
    if scene in inv: continue
    add_inv.append(f'选角人物,{scene},scripts/characters/动漫/咒术回战/{key}.gd,"{actions}",是,{note}')
if add_inv:
    if not inv.endswith("\n"): inv += "\n"
    inv += "\n".join(add_inv) + "\n"
    inv_path.write_text(inv, encoding="utf-8-sig", newline="\n")
    changed.append("inventory+%d" % len(add_inv))

# ---------------- 名单扩展测试
ext_path = root / "tests/test_manual_control_roster_extensions.gd"
ext = ext_path.read_text(encoding="utf-8-sig")
anchor = '\t\t"动漫/菜月昴":[&"controlled_attack_action",&"controlled_skill_action"],\n'
if '"动漫/五条悟"' not in ext and anchor in ext:
    add = ""
    for name, key, actions, note in ROWS:
        add += '\t\t"动漫/%s":[%s],\n' % (name, ",".join('&"%s"' % a for a in actions.split(",")))
    ext = ext.replace(anchor, anchor + add, 1)
    ext_path.write_text(ext, encoding="utf-8", newline="\n")
    changed.append("roster_extensions")
print("JJK_INTEGRATE", changed or "already")
