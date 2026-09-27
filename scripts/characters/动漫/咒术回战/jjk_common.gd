extends RefCounted
## 咒术回战公共工具：带咒术上下文的分类伤害、范围索敌、地图范围、音效。
## 不是新的伤害系统：所有伤害仍走 ball.receive_classified_positional_damage()。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const CTX:String = "_jjk_ctx"

const SOUNDS:Dictionary = {
	"black_flash": preload("res://audio/characters/咒术回战/black_flash.ogg"),
	"gojo_intro": preload("res://audio/characters/咒术回战/gojo_intro.ogg"),
	"gojo_blue": preload("res://audio/characters/咒术回战/gojo_blue.ogg"),
	"gojo_red": preload("res://audio/characters/咒术回战/gojo_red.ogg"),
	"gojo_purple": preload("res://audio/characters/咒术回战/gojo_purple.ogg"),
	"gojo_purple_sfx": preload("res://audio/characters/咒术回战/gojo_purple_sfx.ogg"),
	"gojo_purple_200": preload("res://audio/characters/咒术回战/gojo_purple_200.ogg"),
	"gojo_domain": preload("res://audio/characters/咒术回战/gojo_domain.ogg"),
	"gojo_teleport": preload("res://audio/characters/咒术回战/gojo_teleport.ogg"),
	"sukuna_intro": preload("res://audio/characters/咒术回战/sukuna_intro.ogg"),
	"sukuna_dismantle": preload("res://audio/characters/咒术回战/sukuna_dismantle.ogg"),
	"sukuna_cleave": preload("res://audio/characters/咒术回战/sukuna_cleave.ogg"),
	"sukuna_fuga": preload("res://audio/characters/咒术回战/sukuna_fuga.ogg"),
	"sukuna_domain": preload("res://audio/characters/咒术回战/sukuna_domain.ogg"),
	"sukuna_world_slash": preload("res://audio/characters/咒术回战/sukuna_world_slash.ogg"),
	"mahoraga_wheel": preload("res://audio/characters/咒术回战/mahoraga_wheel.ogg"),
	"mahoraga_summon": preload("res://audio/characters/咒术回战/mahoraga_summon.ogg"),
	"mahoraga_roar": preload("res://audio/characters/咒术回战/mahoraga_roar.ogg"),
	"agito_roar": preload("res://audio/characters/咒术回战/agito_roar.ogg"),
	"agito_thunder": preload("res://audio/characters/咒术回战/agito_thunder.ogg"),
}

## 带上下文的伤害。ctx 可含：
##  phenomenon:String  魔虚罗适应用的“现象”键；
##  sure_hit:bool      领域必中（无视无下限/格挡）；
##  bypass_infinity:bool 无视无下限（世界斩、领域展延、适应后的魔虚罗）；
##  unadaptable:bool   魔虚罗无法适应（茈）；
##  ignore_block:bool
static func hit(source:ball,target:ball,amount:float,point:Vector2,kind:StringName = &"magic",ctx:Dictionary = {}) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target) or amount <= 0.0 or not is_finite(amount): return false
	if target.health <= 0 or not U.enemy(source,target) or source.is_damage_output_disabled(): return false
	var c:Dictionary = ctx.duplicate()
	c["source"] = source
	var had:bool = target.has_meta(CTX)
	var previous:Variant = target.get_meta(CTX) if had else null
	target.set_meta(CTX,c)
	var ignore_block:bool = bool(ctx.get("ignore_block",false)) or bool(ctx.get("sure_hit",false))
	var accepted:bool = target.receive_classified_positional_damage(amount,point,kind,ignore_block,source)
	if had: target.set_meta(CTX,previous)
	elif target.has_meta(CTX): target.remove_meta(CTX)
	return accepted

static func ctx_of(target:Node) -> Dictionary:
	if is_instance_valid(target) and target.has_meta(CTX):
		var value:Variant = target.get_meta(CTX)
		if value is Dictionary: return value
	return {}

## 击退/眩晕也带上下文，便于无下限与适应判断。
static func knock(source:ball,target:ball,dir:Vector2,distance:float,speed:float,stun:float = 0.0,ctx:Dictionary = {}) -> void:
	if not is_instance_valid(target) or target.health <= 0 or not U.enemy(source,target): return
	var c:Dictionary = ctx.duplicate()
	c["source"] = source
	var had:bool = target.has_meta(CTX)
	var previous:Variant = target.get_meta(CTX) if had else null
	target.set_meta(CTX,c)
	if dir.length_squared() < 0.0001: dir = Vector2.RIGHT
	target.apply_knockback(dir.normalized(),distance,speed,0.4,stun,{"source":source,"lock_control":stun > 0.0})
	if had: target.set_meta(CTX,previous)
	elif target.has_meta(CTX): target.remove_meta(CTX)

static func stun(source:ball,target:ball,duration:float,ctx:Dictionary = {}) -> void:
	if not is_instance_valid(target) or target.health <= 0 or duration <= 0.0: return
	var c:Dictionary = ctx.duplicate()
	c["source"] = source
	var had:bool = target.has_meta(CTX)
	var previous:Variant = target.get_meta(CTX) if had else null
	target.set_meta(CTX,c)
	target.apply_stun(duration,source)
	if had: target.set_meta(CTX,previous)
	elif target.has_meta(CTX): target.remove_meta(CTX)

static func candidates(node:Node) -> Array:
	return TOOLS.targeting_candidates(node)

static func enemies_in_circle(source:ball,center:Vector2,radius:float) -> Array[ball]:
	var result:Array[ball] = []
	for raw:Variant in candidates(source):
		if not raw is ball: continue
		var t:ball = raw
		if t.health <= 0 or not U.enemy(source,t): continue
		if t.global_position.distance_to(center) <= radius + U.radius(t): result.append(t)
	return result

static func allies_in_circle(source:ball,center:Vector2,radius:float,include_self:bool = true) -> Array[ball]:
	var result:Array[ball] = []
	for raw:Variant in source.get_tree().get_nodes_in_group("Ball"):
		if not raw is ball: continue
		var t:ball = raw
		if t.health <= 0 or (t == source and not include_self): continue
		if not t.is_combat_targetable() and t != source: continue
		if t != source and (source.Team.is_empty() or t.Team != source.Team): continue
		if t.global_position.distance_to(center) <= radius + U.radius(t): result.append(t)
	return result

static func enemies_on_segment(source:ball,a:Vector2,b:Vector2,half_width:float) -> Array[ball]:
	var result:Array[ball] = []
	for raw:Variant in candidates(source):
		if not raw is ball: continue
		var t:ball = raw
		if t.health <= 0 or not U.enemy(source,t): continue
		if U.segment_distance(t.global_position,a,b) <= half_width + U.radius(t): result.append(t)
	return result

static func nearest_enemy(source:ball) -> ball:
	return U.nearest(source)

static func map_rect(node:Node2D) -> Rect2:
	var rect:Rect2 = TOOLS.map_rect(node)
	if rect.size.x > 10.0 and rect.size.y > 10.0: return rect
	var vp:Viewport = node.get_viewport()
	if vp != null:
		var inv:Transform2D = vp.get_canvas_transform().affine_inverse()
		var vis:Rect2 = vp.get_visible_rect()
		var p0:Vector2 = inv * vis.position
		var p1:Vector2 = inv * vis.end
		return Rect2(p0,p1-p0).abs()
	return Rect2(node.global_position - Vector2(800,450),Vector2(1600,900))

static func clamp_to_map(node:Node2D,p:Vector2,margin:float = 24.0) -> Vector2:
	var r:Rect2 = map_rect(node).grow(-margin)
	if r.size.x <= 0.0 or r.size.y <= 0.0: return p
	return Vector2(clampf(p.x,r.position.x,r.end.x),clampf(p.y,r.position.y,r.end.y))

## 本地播放（调用方负责网络广播）。
static func play_local(context:Node,key:String,point:Vector2,volume_db:float = 0.0,max_distance:float = 2600.0) -> AudioStreamPlayer2D:
	if not SOUNDS.has(key) or not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	if tree.current_scene == null: return null
	var player:AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = SOUNDS[key]
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.attenuation = 0.5
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	tree.current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("BattleTransient")
	player.add_to_group("JJKSound")
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player

static func english() -> bool:
	return str(Game.current_locale).begins_with("en")
