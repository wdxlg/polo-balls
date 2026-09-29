extends RefCounted
## Shared legacy state/ownership adapters. Never used to decide projectile identity.
const CUSTOM = {
	"res://scripts/effects/我的世界/女巫药水.gd": {"owner": "source_witch", "damage_value": 50.0, "speed_value": 330.0, "ended": "_exploded", "radius": 9.0},
	"res://scripts/effects/我的世界/水泼弹.gd": {"owner": "_caster", "damage": "_damage", "speed_value": 300.0, "ended": "_hit", "radius": 8.0},
	"res://scripts/effects/我的世界/蛛网弹.gd": {"owner": "_caster", "damage": "_damage", "speed": "_speed", "ended": "_hit", "radius": 8.0},
	"res://scripts/shooter/军火商_子弹.gd": {"owner_method": "_resolve_master", "team": "Team", "damage": "damage_amount", "speed": "speed", "ended": "_exploded", "radius": 5.0},
	"res://scripts/shooter/猎人_霰弹.gd": {"owner_method": "_resolve_master", "team": "Team", "damage": "damage_amount", "speed": "speed", "ended": "_finished", "radius": 4.0},
	"res://scripts/shooter/魔角猎人_黑弹.gd": {"owner_method": "_resolve_master", "team": "Team", "damage": "damage_amount", "speed": "speed", "ended": "_finished", "radius": 8.0},
	"res://scripts/shooter/建筑工人_砖块.gd": {"owner": "builder_owner", "team": "team", "damage": "enemy_damage", "speed": "move_speed", "active": "_launched", "radius": 8.0},
	"res://scripts/shooter/数学老师公式弹.gd": {"owner": "owner_teacher", "team": "projectile_team", "damage": "damage_amount", "speed": "travel_speed", "authority": "authoritative_logic", "through_walls": true, "radius": 10.0},
	"res://scripts/shooter/收债人_钱.gd": {"owner": "collector", "team": "collector_team", "damage_value": 0.0, "speed": "projectile_speed", "authority": "authoritative_logic", "radius": 7.0},
	"res://scripts/shooter/战争女神_火焰剑气.gd": {"owner": "owner_ball", "team": "team", "damage": "damage_amount", "speed": "speed", "ended": "_finished", "radius": 9.0},
	"res://scripts/shooter/凑企鹅石头.gd": {"owner": "Master", "team": "Team", "damage": "impact_damage", "speed": "travel_speed", "active": "flying", "radius": 10.0},
	"res://scripts/effects/薇欧拉_火焰弹.gd": {"owner": "owner_ref", "damage": "damage_amount", "speed": "speed", "ended": "_finished", "radius": 9.0},
	"res://scripts/effects/薇欧拉_文字弹.gd": {"owner": "owner_ref", "damage": "damage_amount", "speed": "speed", "through_walls": true, "radius": 8.0},
	"res://scripts/effects/乌鲁鲁火焰弹.gd": {"owner": "owner_ref", "multiplier": "impact_damage_multiplier", "speed_value": 300.0, "ended": "_finished", "radius": 9.0},
	"res://scripts/effects/我的世界/三叉戟.gd": {"owner": "unit", "damage_value": 18.0, "speed_value": 400.0, "state": "flight_state", "state_value": 1, "radius": 6.0},
	"res://scripts/characters/我的世界/new5/fireball.gd": {"neutral": true, "damage": "Damage", "speed_value": 185.0, "ended": "exploded", "radius": 8.0},
}

# Explicit direct-payload semantics, verified against the native damage calls.
const PAYLOAD_KINDS = {
	"res://scripts/effects/我的世界/烈焰弹.gd": "fire",
	"res://scripts/effects/薇欧拉_火焰弹.gd": "fire",
	"res://scripts/effects/乌鲁鲁火焰弹.gd": "fire",
	"res://scripts/shooter/战争女神_火焰剑气.gd": "fire",
}
static func config(shot:Node) -> Dictionary:
	if shot.get_script()==null: return {}
	return CUSTOM.get(shot.get_script().resource_path,{})

static func source(shot:Node,c:Dictionary) -> Node:
	var value:Variant = null
	if c.has("owner_method") and shot.has_method(c.owner_method): value = shot.call(c.owner_method)
	elif c.has("owner"): value = shot.get(c.owner)
	if not is_instance_valid(value): return null
	if value is WeakRef: value = value.get_ref()
	return value if is_instance_valid(value) and value is Node else null

static func team(shot:Node,c:Dictionary) -> String:
	if c.has("team"): return str(shot.get(c.team))
	var owner:Node = source(shot,c)
	return str(owner.Team) if owner is ball else ""
