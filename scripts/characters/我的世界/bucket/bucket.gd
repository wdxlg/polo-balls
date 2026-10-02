extends "res://scripts/characters/我的世界/new5/base.gd"
const FIELD = preload("res://scripts/characters/我的世界/bucket/fluid_field.gd")

@export_enum("Water:0","Lava:1") var liquid:int = 0
@export var pour_cooldown:float = 6.0
@export var first_pour_delay:float = 1.0
@export var retry_delay:float = 0.5
@export var pour_tilt_degrees:float = 70.0
@export var pour_tilt_seconds:float = 0.35

var _field:Node2D
var _pour_wait:float = 1.0
var _pour_serial:int = 0
var _shown_serial:int = 0
var _tilt_age:float = 99.0


func _ready() -> void:
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Death_Audio = AUDIO.EVENTS["entity.item.break"][0].stream
	super._ready()
	add_to_group("MCBucket")
	if liquid == FIELD.WATER: add_to_group("MCWaterBucket")
	else: add_to_group("MCLavaBucket")
	_pour_wait = first_pour_delay
	if image is Sprite2D:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_field.call_deferred()


func _ensure_field() -> void:
	if is_instance_valid(_field) or not is_inside_tree(): return
	_field = FIELD.ensure(self)


func fluid_field() -> Node2D:
	_ensure_field()
	return _field


func pour_cooldown_left() -> float:
	return _pour_wait


func step_mob(delta:float) -> void:
	_ensure_field()
	_pour_wait = maxf(_pour_wait - delta,0.0)
	if _pour_wait > 0.0 or not can_act(): return
	if pour(): _pour_wait = pour_cooldown
	else: _pour_wait = retry_delay


func pour() -> bool:
	_ensure_field()
	if not is_instance_valid(_field) or not is_multiplayer_authority(): return false
	var cell:Variant = _field.pick_place_cell(liquid,global_position)
	if cell == null: return false
	if not _field.place_source(liquid,cell,self): return false
	_pour_serial += 1
	_tilt_age = 0.0
	return true


func _process(delta:float) -> void:
	super._process(delta)
	_tilt_age += delta


func visual_mob() -> void:
	if image == null or not is_instance_valid(image) or health <= 0: return
	if _shown_serial != _pour_serial:
		_shown_serial = _pour_serial
		_tilt_age = 0.0
	var t:float = clampf(_tilt_age / maxf(pour_tilt_seconds,0.01),0.0,1.0)
	var amount:float = sin(t * PI)
	var side:float = 1.0 if _face_right else -1.0
	image.rotation = deg_to_rad(pour_tilt_degrees) * amount * side


func face_horizontal(hint:Vector2,_native_faces_left:bool = true) -> void:
	if is_multiplayer_authority() and absf(hint.x) > 0.01: _face_right = hint.x > 0


func visual_state() -> Dictionary:
	return {"time":clock,"pour":_pour_serial}


func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_pour_serial = int(data.get("pour",_pour_serial))


func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_WATER_BUCKET" if liquid == FIELD.WATER else "MC_ARMOR_INTRO_LAVA_BUCKET")


func Die() -> void:
	if is_multiplayer_authority() and liquid == FIELD.LAVA and is_instance_valid(_field): _field.owner_died(self)
	super.Die()


@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)
