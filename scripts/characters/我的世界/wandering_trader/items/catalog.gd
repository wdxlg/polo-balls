extends RefCounted
## 流浪商人物品 (docs/WANDERING_TRADER.md "物品"). One item is rolled on every wall exit and shown
## in the item frame under him until it is used. Textures: original Java 1.21.1 client jar PNGs
## (Images/characters/我的世界/流浪商人/items/SOURCE_JAVA.json); sounds: audio.gd item_* events.
const GUNPOWDER:StringName = &"gunpowder"
const BLUE_ICE:StringName = &"blue_ice"
const PUFFERFISH:StringName = &"pufferfish_bucket"
const DRIPSTONE:StringName = &"pointed_dripstone"
const SLIME_BALL:StringName = &"slime_ball"
const HAY:StringName = &"hay_block"
const POTATO:StringName = &"baked_potato"
const CACTUS:StringName = &"cactus"
const TROPICAL_FISH:StringName = &"tropical_fish_bucket"
const ALL:Array[StringName] = [GUNPOWDER,BLUE_ICE,PUFFERFISH,DRIPSTONE,SLIME_BALL,HAY,POTATO,CACTUS,TROPICAL_FISH]
## Used the moment he is out of the wall; the others stay in the frame until their trigger.
const IMMEDIATE:Array[StringName] = [BLUE_ICE,PUFFERFISH,HAY,POTATO,TROPICAL_FISH]

const ICONS:Dictionary = {
	&"gunpowder":preload("res://Images/characters/我的世界/流浪商人/items/item_gunpowder.png"),
	&"blue_ice":preload("res://Images/characters/我的世界/流浪商人/items/block_blue_ice.png"),
	&"pufferfish_bucket":preload("res://Images/characters/我的世界/流浪商人/items/item_pufferfish_bucket.png"),
	&"pointed_dripstone":preload("res://Images/characters/我的世界/流浪商人/items/item_pointed_dripstone.png"),
	&"slime_ball":preload("res://Images/characters/我的世界/流浪商人/items/item_slime_ball.png"),
	&"hay_block":preload("res://Images/characters/我的世界/流浪商人/items/block_hay_block_side.png"),
	&"baked_potato":preload("res://Images/characters/我的世界/流浪商人/items/item_baked_potato.png"),
	&"cactus":preload("res://Images/characters/我的世界/流浪商人/items/block_cactus_side.png"),
	&"tropical_fish_bucket":preload("res://Images/characters/我的世界/流浪商人/items/item_tropical_fish_bucket.png"),
}
const NAMES_ZH:Dictionary = {
	&"gunpowder":"火药",&"blue_ice":"蓝冰",&"pufferfish_bucket":"河豚桶",&"pointed_dripstone":"滴水石锥",
	&"slime_ball":"粘液球",&"hay_block":"干草块",&"baked_potato":"马铃薯",&"cactus":"仙人掌",&"tropical_fish_bucket":"热带鱼桶",
}
const TEX_BLUE_ICE:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_blue_ice.png")
const TEX_HAY_SIDE:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_hay_block_side.png")
const TEX_HAY_TOP:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_hay_block_top.png")
const TEX_CACTUS_SIDE:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_cactus_side.png")
const TEX_DRIPSTONE_TIP:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_pointed_dripstone_up_tip.png")
const TEX_STONE:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_stone.png")
const TEX_FRAME_BACK:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_item_frame.png")
const TEX_FRAME_WOOD:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_birch_planks.png")
const TEX_HEART:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/particle_heart.png")
const TEX_PUFFERFISH:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/item_pufferfish.png")
const TEX_TROPICAL_FISH:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/item_tropical_fish.png")
const PUFFERFISH_SCENE_PATH:String = "res://scenes/creatures/流浪商人_河豚.tscn"
const TROPICAL_FISH_SCENE_PATH:String = "res://scenes/creatures/流浪商人_热带鱼.tscn"

static func icon(kind:StringName) -> Texture2D:
	return ICONS.get(kind,null)

static func display_name(kind:StringName) -> String:
	return String(NAMES_ZH.get(kind,String(kind)))

static func explosion_frames() -> Array[Texture2D]:
	var frames:Array[Texture2D] = []
	for i:int in range(16):
		frames.append(load("res://Images/characters/我的世界/流浪商人/items/particle_explosion_%d.png" % i) as Texture2D)
	return frames

# ------------------------------------------------------------------ shared unit helpers
## Living, targetable characters / summons (every team) that item hazards can touch.
static func units(context:Node) -> Array[ball]:
	var result:Array[ball] = []
	if not is_instance_valid(context) or not context.is_inside_tree(): return result
	for raw:Node in context.get_tree().get_nodes_in_group(&"Ball"):
		if not (raw is ball) or raw.is_queued_for_deletion(): continue
		var unit:ball = raw as ball
		if unit.health <= 0 or unit.Type not in [ball.Ball_Type.Ball,ball.Ball_Type.Creature]: continue
		if not unit.is_combat_targetable(): continue
		if unit.has_method(&"is_hidden_in_wall") and (bool(unit.call(&"is_hidden_in_wall")) or int(unit.get(&"wall_phase")) != 0): continue
		result.append(unit)
	return result

## World rect of a unit's body shape (falls back to a small box around its position).
static func body_rect(unit:Node2D) -> Rect2:
	var body:CollisionShape2D = unit.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if body == null or body.shape == null: return Rect2(unit.global_position - Vector2(6,6),Vector2(12,12))
	return body.global_transform*body.shape.get_rect()

static func enemy_of(trader:Node,target:Variant) -> bool:
	if not is_instance_valid(trader) or not is_instance_valid(target): return false
	if trader.has_method(&"wt_enemy"): return bool(trader.call(&"wt_enemy",target))
	return false

static func paused(context:Node) -> bool:
	if not is_instance_valid(context) or not context.is_inside_tree(): return true
	return Game.now_stop_state or context.get_tree().paused

## Damage with the §1 hit sound. source = null for neutral hazards (they hurt every side,
## including the trader himself). Returns the actual health lost.
static func hurt(trader:Node,target:ball,amount:float,point:Vector2,credit_trader:bool) -> float:
	if not is_instance_valid(target) or amount <= 0.0 or target.health <= 0: return 0.0
	var before:float = maxf(float(target.health),0.0)
	var source:Node = trader if credit_trader and is_instance_valid(trader) else null
	if source != null and source.has_method(&"is_damage_output_disabled") and bool(source.call(&"is_damage_output_disabled")): return 0.0
	target.receive_positional_damage(amount,point,false,source)
	var actual:float = before - (maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0)
	if actual > 0.0 and is_instance_valid(trader) and trader.has_method(&"wt_hit_sound"): trader.call(&"wt_hit_sound",actual,target.global_position)
	return actual
