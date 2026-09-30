extends RefCounted
## Explicit resource registry. Entity identity is independent of damage events.
## Scene entries describe selectable forms; script entries cover dynamic .new() objects.
## ordinary_or_contextual is an audit summary, NEVER a legal damage-event kind.
## Unknown new resources stay unregistered; do not infer fire from names/directories.
const SCENES:Dictionary = {
 "res://scenes/characters/默认/丁某人睡觉.tscn": {
   "entity_kind": "character",
   "attack_modes": [
     "ranged"
   ],
   "carriers": [
     "projectile",
     "area"
   ],
   "damage_kinds": [
     "ordinary"
   ],
   "stage_field": "awake",
   "stages": {
     "false": {
       "carriers": [
         "projectile"
       ],
       "review": "sleeping: four Z; current owner attack power, ordinary impact + 0.1s public stun; no body damage"
     },
     "true": {
       "carriers": [
         "area"
       ],
       "review": "awake: one swept pixel annulus; each enemy current HP as raw-health ordinary damage; shared absorption/vehicle rules retained"
     }
   },
   "root_script": "res://scripts/characters/默认/丁某人睡觉.gd"
 },
 "res://scenes/shooter/默认/丁某人_Z.tscn": {
   "entity_kind": "projectile",
   "attack_modes": [
     "ranged"
   ],
   "carriers": [
     "projectile"
   ],
   "damage_kinds": [
     "ordinary"
   ],
   "review": "flying Z: public projectile ownership/reflection/block; owner current Damage; stun only on effective HP damage",
   "root_script": "res://scripts/characters/默认/ding_sleep/z.gd"
 },
 "res://scenes/characters/我的世界/皓宸.tscn": {"entity_kind":"character","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"passive_enemy_energy; top_contributor_fresh_subordinate; half_combat_stats_except_speed; shared_family; see docs/HAOCHEN.md","root_script":"res://scripts/characters/我的世界/皓宸.gd"},
 "res://scenes/characters/我的世界/流浪商人.tscn": {"entity_kind":"character","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"summoner_two_leashed_llamas; milk_cleanse_witch_invisibility_wall_phase; no_direct_damage; see docs/WANDERING_TRADER.md","root_script":"res://scripts/characters/我的世界/流浪商人.gd"},
 "res://scenes/creatures/流浪商人_羊驼.tscn": {"entity_kind":"subentity","attack_modes":["ranged"],"carriers":[],"damage_kinds":["ordinary_or_contextual"],"review":"killable_leashed_summon; spit_via_projectile; llama_body_speed_damage; see docs/WANDERING_TRADER.md","root_script":"res://scripts/characters/我的世界/wandering_trader/llama.gd"},
 "res://scenes/shooter/我的世界/羊驼口水.tscn": {"entity_kind":"projectile","attack_modes":["ranged"],"carriers":["projectile"],"damage_kinds":[],"review":"llama_spit_snowball_contract; see docs/WANDERING_TRADER.md","root_script":"res://scripts/characters/我的世界/wandering_trader/spit.gd"},
 "res://scenes/effects/我的世界/角色复制请求.tscn": {"entity_kind":"effect","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"confirmed_spawn_ticket; copy_cast_native_particles; no_damage","root_script":"res://scripts/effects/我的世界/character_copy_request.gd"},
  "res://scenes/characters/动漫/五条悟.tscn": {"entity_kind":"character","attack_modes":["ranged","melee"],"carriers":["projectile","ray_beam","area","body_contact"],"damage_kinds":["magic","ordinary"],"review":"infinity_blocks_non_sure_hit; blue_pull; red; purple_line; unlimited_void_closed_barrier; see docs/JJK_CHARACTERS.md","root_script":"res://scripts/characters/动漫/咒术回战/gojo.gd"},
  "res://scenes/characters/动漫/宿傩.tscn": {"entity_kind":"character","attack_modes":["melee","ranged"],"carriers":["ray_beam","area","projectile","body_contact"],"damage_kinds":["ordinary","fire"],"review":"dismantle_cleave_fuga; malevolent_shrine_whole_map; one_time_1hp_lock_world_slash; summons; see docs/JJK_CHARACTERS.md","root_script":"res://scripts/characters/动漫/咒术回战/sukuna.gd"},
  "res://scenes/characters/动漫/魔虚罗.tscn": {"entity_kind":"character","attack_modes":["melee"],"carriers":["weapon_sweep","area"],"damage_kinds":["ordinary"],"review":"adaptation_wheel_per_phenomenon; see docs/JJK_CHARACTERS.md","root_script":"res://scripts/characters/动漫/咒术回战/mahoraga.gd"},
  "res://scenes/characters/动漫/嵌合暗兽.tscn": {"entity_kind":"character","attack_modes":["melee","ranged"],"carriers":["body_contact","area"],"damage_kinds":["ordinary","magic"],"review":"rct_heal_aura; nue_thunder; round_deer_cleanse; see docs/JJK_CHARACTERS.md","root_script":"res://scripts/characters/动漫/咒术回战/agito.gd"},
 "res://scenes/characters/我的世界/凋灵骷髅.tscn": {"entity_kind":"character","attack_modes":["melee"],"carriers":["weapon_sweep","status_tick"],"damage_kinds":["ordinary","wither"],"review":"two_slashes; once_per_enemy_per_slash; shared_wither_current_plus_one_3s; see docs/WITHER_SKELETON.md","root_script":"res://scripts/characters/我的世界/wither_skeleton/wither_skeleton.gd"},
 "res://scenes/characters/我的世界/石矛.tscn": {"entity_kind":"character","attack_modes":["melee"],"carriers":["weapon_sweep"],"damage_kinds":["ordinary"],"review":"stone_spear_three_formations; attached_tips_not_projectiles","root_script":"res://scripts/characters/我的世界/石矛.gd"},
 "res://scenes/ball.tscn": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/ball.gd"
 },
 "res://scenes/character_spawner_tiles.tscn": {
  "entity_kind": "system",
  "root_script": "res://addons/character_spawner/character_spawner_tiles.gd"
 },
 "res://scenes/damage_text.tscn": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/damage_text.gd"
 },
 "res://scenes/debug_in_hit.tscn": {
  "entity_kind": "system",
  "root_script": ""
 },
 "res://scenes/health_bar.tscn": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/health_bar.gd"
 },
 "res://scenes/node_2d.tscn": {
  "entity_kind": "system",
  "root_script": ""
 },
 "res://scenes/particle.tscn": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/status_image.tscn": {
  "entity_kind": "system",
  "root_script": ""
 },
 "res://scenes/world.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/world.gd"
 },
 "res://scenes/characters/AI/时砂司祭.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/AI/时砂司祭.gd"
 },
 "res://scenes/characters/AI/磐灯守卫.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/AI/磐灯守卫.gd"
 },
 "res://scenes/characters/AI/霆针游侠.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/AI/霆针游侠.gd"
 },
 "res://scenes/characters/meme/不坏煎饼.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/不坏煎饼.gd"
 },
 "res://scenes/characters/meme/凑企鹅.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/凑企鹅.gd"
 },
 "res://scenes/characters/meme/大狗叫.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/大狗叫.gd"
 },
 "res://scenes/characters/meme/寸头没事沙漠溜达猪.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/寸头没事沙漠溜达猪.gd"
 },
 "res://scenes/characters/meme/愤怒的普通人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/愤怒的普通人.gd"
 },
 "res://scenes/characters/meme/时光.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/时光.gd"
 },
 "res://scenes/characters/meme/棍母.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/棍母.gd"
 },
 "res://scenes/characters/meme/肌肉男.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/肌肉男.gd"
 },
 "res://scenes/characters/meme/菊花茶.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/菊花茶.gd"
 },
 "res://scenes/characters/meme/野生狗奶.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/meme/野生狗奶.gd"
 },
 "res://scenes/characters/三角洲/堵桥.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/三角洲/堵桥.gd"
 },
 "res://scenes/characters/三角洲/夺舍狼.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/夺舍狼.gd"
 },
 "res://scenes/characters/三角洲/猛攻哥.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/三角洲/跑刀仔.gd"
 },
 "res://scenes/characters/三角洲/盾狗.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/三角洲/盾狗.gd"
 },
 "res://scenes/characters/三角洲/背刺鼠.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/三角洲/背刺鼠.gd"
 },
 "res://scenes/characters/三角洲/跑刀仔.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/三角洲/跑刀仔.gd"
 },
 "res://scenes/characters/乐队/户山香澄.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/乐队/户山香澄.gd"
 },
 "res://scenes/characters/乐队/若叶睦.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/乐队/若叶睦.gd"
 },
 "res://scenes/characters/乐队/薇欧拉.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/乐队/薇欧拉.gd"
 },
 "res://scenes/characters/人物/NC佬.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/NC佬.gd"
 },
 "res://scenes/characters/人物/伤心的男人.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/伤心的男人.gd"
 },
 "res://scenes/characters/人物/伪军头子.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/伪军头子.gd"
 },
 "res://scenes/characters/人物/保安.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/保安.gd"
 },
 "res://scenes/characters/人物/军官.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/军官.gd"
 },
 "res://scenes/characters/人物/军火商.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/军火商.gd"
 },
 "res://scenes/characters/人物/决斗者.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/决斗者.gd"
 },
 "res://scenes/characters/人物/剑客.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/剑客.gd"
 },
 "res://scenes/characters/人物/占卜师.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/占卜师.gd"
 },
 "res://scenes/characters/人物/原始人.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/原始人.gd"
 },
 "res://scenes/characters/人物/变形者.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/变形者.gd"
 },
 "res://scenes/characters/人物/国王.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/国王.gd"
 },
 "res://scenes/characters/人物/小丑.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/小丑.gd"
 },
 "res://scenes/characters/人物/小偷.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/小偷.gd"
 },
 "res://scenes/characters/人物/布鲁斯.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/布鲁斯.gd"
 },
 "res://scenes/characters/人物/建筑工人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/建筑工人.gd"
 },
 "res://scenes/characters/人物/影子.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/影子.gd"
 },
 "res://scenes/characters/人物/战斧重骑兵.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/战斧重骑兵.gd"
 },
 "res://scenes/characters/人物/投资者.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/投资者.gd"
 },
 "res://scenes/characters/人物/拳击手.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/拳击手.gd"
 },
 "res://scenes/characters/人物/掷骰子的人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/人物/掷骰子的人.gd"
 },
 "res://scenes/characters/人物/收债人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/收债人.gd"
 },
 "res://scenes/characters/人物/数学老师.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/数学老师.gd"
 },
 "res://scenes/characters/人物/时光客.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/时光客.gd"
 },
 "res://scenes/characters/人物/智者.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/智者.gd"
 },
 "res://scenes/characters/人物/服务员.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/服务员.gd"
 },
 "res://scenes/characters/人物/极速者.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/极速者.gd"
 },
 "res://scenes/characters/人物/棋手.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/棋手.gd"
 },
 "res://scenes/characters/人物/火车长.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/火车长.gd"
 },
 "res://scenes/characters/人物/炮兵.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/炮兵.gd"
 },
 "res://scenes/characters/人物/炸弹客.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/炸弹客.gd"
 },
 "res://scenes/characters/人物/猎人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/猎人.gd"
 },
 "res://scenes/characters/人物/疲倦的人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/人物/疲倦的人.gd"
 },
 "res://scenes/characters/人物/矿工.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/矿工.gd"
 },
 "res://scenes/characters/人物/磁铁.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/磁铁.gd"
 },
 "res://scenes/characters/人物/科学家.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/科学家.gd"
 },
 "res://scenes/characters/人物/红绿灯.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/红绿灯.gd"
 },
 "res://scenes/characters/人物/背刺者.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/背刺者.gd"
 },
 "res://scenes/characters/人物/裁判.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/裁判.gd"
 },
 "res://scenes/characters/人物/训犬师.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/训犬师.gd"
 },
 "res://scenes/characters/人物/赌徒.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/赌徒.gd"
 },
 "res://scenes/characters/人物/醉汉.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/醉汉.gd"
 },
 "res://scenes/characters/人物/重女.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/重女.gd"
 },
 "res://scenes/characters/人物/键盘侠.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/键盘侠.gd"
 },
 "res://scenes/characters/人物/锻刀师.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "fire",
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/锻刀师.gd"
 },
 "res://scenes/characters/人物/镜子.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/镜子.gd"
 },
 "res://scenes/characters/人物/面包车.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/面包车.gd"
 },
 "res://scenes/characters/人物/领导.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/领导.gd"
 },
 "res://scenes/characters/人物/黑帮老大.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/黑帮老大.gd"
 },
 "res://scenes/characters/人物/鼓手.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/鼓手.gd"
 },
 "res://scenes/characters/人物/形态/疲倦的人_悲伤形态.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/人物/悲伤的男人.gd"
 },
 "res://scenes/characters/人物/形态/疲倦的人_愤怒形态.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/人物/愤怒的男人.gd"
 },
 "res://scenes/characters/传说之下/Sans.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee",
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/传说之下/Sans.gd"
 },
 "res://scenes/characters/动漫/菜月昴.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/动漫/菜月昴.gd"
 },
 "res://scenes/characters/动物/九头蛇.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/动物/九头蛇.gd"
 },
 "res://scenes/characters/动物/兔子.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/兔子.gd"
 },
 "res://scenes/characters/动物/牛.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/动物/牛系.gd"
 },
 "res://scenes/characters/动物/牛犊子.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/动物/牛系.gd"
 },
 "res://scenes/characters/动物/猫.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/猫.gd"
 },
 "res://scenes/characters/小弟/NC坦克.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/NC步枪兵.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/伪军.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/伪军.gd"
 },
 "res://scenes/characters/小弟/功夫小弟.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/国王守卫.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/国王将军.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/愤怒的人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/愤怒的人.gd"
 },
 "res://scenes/characters/小弟/拳头小混混.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/持刀小混混.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/铁棍小混混.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/黑帮小弟.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/小弟/黑帮持枪小弟.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/characters/我的世界/仙人掌.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/cactus_note/cactus.gd"
 },
 "res://scenes/characters/我的世界/凋灵.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/wither/wither.gd"
 },
 "res://scenes/characters/我的世界/史莱姆.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/slime.gd"
 },
 "res://scenes/characters/我的世界/唤魔者.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/唤魔者.gd"
 },
 "res://scenes/characters/我的世界/唱片机.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/cactus_note/note_block.gd"
 },
 "res://scenes/characters/我的世界/天堂陨落长弓.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/heavenfall_longbow.gd"
 },
 "res://scenes/characters/我的世界/女巫.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/女巫.gd"
 },
 "res://scenes/characters/我的世界/守卫者.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/guardian.gd"
 },
 "res://scenes/characters/我的世界/弓.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/bow.gd"
 },
 "res://scenes/characters/我的世界/恶魂.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/ghast.gd"
 },
 "res://scenes/characters/我的世界/悦灵.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/allay/allay.gd"
 },
 "res://scenes/characters/我的世界/木剑.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/frontier/wooden_sword.gd"
 },
 "res://scenes/characters/我的世界/木矛.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/木矛.gd"
 },
 "res://scenes/characters/我的世界/木船.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/oak_boat.gd"
 },
 "res://scenes/characters/我的世界/末影人.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/末影人.gd"
 },
 "res://scenes/characters/我的世界/溺尸.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/溺尸.gd"
 },
 "res://scenes/characters/我的世界/潜影贝.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/潜影贝.gd"
 },
 "res://scenes/characters/我的世界/烈焰人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/烈焰人.gd"
 },
 "res://scenes/characters/我的世界/监守者.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/frontier/warden.gd"
 },
 "res://scenes/characters/我的世界/矿车.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/minecart/minecart.gd"
 },
 "res://scenes/characters/我的世界/硫方怪.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "fire",
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/硫方怪.gd"
 },
 "res://scenes/characters/我的世界/粘性活塞.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/piston.gd"
 },
 "res://scenes/characters/我的世界/羊.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/sheep.gd"
 },
 "res://scenes/characters/我的世界/苔藓.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/frontier/moss.gd"
 },
 "res://scenes/characters/我的世界/苦力怕.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/苦力怕.gd"
 },
 "res://scenes/characters/我的世界/蜘蛛.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/蜘蛛.gd"
 },
 "res://scenes/characters/我的世界/蝙蝠.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/bat/bat.gd"
 },
 "res://scenes/characters/我的世界/蠹虫.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/蠹虫.gd"
 },
 "res://scenes/characters/我的世界/重锤.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/重锤.gd"
 },
 "res://scenes/characters/我的世界/钓鱼竿.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/fishing_rod.gd"
 },
 "res://scenes/characters/我的世界/钻石剑.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/钻石剑.gd"
 },
 "res://scenes/characters/我的世界/钻石长矛.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/钻石长矛.gd"
 },
 "res://scenes/characters/我的世界/铁傀儡.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/铁傀儡.gd"
 },
 "res://scenes/characters/我的世界/铁匠村民.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/铁匠村民.gd"
 },
 "res://scenes/characters/我的世界/铁砧.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/铁砧.gd"
 },
 "res://scenes/characters/我的世界/铜剑.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/铜剑.gd"
 },
 "res://scenes/characters/我的世界/雪傀儡.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/snow_golem/snow_golem.gd"
 },
 "res://scenes/characters/我的世界/雾中人.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/fog_man/actor.gd"
 },
 "res://scenes/characters/我的世界/鞘翅重锤.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/鞘翅重锤.gd"
 },
 "res://scenes/characters/我的世界/鞘翅重锤长矛.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/鞘翅重锤长矛.gd"
 },
 "res://scenes/characters/我的世界/鞘翅长矛.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/鞘翅长矛.gd"
 },
 "res://scenes/characters/我的世界/骷髅.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/骷髅.gd"
 },
 "res://scenes/characters/月计/伞夫.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/月计/伞夫.gd"
 },
 "res://scenes/characters/月计/堇紫泪滴.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/月计/堇紫泪滴.gd"
 },
 "res://scenes/characters/月计/殷红迷雾.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/月计/殷红迷雾.gd"
 },
 "res://scenes/characters/杀戮尖塔/小刀猎.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/小刀猎.gd"
 },
 "res://scenes/characters/杀戮尖塔/异蛙寄生虫.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/异蛙寄生虫.gd"
 },
 "res://scenes/characters/杀戮尖塔/异蛙寄生虫_小.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/异蛙寄生虫_小.gd"
 },
 "res://scenes/characters/杀戮尖塔/战士.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/战士.gd"
 },
 "res://scenes/characters/杀戮尖塔/猎人杀手.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/猎人杀手.gd"
 },
 "res://scenes/characters/杀戮尖塔/虔诚雕刻师.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/虔诚雕刻师.gd"
 },
 "res://scenes/characters/杀戮尖塔/蛇咬相生猎.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/蛇咬相生猎.gd"
 },
 "res://scenes/characters/杀戮尖塔/蜂群术士.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/蜂群术士.gd"
 },
 "res://scenes/characters/杀戮尖塔/观者.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/观者.gd"
 },
 "res://scenes/characters/杀戮尖塔/锻剑储君.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/锻剑储君.gd"
 },
 "res://scenes/characters/杀戮尖塔/门扉缔造者.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/杀戮尖塔/门扉缔造者.gd"
 },
 "res://scenes/characters/游戏/战争女神.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee",
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/游戏/战争女神.gd"
 },
 "res://scenes/characters/游戏/魔角猎人.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/游戏/魔角猎人.gd"
 },
 "res://scenes/characters/物品/气球.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/气球.gd"
 },
 "res://scenes/characters/默认/不死盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/不死盔甲架.gd"
 },
 "res://scenes/characters/默认/弓箭盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/弓箭盔甲架.gd"
 },
 "res://scenes/characters/默认/盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/盔甲架.gd"
 },
 "res://scenes/characters/默认/石头.tscn": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/石头.gd"
 },
 "res://scenes/characters/默认/移动盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/移动盔甲架.gd"
 },
 "res://scenes/characters/默认/药水测试盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/效果测试盔甲架.gd"
 },
 "res://scenes/characters/默认/虚无盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/虚无盔甲架.gd"
 },
 "res://scenes/characters/默认/防御盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/防御盔甲架.gd"
 },
 "res://scenes/characters/默认/附魔测试盔甲架.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/默认/效果测试盔甲架.gd"
 },
 "res://scenes/creatures/九头蛇_头.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/动物/九头蛇_头.gd"
 },
 "res://scenes/creatures/伪军.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/伪军.gd"
 },
 "res://scenes/creatures/储君_sword.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/储君_sword.gd"
 },
 "res://scenes/creatures/军火商_枪.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/军火商_枪.gd"
 },
 "res://scenes/creatures/唤魔恼鬼.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/唤魔恼鬼.gd"
 },
 "res://scenes/creatures/小狗叫.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/小狗叫.gd"
 },
 "res://scenes/creatures/布鲁斯_狗.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/布鲁斯_狗.gd"
 },
 "res://scenes/creatures/建筑工人_墙.tscn": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/建筑工人_墙.gd"
 },
 "res://scenes/creatures/投稿随从.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/投稿随从.gd"
 },
 "res://scenes/creatures/末影分身.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/mc_short_lived_mob.gd"
 },
 "res://scenes/creatures/火车长_列车.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/火车长_列车.gd"
 },
 "res://scenes/creatures/猎人_捕兽夹.tscn": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/猎人_捕兽夹.gd"
 },
 "res://scenes/creatures/训犬师_狗.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/训犬师_狗.gd"
 },
 "res://scenes/creatures/铁傀儡村民.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/铁傀儡村民.gd"
 },
 "res://scenes/creatures/门扉缔造者_手.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/门扉缔造者_手.gd"
 },
 "res://scenes/creatures/领导房产业主.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/领导房产业主.gd"
 },
 "res://scenes/creatures/我的世界/凋零信标.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/wither/beacon.gd"
 },
 "res://scenes/creatures/我的世界/史莱姆_中.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/slime.gd"
 },
 "res://scenes/creatures/我的世界/史莱姆_小.tscn": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/slime.gd"
 },
 "res://scenes/creatures/我的世界/苦力怕头.tscn": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/creatures/我的世界/苦力怕头.gd"
 },
 "res://scenes/effects/stun_visual.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/stun_visual.gd"
 },
 "res://scenes/effects/兔子繁殖特效.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/兔子繁殖特效.gd"
 },
 "res://scenes/effects/战争女神_免疫爆裂.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/战争女神_免疫爆裂.gd"
 },
 "res://scenes/effects/战争女神_变身火焰.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/战争女神_变身火焰.gd"
 },
 "res://scenes/effects/战争女神_法阵.tscn": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/战争女神_法阵.gd"
 },
 "res://scenes/effects/户山香澄_星星坠落.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/户山香澄_星星坠落.gd"
 },
 "res://scenes/effects/野生狗奶老死残骸.tscn": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/野生狗奶老死残骸.gd"
 },
 "res://scenes/effects/锻刀师_蒸汽.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/锻刀师_蒸汽.gd"
 },
 "res://scenes/effects/锻刀师_震荡波.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/锻刀师_震荡波.gd"
 },
 "res://scenes/effects/领导掉落物.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/领导掉落物.gd"
 },
 "res://scenes/effects/魔角猎人_小爆弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/魔角猎人_小爆弹.gd"
 },
 "res://scenes/effects/魔角猎人_爆炸特效.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/魔角猎人_爆炸特效.gd"
 },
 "res://scenes/effects/我的世界/MC烟雾粒子.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/我的世界/MC烟雾粒子.gd"
 },
 "res://scenes/effects/我的世界/MC爆炸.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/我的世界/mc_explosion.gd"
 },
 "res://scenes/effects/我的世界/下界合金锭.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/我的世界/下界合金锭.gd"
 },
 "res://scenes/effects/我的世界/雪傀儡雪地.tscn": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/snow_golem/snow_field.gd"
 },
 "res://scenes/effects/我的世界/雷电.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/我的世界/雷电.gd"
 },
 "res://scenes/particle/Attack_white_points.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/particle/gpu_particles_2d.tscn": {
  "entity_kind": "visual",
  "root_script": ""
 },
 "res://scenes/particle/异蛙寄生虫/汁液.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/particle/异蛙寄生虫/蛆.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/particle/蜂群术士/Bee_Follow.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/particle/蜂群术士/Bee_In_Char.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/particle/蜂群术士/Bee_Stand.tscn": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://classes/particles.gd"
 },
 "res://scenes/shooter/bee.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/bee.gd"
 },
 "res://scenes/shooter/knife.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/knife.gd"
 },
 "res://scenes/shooter/knife_flat_probe.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/knife.gd"
 },
 "res://scenes/shooter/不坏煎饼弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/不坏煎饼弹.gd"
 },
 "res://scenes/shooter/伪军子弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/伪军子弹.gd"
 },
 "res://scenes/shooter/军火商_子弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/军火商_子弹.gd"
 },
 "res://scenes/shooter/凑企鹅石头.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/凑企鹅石头.gd",
  "stage_field": "flying",
  "stages": {
   "true": {
    "entity_kind": "projectile",
    "attack_modes": [
     "ranged"
    ],
    "carriers": [
     "projectile"
    ]
   },
   "false": {
    "entity_kind": "obstacle",
    "attack_modes": [
     "none"
    ],
    "carriers": [
     "none"
    ]
   }
  }
 },
 "res://scenes/shooter/堵桥PSG子弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/堵桥PSG子弹.gd"
 },
 "res://scenes/shooter/子弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/子弹.gd"
 },
 "res://scenes/shooter/建筑工人_砖块.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/建筑工人_砖块.gd"
 },
 "res://scenes/shooter/弹球.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/弹球.gd"
 },
 "res://scenes/shooter/战争女神_火焰剑气.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/战争女神_火焰剑气.gd"
 },
 "res://scenes/shooter/数学老师公式弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/数学老师公式弹.gd"
 },
 "res://scenes/shooter/无重力弹球.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/无重力弹球.gd"
 },
 "res://scenes/shooter/时光客时钟.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/时光客时钟.gd"
 },
 "res://scenes/shooter/潜影弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/潜影弹.gd"
 },
 "res://scenes/shooter/炸弹客炸弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/炸弹客炸弹.gd"
 },
 "res://scenes/shooter/猎人_霰弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/猎人_霰弹.gd"
 },
 "res://scenes/shooter/磁铁_电球.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/磁铁_电球.gd"
 },
 "res://scenes/shooter/科学家弹丸.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/科学家弹丸.gd"
 },
 "res://scenes/shooter/菊花茶水滴.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/菊花茶水滴.gd"
 },
 "res://scenes/shooter/蛇咬.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/蛇咬.gd"
 },
 "res://scenes/shooter/蜘蛛地网.tscn": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/蜘蛛地网.gd"
 },
 "res://scenes/shooter/裁判红牌.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/裁判牌.gd"
 },
 "res://scenes/shooter/裁判蓝牌.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/裁判牌.gd"
 },
 "res://scenes/shooter/裁判黄牌.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/裁判牌.gd"
 },
 "res://scenes/shooter/酒瓶.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/酒瓶.gd"
 },
 "res://scenes/shooter/键盘文字.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/键盘文字.gd"
 },
 "res://scenes/shooter/领导处分文件.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/领导处分文件.gd"
 },
 "res://scenes/shooter/领导小领导.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/领导小领导.gd"
 },
 "res://scenes/shooter/魔角猎人_黑弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/魔角猎人_黑弹.gd"
 },
 "res://scenes/shooter/clown/clown_area_object.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/clown/clown_area_object.gd",
  "stage_field": "object_mode",
  "stages": {
   "0": {
    "entity_kind": "terrain",
    "attack_modes": [
     "environment"
    ],
    "carriers": [
     "body_contact"
    ],
    "damage_kinds": []
   },
   "1": {
    "entity_kind": "projectile",
    "attack_modes": [
     "ranged"
    ],
    "carriers": [
     "projectile"
    ]
   }
  }
 },
 "res://scenes/shooter/clown/clown_projectile.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/shooter/clown/clown_projectile.gd"
 },
 "res://scenes/shooter/我的世界/仙人掌刺.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/cactus_note/thorn.gd"
 },
 "res://scenes/shooter/我的世界/天陨箭.tscn": {
  "stage_field": "_landed",
  "stages": {"true": {"entity_kind": "visual", "carriers": ["none"]}, "false": {"entity_kind": "projectile"}},
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/heavenfall_arrow.gd"
 },
 "res://scenes/shooter/我的世界/天陨箭矢.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/heavenfall_bolt.gd"
 },
 "res://scenes/shooter/我的世界/天陨裂隙.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new6/heavenfall_rift.gd"
 },
 "res://scenes/shooter/我的世界/恶魂火焰弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/new5/fireball.gd"
 },
 "res://scenes/shooter/我的世界/悦灵音符.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/allay/note.gd"
 },
 "res://scenes/shooter/我的世界/烈焰弹.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/我的世界/烈焰弹.gd"
 },
 "res://scenes/shooter/我的世界/雪球.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/characters/我的世界/snow_golem/snowball.gd"
 },
 "res://scenes/shooter/我的世界/骷髅箭.tscn": {
  "stage_field": "_mode",
  "stages": {"0": {"entity_kind": "projectile"}, "1": {"entity_kind": "terrain"}, "2": {"entity_kind": "status", "status_polarity": "negative", "status_cleanup": "detach"}},
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/effects/我的世界/骷髅箭.gd"
 },
 "res://scenes/terrain/原始人火堆.tscn": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/terrain/原始人火堆.gd"
 },
 "res://scenes/terrain/火车长_煤矿.tscn": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/terrain/火车长_煤矿.gd"
 },
 "res://scenes/terrain/矿工小石头.tscn": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/terrain/矿工小石头.gd"
 },
 "res://scenes/terrain/若叶睦_黄瓜花盆.tscn": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/terrain/若叶睦_黄瓜花盆.gd"
 },
 "res://scenes/terrain/我的世界/锻造台.tscn": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/terrain/我的世界/锻造台.gd"
 },
 "res://scenes/training/character_fresh_probe.tscn": {
  "entity_kind": "system",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/character_fresh_probe.gd"
 },
 "res://scenes/training/character_stage_probe.tscn": {
  "entity_kind": "system",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/character_stage_probe.gd"
 },
 "res://scenes/training/knife_batch_probe.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/knife_batch_probe.gd"
 },
 "res://scenes/training/knife_native_probe.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/knife_native_probe.gd"
 },
 "res://scenes/training/knife_native_rid_probe.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/knife_native_rid_probe.gd"
 },
 "res://scenes/training/knife_stage_probe.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/knife_stage_probe.gd"
 },
 "res://scenes/training/release_benchmark_boot.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/release_benchmark_node.gd"
 },
 "res://scenes/training/SpeedsterDodgeTrainingArena.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/speedster_dodge_training_arena.gd"
 },
 "res://scenes/training/SpeedsterRLWorld.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/world.gd"
 },
 "res://scenes/training/SpeedsterTrainingProjectile.tscn": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://scripts/training/speedster_training_projectile.gd"
 },
 "res://global/audios.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://global/audios.gd"
 },
 "res://global/game.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://global/game.gd"
 },
 "res://ui/control.tscn": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "root_script": "res://ui/control.gd"
 },
 "res://ui/game_setting.tscn": {
  "entity_kind": "system",
  "root_script": ""
 },
 "res://ui/team_set_button.tscn": {
  "entity_kind": "system",
  "root_script": ""
 }
}

const SCRIPTS:Dictionary = {
	"res://global/feedback_settings.gd": {"entity_kind":"system","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"local_feedback_validation_and_curves; no_combat_state"},
 "res://scripts/characters/默认/丁某人睡觉.gd": {
   "entity_kind": "character",
   "attack_modes": [
     "ranged"
   ],
   "carriers": [
     "projectile",
     "area"
   ],
   "damage_kinds": [
     "ordinary"
   ],
   "stage_field": "awake",
   "stages": {
     "false": {
       "carriers": [
         "projectile"
       ],
       "review": "sleeping: four Z; current owner attack power, ordinary impact + 0.1s public stun; no body damage"
     },
     "true": {
       "carriers": [
         "area"
       ],
       "review": "awake: one swept pixel annulus; each enemy current HP as raw-health ordinary damage; shared absorption/vehicle rules retained"
     }
   }
 },
 "res://scripts/characters/默认/ding_sleep/z.gd": {
   "entity_kind": "projectile",
   "attack_modes": [
     "ranged"
   ],
   "carriers": [
     "projectile"
   ],
   "damage_kinds": [
     "ordinary"
   ],
   "review": "flying Z: public projectile ownership/reflection/block; owner current Damage; stun only on effective HP damage"
 },
 "res://scripts/characters/默认/ding_sleep/wave.gd": {
   "entity_kind": "effect",
   "attack_modes": [
     "ranged"
   ],
   "carriers": [
     "area"
   ],
   "damage_kinds": [
     "ordinary"
   ],
   "review": "active expanding annulus: authority only; once per target; target current HP raw-health ordinary component, not caster HP; visual is same clock/radius"
 },
 "res://scripts/characters/默认/ding_sleep/audio.gd": {
   "entity_kind": "component",
   "attack_modes": [],
   "carriers": [],
   "damage_kinds": [],
   "review": "Native event adapter only; shared mc_native_audio queue"
 },
 "res://scripts/characters/我的世界/皓宸.gd": {"entity_kind":"character","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"passive_enemy_energy; top_contributor_fresh_subordinate; half_combat_stats_except_speed; shared_family; see docs/HAOCHEN.md"},
 "res://scripts/effects/我的世界/character_copy_request.gd": {"entity_kind":"effect","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"confirmed_spawn_ticket; copy_cast_native_particles; no_damage"},
 "res://scripts/characters/我的世界/haochen/audio.gd": {"entity_kind":"component","attack_modes":["none"],"carriers":["none"],"damage_kinds":[],"review":"user_charge_voice_and_original_minecraft_audio_adapter; shared_queue"},
  "res://scripts/characters/动漫/咒术回战/gojo.gd": {"entity_kind":"character","attack_modes":["ranged","melee"],"carriers":["projectile","ray_beam","area","body_contact"],"damage_kinds":["magic","ordinary"],"review":"infinity_blocks_non_sure_hit; blue_pull; red; purple_line; unlimited_void_closed_barrier; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/sukuna.gd": {"entity_kind":"character","attack_modes":["melee","ranged"],"carriers":["ray_beam","area","projectile","body_contact"],"damage_kinds":["ordinary","fire"],"review":"dismantle_cleave_fuga; malevolent_shrine_whole_map; one_time_1hp_lock_world_slash; summons; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/mahoraga.gd": {"entity_kind":"character","attack_modes":["melee"],"carriers":["weapon_sweep","area"],"damage_kinds":["ordinary"],"review":"adaptation_wheel_per_phenomenon; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/agito.gd": {"entity_kind":"character","attack_modes":["melee","ranged"],"carriers":["body_contact","area"],"damage_kinds":["ordinary","magic"],"review":"rct_heal_aura; nue_thunder; round_deer_cleanse; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/jjk_base.gd": {"entity_kind":"component","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"shared_cursed_energy_rct_black_flash_rpc_layer; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/jjk_common.gd": {"entity_kind":"component","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"static_context_damage_helpers_and_audio_bank; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/jjk_fx.gd": {"entity_kind":"visual","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"pure_visual_one_shot_fx; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/jjk_projectile.gd": {"entity_kind":"projectile","attack_modes":["ranged"],"carriers":["projectile"],"damage_kinds":["ordinary_or_contextual"],"review":"authority_swept_red_and_fuga; see docs/JJK_CHARACTERS.md"},
  "res://scripts/characters/动漫/咒术回战/jjk_domain.gd": {"entity_kind":"effect","attack_modes":["area"],"carriers":["area"],"damage_kinds":["ordinary","magic"],"review":"domain_expansion_sure_hit; closed_barrier_is_terrain_layer; see docs/JJK_CHARACTERS.md"},
 "res://classes/sprite_snapshot_trail.gd": {"entity_kind":"visual","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"bounded_plain_sprite_snapshots; shared_copier_and_shader; no_physics_or_damage"},
 "res://scripts/characters/我的世界/wither_skeleton/wither_skeleton.gd": {"entity_kind":"character","attack_modes":["melee"],"carriers":["weapon_sweep","status_tick"],"damage_kinds":["ordinary","wither"],"review":"two_slashes; once_per_enemy_per_slash; shared_wither_current_plus_one_3s; see docs/WITHER_SKELETON.md"},
 "res://scripts/effects/我的世界/mc_creature_voice.gd": {"entity_kind":"component","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"shared_native_queue_audio_only"},
 "res://Images/characters/我的世界/wither_skeleton/poses.gd": {"entity_kind":"visual","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"original_model_projected_hand_anchors"},
 "res://scripts/characters/我的世界/wither_skeleton/sounds.gd": {"entity_kind":"component","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"original_mojang_audio_bank"},
 "res://scripts/characters/我的世界/石矛.gd": {"entity_kind":"character","attack_modes":["melee"],"carriers":["weapon_sweep"],"damage_kinds":["ordinary"],"review":"stone_spear_three_formations; attached_tips_not_projectiles"},
 "res://classes/weapon_tip_sweep.gd": {"entity_kind":"component","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"shared_exact_tip_geometry; no_damage_policy"},
 "res://classes/status_cleansing.gd": {"entity_kind":"system","attack_modes":[],"carriers":[],"damage_kinds":[],"review":"shared_negative_cleanse; explicit_status_protocol"},
 "res://classes/after_image_render_batch.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/ai_original_base.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/ball.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/body_collision_exclusions.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/buff.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/character_spawn_entry.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/fresh_scene_supply.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/health_bar.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/hitbox.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/hurtbox.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/map_tile_geometry.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/particles.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/portal_link.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/portal_map.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/prewarmed_audio_stream.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/property_index.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/runtime_knife_scene.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/state_machine.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/character_auto_fit.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/damage_text.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/day_night_cycle.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/development_mode.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/projectile_contact.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/random_character_draft.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/world.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/audio/local_positional_sfx.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/audio/投稿吹哨音效.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/audio/训犬师音效.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/bilibili.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/NC佬.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/speedster_motion_plan.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/speedster_ricochet_planner.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/speedster_threat.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/伤心的男人.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/伪军头子.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/保安.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/保安_增援请求.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/兔子.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/军火商.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/决斗者.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/剑客.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/占卜师.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/原始人.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/变形者.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/变形者_图片预演.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/变形者_形态控制器.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/国王.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/夺舍狼.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/小丑.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/小偷.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/属性提示.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/布鲁斯.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/建筑工人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/影子.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/愤怒的人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/战斧重骑兵.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/投稿角色工具.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/投资者.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/投资者_地图控制器.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/投资者_柱.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/拳击手.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/收债人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/数学老师.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/时光客.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/智者.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/智者_布局点.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/服务员.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/极速者.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/棋子.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/棋手.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/棋盘控制器.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/气球.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/火车长.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/炮兵.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/炸弹客.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/猎人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/猫.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/矿工.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/磁铁.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/科学家.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/科学家_传送门.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/红绿灯.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/背刺者.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/裁判.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/训犬师.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/赌徒.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/醉汉.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/重女.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/键盘侠.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/锻刀师.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "fire",
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/镜子.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/面包车.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/领导.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/黑帮老大.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/鼓手.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/AI/时砂司祭.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/AI/磐灯守卫.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/AI/霆针游侠.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/不坏煎饼.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/凑企鹅.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/大狗叫.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/寸头没事沙漠溜达猪.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/愤怒的普通人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/时光.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/时光围棋子.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/棍母.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/狗叫机制.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/肌肉男.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/菊花茶.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/meme/野生狗奶.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/RL/speedster_dodge_rl_controller.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/三角洲/堵桥.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/三角洲/盾狗.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/三角洲/背刺鼠.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/三角洲/跑刀仔.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/乐队/户山香澄.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/乐队/若叶睦.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/乐队/薇欧拉.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/人物/悲伤的男人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/人物/愤怒的男人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/人物/掷骰子的人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/人物/疲倦的人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/传说之下/Sans.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee",
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动漫/死亡回归快照值.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动漫/死亡回归时间轴.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动漫/菜月昴.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动漫/菜月昴惯性鞭.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动物/九头蛇.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动物/九头蛇_头.gd": {
  "entity_kind": "subentity",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/动物/牛系.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/anvil_escape_lease.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/mc_item_base.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/mc_mob_base.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/sulfur_cube_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/sulfur_cube_model.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/weapon_visual_size.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/唤魔者.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/女巫.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/木矛.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/末影人.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/溺尸.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/潜影贝.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/烈焰人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/硫方怪.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "fire",
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/苦力怕.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/蜘蛛.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/蠹虫.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/重锤.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/钻石剑.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/钻石长矛.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/铁傀儡.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/铁匠村民.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/铁砧.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/铜剑.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/鞘翅重锤.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/鞘翅重锤长矛.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/鞘翅长矛.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/骷髅.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/allay.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/capture.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/extended_capture.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/native_return.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/native_sounds.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/note.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/note_trail.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/orbit.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/recall_burst.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/recall_wave.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/return_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/allay/smooth_orbit.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/bat/bat.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/bat/bat_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/bat/bat_gather_navigation.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/bat/bat_transform_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/block_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/cactus.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/disc_flight.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/extra_library.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/features_creator.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/features_precipice.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/features_relic.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/music_channel_peaks.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/music_features.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/music_peaks.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/music_shape_features.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/note_block.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/note_wave.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/shape_cat.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/shape_creator.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/shape_otherside.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/shape_pigstep.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/shape_precipice.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/shape_relic.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/cactus_note/thorn.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/copper_sword/charge_visual.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/copper_sword/swing_trail.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/diamond_spear/echo.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/diamond_spear/feedback.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/actor.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/charge_mist.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/effects.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/eyes.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/eye_points.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/field.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/fog_man/mask.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/base.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/battle_noise.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/creeper_style_bar.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/moss.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/moss_azalea.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/moss_debris.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/moss_footsteps.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/sword_workbench.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/warden.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/warden_ground_debris.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/warden_screen.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/warden_voice.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/warden_wave.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/frontier/wooden_sword.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/airborne.gd": {
  "status_polarity": "dynamic",
  "status_cleanup": "cleanse_status_effect",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/iron_ingot_projectile.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/landing_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/landing_impact.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/native_audio_player.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/native_sounds.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/iron_golem/pair_base.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/minecart/minecart.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/minecart/minecart_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/minecart/native_particles.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/minecart/powered_rails.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/base.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/blast.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/fireball.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/fishing_rod.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/ghast.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/guardian.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/guardian_spike_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/piston.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/piston_push.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/piston_slime_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/slime.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/slime_jump_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/sticky_hold.gd": {
  "status_polarity": "negative",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new5/utils.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/boat_rider.gd": {
  "status_polarity": "neutral",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/bow.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/fx_burst.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/grass_bite_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_arrow.gd": {
  "stage_field": "_landed",
  "stages": {"true": {"entity_kind": "visual", "carriers": ["none"]}, "false": {"entity_kind": "projectile"}},
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_arrow_debris.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_bolt.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_collision.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_debris.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_longbow.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_pierce_rift.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_rain_rift.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_rift.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_ring.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_sky_band.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_transit.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_union.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/heavenfall_wave_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/oak_boat.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/sheep.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/wool_break_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/new6/wool_projectile.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/cold.gd": {
  "status_polarity": "negative",
  "status_cleanup": "clear_for_immunity",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "cold"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/ice_shell.gd": {
  "status_polarity": "neutral",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/native_sounds.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/phase_sounds.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/rules.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/snowball.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/snow_field.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/snow_golem/snow_golem.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon_beam.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon_emitter.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon_glow.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon_profile.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon_ring.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/beacon_summon_fx.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/bedrock_rig.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/charge_reset.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/rose.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/skull.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/status.gd": {
  "status_polarity": "negative",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/我的世界/wither/wither.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/伞夫.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/伞夫视觉.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/堇紫泪滴.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/堇紫泪滴视觉.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/月计理智角色.gd": {
  "entity_kind": "combat_entity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/殷红迷雾.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/月计/殷红迷雾视觉.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/小刀猎.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/异蛙寄生虫.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/异蛙寄生虫_小.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/战士.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/猎人杀手.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/虔诚雕刻师.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/蛇咬相生猎.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/蜂群术士.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/观者.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/锻剑储君.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/杀戮尖塔/门扉缔造者.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/游戏/战争女神.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "melee",
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/游戏/魔角猎人.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/不死盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/军官.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/弓箭盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/效果测试盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/石头.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/移动盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/虚无盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/characters/默认/防御盔甲架.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/mc_short_lived_mob.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/伪军.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/储君_sword.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/军火商_枪.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/唤魔恼鬼.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/小狗叫.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/布鲁斯_狗.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/布鲁斯_食物.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/建筑工人_墙.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/投稿随从.gd": {
  "entity_kind": "character",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/火车长_列车.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/猎人_捕兽夹.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/训犬师_狗.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/铁傀儡村民.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/门扉缔造者_手.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/领导房产业主.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/creatures/我的世界/苦力怕头.gd": {
  "entity_kind": "subentity",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/blood_liquid_drop.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/blood_surface_decal.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/character_hurt_shake.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/combat_impact_layer.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/hit_burst_effect.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/knockback_effect.gd": {
  "status_polarity": "dynamic",
  "status_cleanup": "cleanse_status_effect",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/physical_airborne_effect.gd": {
  "status_polarity": "dynamic",
  "status_cleanup": "cleanse_status_effect",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/stun_pixel_layer.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/stun_visual.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/summit_arena_3d.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/summit_mountain_range.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/summit_rock_landscape.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/surface_acceleration.gd": {
  "status_polarity": "neutral",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/umbrella_hit_burst.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/umbrella_hit_burst_follow.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/wall_hit_burst.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/wasted_overlay.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/三角洲_铁丝网.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/乌鲁鲁巡飞弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/乌鲁鲁巡飞弹小炸弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/乌鲁鲁火焰区域.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/乌鲁鲁火焰弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/保安_巡逻车碰撞.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/兔子繁殖特效.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/占卜师卡牌.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/地表渲染采样.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/堵桥丢火.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/堵桥巡飞弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/堵桥巡飞弹小炸弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/堵桥火圈.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/影子_吼叫波.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/战争女神_免疫爆裂.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/战争女神_变身火焰.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/战争女神_法阵.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/户山香澄_星星坠落.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/投稿雨滴.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/服务员门.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/殷红迷雾_刀光.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/炮兵炮击区域.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/狗叫声波.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/若叶睦_击杀血液.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/菊花茶重力视觉.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/薇欧拉_文字弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/薇欧拉_火场.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/薇欧拉_火焰弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/重女式逐字颤抖.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/重女文字.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/重女黑洞视觉.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/野生狗奶老死残骸.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/野生狗奶衰老骷髅.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/锻刀师_蒸汽.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/锻刀师_震荡波.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/领导掉落物.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/魔角猎人_小爆弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/魔角猎人_标记.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/魔角猎人_爆炸特效.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/黑帮老大_扔钱.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/AI/原创战斗反馈.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/sans_wall_slots.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/Sans业力.gd": {
  "status_polarity": "negative",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/Sans滚动骨头.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/Sans终幕.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/Sans终幕骨列.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/Sans骨头攻击.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/传说之下/Sans龙骨炮.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/动漫/菜月昴死档效果.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/动漫/菜月昴背景爱字.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/block_fragments.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/cobweb_debris.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/cobweb_footsteps.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/elytra_firework_trail.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/ghast_obstacle_damage.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/hit_audio_gain.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/item_fragments.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/lightning_glow.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc16_geometry.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc16_native_feedback.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc16_sound_bank.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_charge_circle.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_combat_abilities.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_electric_palette.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_enchantments.gd": {
  "status_polarity": "neutral",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_enchantment_catalog.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_enchantment_effects.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_explosion.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_native_animation.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_native_audio.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_native_batch2.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_native_prewarm.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_obstacle_properties.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_shared_burn.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_status_effects.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_totem_effect.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_visual_effects.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/mc_weaving_web.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/MC烟雾粒子.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/minecraft_clouds.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/pixel_arc.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/spider_silk.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/sulfur_amethyst_crystal.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/sulfur_amethyst_shard.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/sulfur_cube_blast.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/sulfur_ice_trail.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_arc.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_charge_visual.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_enchantment.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_ground_debris.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_hand_visual.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_lightning.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_network.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/trident_return_trail.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/三叉戟.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/下界合金竞技场.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/下界合金锭.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/唤魔尖牙.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/地图内沿阴影.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/地图外沿阴影.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/地图立体墙.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/地图背景主题.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/地图草方块背景.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/女巫药水.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/女巫药水伤害音效.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/女巫药水区域.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/女巫药水效果.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/女巫药水状态.gd": {
  "status_polarity": "dynamic",
  "status_cleanup": "_cleanup",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/女巫药水粒子.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/末影粒子.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/水泼弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/潜影浮空.gd": {
  "status_polarity": "negative",
  "status_cleanup": "finish",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/烈焰弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/烈焰火场.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/石砖缺口阴影.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/蛛网弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/蠹虫石砖场.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/蠹虫石砖渲染块.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/重锤落地冲击.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/钻石剑横扫.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/雷电.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/骷髅箭.gd": {
  "stage_field": "_mode",
  "stages": {"0": {"entity_kind": "projectile"}, "1": {"entity_kind": "terrain"}, "2": {"entity_kind": "status", "status_polarity": "negative", "status_cleanup": "detach"}},
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/我的世界/骷髅箭伤控制.gd": {
  "status_polarity": "negative",
  "status_cleanup": "cleanse_status_effect",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/投稿/悲伤眼泪.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/投稿/掷骰子视觉.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/effects/投稿/疲倦Z.gd": {
  "entity_kind": "effect",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/bee.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/knife.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/不坏煎饼弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/伪军子弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/军火商_子弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/凑企鹅石头.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy",
  "stage_field": "flying",
  "stages": {
   "true": {
    "entity_kind": "projectile",
    "attack_modes": [
     "ranged"
    ],
    "carriers": [
     "projectile"
    ]
   },
   "false": {
    "entity_kind": "obstacle",
    "attack_modes": [
     "none"
    ],
    "carriers": [
     "none"
    ]
   }
  }
 },
 "res://scripts/shooter/堵桥PSG子弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/子弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/建筑工人_砖块.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/弹球.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/战争女神_火焰剑气.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/收债人_钱.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/数学老师公式弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/无重力弹球.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/时光客时钟.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/潜影弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/炸弹客炸弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/猎人_霰弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/磁铁_电球.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/科学家弹丸.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/菊花茶水滴.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/蛇咬.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/蜘蛛地网.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/裁判牌.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/酒瓶.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/键盘文字.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/领导处分文件.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/领导小领导.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/魔角猎人_黑弹.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/clown/clown_area_object.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy",
  "stage_field": "object_mode",
  "stages": {
   "0": {
    "entity_kind": "terrain",
    "attack_modes": [
     "environment"
    ],
    "carriers": [
     "body_contact"
    ],
    "damage_kinds": []
   },
   "1": {
    "entity_kind": "projectile",
    "attack_modes": [
     "ranged"
    ],
    "carriers": [
     "projectile"
    ]
   }
  }
 },
 "res://scripts/shooter/clown/clown_motion_effect.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/shooter/clown/clown_projectile.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/status/mc_shared_burn_status.gd": {
  "status_polarity": "negative",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/status/剑客_流血.gd": {
  "status_polarity": "negative",
  "status_cleanup": "_finish",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/status/战争女神_灼烧.gd": {
  "status_polarity": "negative",
  "status_cleanup": "detach",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/status/锻刀师_燃烧.gd": {
  "status_polarity": "negative",
  "status_cleanup": "_finish",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/status/面包车_匕首流血.gd": {
  "status_polarity": "negative",
  "status_cleanup": "_finish",
  "entity_kind": "status",
  "attack_modes": [],
  "carriers": [
   "status_tick"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/原始人火堆.gd": {
  "entity_kind": "hazard",
  "attack_modes": [
   "environment"
  ],
  "carriers": [
   "area"
  ],
  "damage_kinds": [
   "fire"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/原始人火堆视觉.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/火车长_煤矿.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/生成地形安全管理器.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/矿工小石头.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/若叶睦_黄瓜花盆.gd": {
  "entity_kind": "terrain",
  "attack_modes": [
   "environment"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/terrain/我的世界/锻造台.gd": {
  "entity_kind": "obstacle",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/character_fresh_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/character_stage_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/combat_threat_analyzer.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/hit_burst_gpu_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/knife_batch_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/knife_native_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/knife_native_rid_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/knife_stage_probe.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/live_sans_feedback.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/live_sans_final.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/manual_training_controller.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [
   "ordinary_or_contextual"
  ],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/mc_backgrounds_preview.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/original_visual_reference.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/release_benchmark_node.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/special_character_threat_overlay.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/speedster_dodge_training_arena.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/speedster_rl_world_controller.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/speedster_training_projectile.gd": {
  "entity_kind": "projectile",
  "attack_modes": [
   "ranged"
  ],
  "carriers": [
   "projectile"
  ],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/training_respawn_manager.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/training/training_stats_hud.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_recorder.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_audio.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_controls.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_effect_tooltips.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_locale.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_naming.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_offline.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_preferences.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/dark_oak_doors_3d.gd": {
  "entity_kind": "visual", "attack_modes": [], "carriers": [], "damage_kinds": [],
  "review": "UI-only 3D hinged door meshes; no gameplay bodies or damage"
 },
 "res://scripts/ui/duel_top_hud.gd": {
  "entity_kind": "system", "attack_modes": [], "carriers": [], "damage_kinds": [],
  "review": "single shared top duel HUD and read-only recording mirror; timed damage and countdown display, round-result achievement; no combat damage or authority decisions"
 },
 "res://scripts/ui/dark_oak_transition.gd": {
  "entity_kind": "system", "attack_modes": [], "carriers": [], "damage_kinds": [],
  "review": "local UI transition only; root-owned; real-time; no combat or RPC"
 },
 "res://scripts/ui/dark_oak_transition_button.gd": {
  "entity_kind": "system", "attack_modes": [], "carriers": [], "damage_kinds": [],
  "review": "settings preview only; no gameplay mutation"
 },
 "res://scripts/ui/battle_record_settings.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/battle_record_writer.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/boss_intro_overlay.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/character_side_status_ui.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/effect_preview_panel.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/mc_active_effect_tooltip.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/mc_effect_tooltip.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/mc_preview_enchantment.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/mc_preview_potion_effect.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/multiplayer_control_ring.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/placement_box_overlay.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/random_character_draft_audio.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/random_character_draft_fx.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/random_character_draw_overlay.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/random_character_placeholder.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/random_character_roulette.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/rotation_frame_hud.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/rotation_frame_row.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/rotation_portraits.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/伪军头子钞票UI.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://scripts/ui/月计理智条.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/audios.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_character_placement.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_kill_blood.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_localization.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_room_discovery.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_time_scale.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_training_mode.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_wild_dog_old_age.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/game_wild_dog_time_visual.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://global/translation_catalog.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://ui/control.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "entity_registered; attack_summary_not_event_policy"
 },
 "res://classes/combat_classification.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "resource_data_or_classification_service"
 },
 "res://classes/combat_classification_catalog.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "resource_data_or_classification_service"
 },
 "res://Images/characters/我的世界/native_frames/drowned_hands.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "resource_data_or_classification_service"
 },
 "res://Images/characters/我的世界/native_frames/drowned_trident_masks.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "resource_data_or_classification_service"
 },
 "res://Images/characters/我的世界/native_frames/catch_recoil/catch_layers.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "resource_data_or_classification_service"
 },
 "res://Images/characters/我的世界/native_frames/hand_pounce/drowned_hand_layers.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "resource_data_or_classification_service"
 },
 "res://scripts/training/battle_conditions.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "concurrent_world_environment_controller_or_catalog"
 },
 "res://scripts/training/battle_conditions_catalog.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "concurrent_world_environment_controller_or_catalog"
 },
 "res://scripts/training/snow_wall_view.gd": {
  "entity_kind": "visual",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "reviewed_concurrent_visual_or_ui; no_damage_inference"
 },
 "res://ui/battle_conditions_settings.gd": {
  "entity_kind": "system",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "reviewed_concurrent_visual_or_ui; no_damage_inference"
 },
 "res://classes/visual_pixel_sampler.gd": {
  "entity_kind": "component",
  "attack_modes": [],
  "carriers": [],
  "damage_kinds": [],
  "review": "runtime_visual_sampler; visual_prefix_is_not_a_test"
 },
 "res://classes/projectile_interactions.gd": {"entity_kind": "component", "attack_modes": [], "carriers": [], "damage_kinds": [], "review": "shared_category_interaction_protocol_20260926"},
 "res://classes/projectile_legacy_adapters.gd": {"entity_kind": "component", "attack_modes": [], "carriers": [], "damage_kinds": [], "review": "shared_category_interaction_protocol_20260926"},
 "res://scripts/projectile_interaction_driver.gd": {"entity_kind": "system", "attack_modes": [], "carriers": [], "damage_kinds": [], "review": "shared_category_interaction_protocol_20260926"}
}
