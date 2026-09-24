extends RefCounted
## Reviewed flying objects only. Native state is snapshotted on confirmed contact.
const BALL_PROJECTILES = [
	"res://scripts/shooter/科学家弹丸.gd",
	"res://scripts/shooter/不坏煎饼弹.gd",
	"res://scripts/shooter/伪军子弹.gd",
	"res://scripts/shooter/堵桥PSG子弹.gd",
	"res://scripts/shooter/磁铁_电球.gd",
	"res://scripts/shooter/菊花茶水滴.gd",
	"res://scripts/shooter/裁判牌.gd",
	"res://scripts/shooter/酒瓶.gd",
	"res://scripts/shooter/键盘文字.gd",
	"res://scripts/shooter/蛇咬.gd",
	"res://scripts/shooter/clown/clown_projectile.gd",
]
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

static func native_descriptor(damage:float,speed:float) -> Dictionary:
	# Classification only. native_return.gd stores the complete approved live projectile.
	return {"kind":"native","damage":maxf(damage,0.0),"speed":speed}

static func describe(shot:Node) -> Dictionary:
	var c:Dictionary = config(shot)
	if not c.is_empty():
		if c.has("ended") and bool(shot.get(c.ended)): return {}
		if c.has("active") and not bool(shot.get(c.active)): return {}
		if c.has("state") and int(shot.get(c.state))!=int(c.state_value): return {}
		if c.has("authority") and not bool(shot.get(c.authority)): return {}
		var owner:Node = source(shot,c)
		if not c.get("neutral",false) and (owner==null or not owner is ball or owner.health<=0 or not owner.is_multiplayer_authority()): return {}
		var damage:float = float(shot.get(c.damage)) if c.has("damage") else float(c.get("damage_value",0.0))
		if c.has("multiplier"): damage = owner.attack_damage(float(shot.get(c.multiplier)))
		var speed:float = float(shot.get(c.speed)) if c.has("speed") else float(c.get("speed_value",300.0))
		return native_descriptor(damage,speed)
	if not shot is ball or shot.Type not in [ball.Ball_Type.Shooter,ball.Ball_Type.Shooter_with_Health] or shot.health<=0: return {}
	var script:Script = shot.get_script()
	while script!=null:
		if script.resource_path in BALL_PROJECTILES:
			var damage:float = float(shot.Damage)
			if script.resource_path.ends_with("clown_projectile.gd"):
				if shot.exploded: return {}
				damage = float(shot.impact_damage)
			return native_descriptor(damage,float(shot.Speed))
		script = script.get_base_script()
	return {}
