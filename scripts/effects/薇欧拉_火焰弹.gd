extends Node2D
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")

const FIRE_FIELD_SCRIPT = preload("res://scripts/effects/薇欧拉_火场.gd")
const WAR_GODDESS_BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const WAR_GODDESS_BURN_NODE_NAME:StringName = &"WarGoddessBurnStatus"
const FIRE_ARROW_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/01_箭形火焰箭.png")
const FIRE_EXPLOSION_SFX:AudioStream = preload("res://audio/characters/薇欧拉/火焰爆炸_[cut_3sec].mp3")

const ARROW_LENGTH:float = 56.0
const ARROW_MAIN_ALPHA:float = 0.78
const ARROW_LIGHT_TEXTURE_SIZE:int = 96

var owner_ref:WeakRef = null
var target_ref:WeakRef = null
var damage_amount:float = 120.0
var speed:float = 640.0
var lifetime:float = 4.0
var elapsed:float = 0.0
var explosion_radius:float = 58.0
var burn_duration:float = 3.0
var burn_tick_interval:float = 0.5
var burn_tick_damage:float = 5.0
var fire_field_config:Dictionary = {}
var _finished:bool = false
var _pass_through_direction:Vector2 = Vector2.ZERO

var _visual_root:Node2D = null
var _arrow_main:Sprite2D = null
var _arrow_light:PointLight2D = null
var _phase:float = 0.0

func setup(owner_node:Node,target_node:Node2D,start_position:Vector2,config:Dictionary = {}) -> void:
    owner_ref = weakref(owner_node)
    target_ref = weakref(target_node)
    global_position = start_position
    damage_amount = maxf(float(config.get("damage",damage_amount)),0.0)
    speed = maxf(float(config.get("speed",speed)),20.0)
    lifetime = maxf(float(config.get("lifetime",lifetime)),0.2)
    explosion_radius = maxf(float(config.get("explosion_radius",config.get("impact_radius",explosion_radius))),8.0)
    burn_duration = maxf(float(config.get("burn_duration",burn_duration)),0.1)
    burn_tick_interval = maxf(float(config.get("burn_tick_interval",burn_tick_interval)),0.05)
    burn_tick_damage = maxf(float(config.get("burn_tick_damage",burn_tick_damage)),0.0)
    fire_field_config = config.get("fire_field",{}) as Dictionary

func _ready() -> void:
    add_to_group("AllayExtendedProjectile")
    z_as_relative = false
    z_index = 75
    add_to_group("BattleTransient")
    _build_fire_arrow_visual()

func _physics_process(delta:float) -> void:
    if _finished:
        return
    elapsed += delta
    _phase += delta * 12.0
    if elapsed >= lifetime:
        queue_free()
        return
    var target:Node2D = _target()
    if target == null:
        queue_free()
        return
    var to_target:Vector2 = target.global_position - global_position
    var intangible_target:bool = PROJECTILE_CONTACT.ignores(target)
    if intangible_target:
        # Never clamp movement to an intangible target's center or turn back into it.
        if _pass_through_direction.is_zero_approx():
            _pass_through_direction = to_target.normalized() if not to_target.is_zero_approx() else Vector2.RIGHT.rotated(rotation)
        to_target = _pass_through_direction * maxf(speed * delta + 1.0,1.0)
    var distance_value:float = to_target.length()
    if distance_value <= 0.001:
        if _owner() != null and _owner().is_multiplayer_authority() and target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): return
        _explode(global_position)
        return
    var dir:Vector2 = to_target / distance_value
    var step_distance:float = minf(speed * delta,distance_value)
    var next_position:Vector2 = global_position + dir * step_distance
    if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,global_position,next_position): return
    var hit:Dictionary = _raycast_impact(global_position,next_position)
    if not hit.is_empty():
        var impact_position:Vector2 = hit.get("position",next_position) as Vector2
        global_position = impact_position
        rotation = dir.angle()
        _explode(impact_position)
        return
    global_position = next_position
    rotation = dir.angle()
    if not intangible_target and step_distance >= distance_value - 0.001:
        if _owner() != null and _owner().is_multiplayer_authority() and target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): return
        _explode(target.global_position)
        return
    _animate_fire_arrow()

func _raycast_impact(from_position:Vector2,to_position:Vector2) -> Dictionary:
    var params:=PhysicsRayQueryParameters2D.new()
    params.from = from_position
    params.to = to_position
    params.collision_mask = 3
    params.collide_with_bodies = true
    params.collide_with_areas = true
    var owner_node:Node = _owner()
    params.exclude = _collect_owner_collision_rids(owner_node)
    for _attempt:int in range(32):
        var hit:Dictionary=get_world_2d().direct_space_state.intersect_ray(params)
        if hit.is_empty(): return hit
        var node:Node=hit.get("collider")
        while is_instance_valid(node) and not node is ball: node=node.get_parent()
        if not PROJECTILE_CONTACT.ignores(node):
            if owner_node == null or not owner_node.is_multiplayer_authority() or not is_instance_valid(node) or not node.has_method("try_full_projectile_dodge") or not bool(node.call("try_full_projectile_dodge",self)): return hit
        var excluded:Array[RID]=params.exclude
        _append_collision_rids_recursive(node,excluded)
        params.exclude=excluded
    return {}


func _collect_owner_collision_rids(owner_node:Node) -> Array[RID]:
    var result:Array[RID] = []
    if owner_node == null or not is_instance_valid(owner_node):
        return result
    _append_collision_rids_recursive(owner_node,result)
    return result

func _append_collision_rids_recursive(node:Node,out:Array[RID]) -> void:
    if node is CollisionObject2D:
        var rid:RID = (node as CollisionObject2D).get_rid()
        if rid.is_valid() and not out.has(rid):
            out.append(rid)
    for child:Node in node.get_children():
        _append_collision_rids_recursive(child,out)

func _target() -> Node2D:
    if target_ref == null:
        return null
    var raw:Variant = target_ref.get_ref()
    if raw is Node2D and is_instance_valid(raw):
        var node:Node2D = raw as Node2D
        if node.get("health") != null and int(node.get("health")) <= 0:
            return null
        return node
    return null

func _owner() -> Node:
    if owner_ref == null:
        return null
    var raw:Variant = owner_ref.get_ref()
    if raw is Node and is_instance_valid(raw):
        return raw as Node
    return null

func _explode(impact_position:Vector2) -> void:
    if _finished:
        return
    _finished = true
    global_position = impact_position
    var owner_node:Node = _owner()
    _play_explosion_sfx(impact_position,owner_node)
    if owner_node != null and owner_node.is_multiplayer_authority():
        _apply_explosion_damage(owner_node,impact_position)
    var field:Node2D = FIRE_FIELD_SCRIPT.new() as Node2D
    if field != null:
        field.name = "薇欧拉_火场_%d" % Time.get_ticks_usec()
        get_tree().current_scene.add_child(field,true)
        var field_config:Dictionary = fire_field_config.duplicate(true)
        field_config["radius"] = explosion_radius
        field_config["burn_duration"] = burn_duration
        field_config["burn_tick_interval"] = burn_tick_interval
        field_config["burn_tick_damage"] = burn_tick_damage
        field.call("setup",owner_node,impact_position,field_config)
    queue_free()

func _play_explosion_sfx(position_value:Vector2,owner_node:Node) -> void:
    if FIRE_EXPLOSION_SFX == null or not is_inside_tree():
        return
    var world:Node = get_tree().current_scene
    if world == null:
        return
    var player:=AudioStreamPlayer2D.new()
    player.name = "ViolaFireExplosionSFX"
    player.stream = FIRE_EXPLOSION_SFX
    player.global_position = position_value
    var owner_gain:float = float(owner_node.get("viola_audio_gain_db")) if owner_node != null and owner_node.get("viola_audio_gain_db") != null else 0.0
    player.volume_db = clampf(owner_gain - 3.0,-20.0,8.0)
    player.pitch_scale = randf_range(0.97,1.03)
    player.max_distance = 1800.0
    player.attenuation = 0.75
    if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
        player.bus = &"GameplayRecord"
    world.add_child(player)
    player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
    player.play()

func _apply_explosion_damage(owner_node:Node,impact_position:Vector2) -> void:
    var radius_sq:float = explosion_radius * explosion_radius
    for node:Node in get_tree().get_nodes_in_group("Ball"):
        if not node is ball:
            continue
        var target:ball = node as ball
        if not _is_enemy(target,owner_node):
            continue
        if impact_position.distance_squared_to(target.global_position) > radius_sq:
            continue
        var applied:bool = target.receive_fire_spatial_damage(
            damage_amount,
            {"point":target.global_position,"source":owner_node},
            false,
            false
        )
        if applied:
            _apply_war_goddess_burn(target,owner_node)
            _play_burn_damage_sfx(owner_node,target.global_position)

func _is_enemy(target:ball,owner_node:Node) -> bool:
    if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(owner_node,target): return false # 皓宸复制品及其产物不把己方选为目标
    if target == null or not is_instance_valid(target) or target.health <= 0:
        return false
    if target == owner_node:
        return false
    if not target.is_combat_targetable():
        return false
    var owner_team:String = str(owner_node.get("Team")) if owner_node != null else ""
    if not owner_team.is_empty() and target.Team == owner_team:
        return false
    return true

func _apply_war_goddess_burn(target:ball,owner_node:Node) -> void:
    if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
        return
    if not owner_node is ball:
        return
    var source:ball = owner_node as ball
    var existing:Node = target.get_node_or_null(NodePath(String(WAR_GODDESS_BURN_NODE_NAME)))
    if existing != null and existing.has_method("refresh"):
        existing.call("refresh",source,burn_duration,burn_tick_damage)
        return
    var status:Node2D = WAR_GODDESS_BURN_SCRIPT.new() as Node2D
    if status == null:
        return
    status.name = WAR_GODDESS_BURN_NODE_NAME
    status.top_level = true
    target.add_child(status,true)
    status.global_position = target.global_position
    status.call("setup",target,source,burn_duration,burn_tick_interval,burn_tick_damage)

func _play_burn_damage_sfx(owner_node:Node,position_value:Vector2) -> void:
    if owner_node != null and owner_node.has_method("play_war_burn_tick_sfx"):
        owner_node.call("play_war_burn_tick_sfx",position_value)

func _make_arrow_light_texture() -> GradientTexture2D:
    var gradient:=Gradient.new()
    gradient.offsets = PackedFloat32Array([0.0,0.38,0.76,1.0])
    gradient.colors = PackedColorArray([
        Color(1.0,1.0,1.0,1.0),
        Color(1.0,0.90,0.62,0.74),
        Color(1.0,0.38,0.05,0.24),
        Color(1.0,0.15,0.01,0.0)
    ])
    var texture:=GradientTexture2D.new()
    texture.width = ARROW_LIGHT_TEXTURE_SIZE
    texture.height = ARROW_LIGHT_TEXTURE_SIZE
    texture.fill = GradientTexture2D.FILL_RADIAL
    texture.fill_from = Vector2(0.5,0.5)
    texture.fill_to = Vector2(1.0,0.5)
    texture.gradient = gradient
    return texture

func _build_fire_arrow_visual() -> void:
    _visual_root = Node2D.new()
    _visual_root.name = "FireArrowVisual"
    add_child(_visual_root)
    var base_scale:float = ARROW_LENGTH / maxf(float(FIRE_ARROW_TEXTURE.get_width()),1.0)

    _arrow_main = Sprite2D.new()
    _arrow_main.name = "FlameArrow"
    _arrow_main.texture = FIRE_ARROW_TEXTURE
    _arrow_main.scale = Vector2.ONE * base_scale
    _arrow_main.self_modulate = Color(1.0,0.96,0.86,ARROW_MAIN_ALPHA)
    _visual_root.add_child(_arrow_main)

    # V190：不再复制放大同一张火焰贴图做“假发光/残影”，改用真正 PointLight2D。
    _arrow_light = PointLight2D.new()
    _arrow_light.name = "FireArrowPointLight"
    _arrow_light.texture = _make_arrow_light_texture()
    _arrow_light.texture_scale = 0.72
    _arrow_light.color = Color(1.0,0.31,0.045,1.0)
    _arrow_light.energy = 1.25
    _arrow_light.blend_mode = Light2D.BLEND_MODE_ADD
    _arrow_light.shadow_enabled = false
    _arrow_light.range_z_min = -1024
    _arrow_light.range_z_max = 1024
    _visual_root.add_child(_arrow_light)

func _animate_fire_arrow() -> void:
    if _visual_root == null or not is_instance_valid(_visual_root):
        return
    var length_pulse:float = 1.0 + sin(_phase) * 0.050 + sin(_phase * 0.47) * 0.020
    var body_pulse:float = 1.0 + sin(_phase * 0.71 + 1.2) * 0.022
    _visual_root.scale = Vector2(length_pulse,body_pulse)
    _visual_root.position.y = sin(_phase * 1.35) * 0.85
    _visual_root.rotation = sin(_phase * 0.62) * 0.014
    if _arrow_main != null and is_instance_valid(_arrow_main):
        _arrow_main.self_modulate.a = clampf(ARROW_MAIN_ALPHA + sin(_phase * 0.82) * 0.045,0.66,0.86)
    if _arrow_light != null and is_instance_valid(_arrow_light):
        _arrow_light.energy = 1.25 + sin(_phase * 0.58 + 0.8) * 0.12
