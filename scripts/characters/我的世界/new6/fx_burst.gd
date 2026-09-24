extends Node2D
# new6 一次性原生粒子特效：只绘制 Mojang 图集单元（crit/magic/electric/smoke/redstone），
# 不使用任何自绘美术与 Line2D。
const NATIVE = preload("res://scripts/characters/我的世界/minecart/native_particles.gd")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const SELF: Script = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")

var _parts: Array[Dictionary] = []
var _closed: bool = false
var _rng := RandomNumberGenerator.new()


static func burst(parent: Node, kind: String, point: Vector2, heading: Vector2, count: int, speed: float, life: float, size: float) -> Node2D:
	var fx = SELF.new()
	_attach(fx, parent)
	fx.emit_burst(kind, point, heading, count, speed, life, size)
	fx.close()
	return fx


static func ring(parent: Node, kind: String, center: Vector2, radius: float, count: int, life: float, size: float) -> Node2D:
	var fx = SELF.new()
	_attach(fx, parent)
	fx.emit_ring(kind, center, radius, count, life, size)
	fx.close()
	return fx


static func emitter(parent: Node) -> Node2D:
	var fx = SELF.new()
	_attach(fx, parent)
	return fx


# new6 统一受击反馈：50 及以下原版通用受伤音，50 以上暴击音；
# 音量用项目 hit_audio_gain.damage_gain 随伤害 +0~+6dB，低伤害不降音量。
static func hit_sfx(src: ball, point: Vector2, amount: float) -> void:
	if not is_instance_valid(src) or not src.is_multiplayer_authority():
		return
	var event: String = "entity.player.attack.crit" if amount > 50.0 else "entity.generic.hurt"
	var db: float = HIT_GAIN.damage_gain(amount)
	if src.multiplayer.has_multiplayer_peer() and src.has_method("play_sound"):
		src.rpc("_receive_sound", event, point, db)
	AUDIO.play(src, event, point, db)


static func _attach(fx: Node2D, parent: Node) -> void:
	fx.top_level = true
	fx.z_index = 7
	fx.z_as_relative = false
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(fx)
	fx.global_position = Vector2.ZERO


func _ready() -> void:
	add_to_group("BattleTransient")
	_rng.seed = int(get_instance_id())


func emit(kind: String, point: Vector2, vel: Vector2, life: float, size: float) -> void:
	if _parts.size() >= 64:
		return
	_parts.append({"point": point, "vel": vel, "age": 0.0, "life": maxf(life, 0.05), "kind": kind, "size": size})


func emit_burst(kind: String, point: Vector2, heading: Vector2, count: int, speed: float, life: float, size: float) -> void:
	var base: Vector2 = heading.normalized() if heading.length_squared() > 0.001 else Vector2.RIGHT
	for i in range(maxi(count, 1)):
		var axis: Vector2 = base.rotated(_rng.randf_range(-1.9, 1.9))
		emit(kind, point, axis * _rng.randf_range(speed * 0.35, speed), life * _rng.randf_range(0.7, 1.2), size * _rng.randf_range(0.8, 1.2))
	queue_redraw()


func emit_ring(kind: String, center: Vector2, radius: float, count: int, life: float, size: float) -> void:
	for i in range(maxi(count, 1)):
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(count, 1)))
		emit(kind, center + dir * radius, dir * 46.0, life, size)
	queue_redraw()


func close() -> void:
	_closed = true


func _process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused:
		return
	for i in range(_parts.size() - 1, -1, -1):
		_parts[i].age += delta
		_parts[i].point += _parts[i].vel * delta
		_parts[i].vel *= maxf(0.0, 1.0 - delta * 4.0)
		if _parts[i].age >= _parts[i].life:
			_parts.remove_at(i)
	if _closed and _parts.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var prog: float = clampf(p.age / maxf(p.life, 0.01), 0.0, 1.0)
		NATIVE.draw(self, p.kind, to_local(p.point), p.size, prog, 1.0 - prog)
