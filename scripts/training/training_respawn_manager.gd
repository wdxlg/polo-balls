extends Node

# 训练模式下只复活“真正死亡”的人物。
# - 鼠标删除：节点直接离树、没有先进入 Die -> 不复活。
# - Reset/重打：旧节点在复活计时结束前已离树 -> 不复活。
# - 正常死亡：health<=0 / State.Die 且节点仍在树 -> 延迟后只重建这一人物。

@export_range(0.05,5.0,0.05) var respawn_delay:float = 0.75
@export var preserve_death_position:bool = true

var _pending:Dictionary = {}

func _physics_process(delta:float) -> void:
	if not Game.is_training_mode():
		_pending.clear()
		return

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball: continue
		var b:ball = node as ball
		if b.Type != ball.Ball_Type.Ball: continue
		if b.health > 0 and (b.state_machine == null or b.state_machine.current_state != ball.State.Die): continue
		var id:int = b.get_instance_id()
		if not _pending.has(id):
			_pending[id] = {
				"node":b,
				"left":respawn_delay,
				"position":b.global_position,
				"team":b.Team,
				"scene":b.scene_file_path,
				"setup_id":int(b.get_meta("battle_setup_id",-1)),
			}

	for id:Variant in _pending.keys().duplicate():
		var rec:Dictionary = _pending[id]
		var old:Node = rec.get("node")
		# 节点已被 Reset / 鼠标删除 / 换场景移除：明确取消复活。
		if old == null or not is_instance_valid(old) or not old.is_inside_tree():
			_pending.erase(id)
			continue
		rec["left"] = float(rec.get("left",0.0)) - delta
		_pending[id] = rec
		if float(rec["left"]) > 0.0: continue
		_respawn(rec)
		_pending.erase(id)

func _respawn(rec:Dictionary) -> void:
	var old:Node = rec.get("node")
	if old == null or not is_instance_valid(old) or not old.is_inside_tree(): return
	if not Game.is_training_mode(): return
	var path:String = str(rec.get("scene",""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("TrainingRespawnManager: 无法复活，场景路径无效: "+path)
		return
	var packed:PackedScene = load(path)
	var fresh:Node = packed.instantiate()
	if not fresh is ball:
		fresh.queue_free(); return
	var b:ball = fresh as ball
	b.Team = str(rec.get("team",""))
	b.global_position = Vector2(rec.get("position",Vector2.ZERO)) if preserve_death_position else (old as Node2D).global_position
	var setup_id:int = int(rec.get("setup_id",-1))
	if setup_id >= 0: b.set_meta("battle_setup_id",setup_id)
	var parent:Node = old.get_parent()
	if parent == null: parent = get_tree().current_scene
	parent.add_child(b,true)
	Game.free_node(old)
