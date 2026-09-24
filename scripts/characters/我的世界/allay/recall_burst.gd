extends RefCounted
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")
var unit:ball
var phase:String=""
var elapsed:float=0.0
var cooldown:float=0.0
var serial:int=0
var selected:Array[WeakRef]=[]
var spin_hits:Dictionary={}
var last_consumed:int=0
var last_damage:float=0.0
func _init(owner_ball:ball) -> void: unit=owner_ball
func busy() -> bool: return not phase.is_empty()
func available() -> Array[Node]:
	var result:Array[Node]=[]
	for shot:Node in unit.get_tree().get_nodes_in_group("AllayFlyingNote"):
		if not is_instance_valid(shot) or shot.is_queued_for_deletion() or shot._spent or shot.health<=0: continue
		if shot.Master==unit and shot._recall_state==0: result.append(shot)
	result.sort_custom(func(a:Node,b:Node)->bool: return a.global_position.distance_squared_to(unit.global_position)<b.global_position.distance_squared_to(unit.global_position))
	return result
func live(arrived_only:bool=false) -> Array[Node]:
	var result:Array[Node]=[]
	for ref:WeakRef in selected:
		var shot:Variant=ref.get_ref()
		if not is_instance_valid(shot) or shot.is_queued_for_deletion() or shot._spent or shot.health<=0: continue
		if shot._recall_token!=serial or shot._recall_state==0: continue
		if arrived_only and shot._recall_state!=2: continue
		result.append(shot)
	return result
func try_start() -> bool:
	if busy() or cooldown>0.0 or not unit.active() or unit.dizziness or unit.is_damage_output_disabled(): return false
	var enemy:ball=null
	for target:Node in unit.get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(unit,target) or not target.is_combat_lockable(): continue
		if not unit.Team.is_empty() and target.Team==unit.Team: continue
		if unit.global_position.distance_to(target.global_position)<=unit.recall_trigger and U.line_clear(unit,unit.global_position,target.global_position):
			enemy=target
			break
	if enemy==null: return false
	var flying:Array[Node]=available()
	if unit.notes+flying.size()<5: return false
	serial+=1
	phase="gather"; elapsed=0.0; cooldown=unit.recall_cooldown
	selected.clear(); spin_hits.clear(); last_consumed=0; last_damage=0.0
	# Retrieve existing airborne notes first, not just the stock around the body.
	for shot:Node in flying:
		if selected.size()>=20: break
		selected.append(weakref(shot))
		shot.begin_recall(unit,serial)
	while selected.size()<20 and unit.notes>0:
		var shot:Node=unit.fire_note(enemy)
		unit.notes-=1
		selected.append(weakref(shot))
		shot.begin_recall(unit,serial)
		shot.join_recall()
	return true
func accepts(token:int) -> bool: return phase=="gather" and token==serial
func advance(delta:float) -> void:
	if not unit.active() or unit.dizziness or unit.is_damage_output_disabled(): return
	cooldown=maxf(cooldown-maxf(delta,0.0),0.0)
	if not busy(): return
	elapsed+=maxf(delta,0.0)
	var ring:Array[Node]=live(true)
	if phase=="gather":
		if live().size()==ring.size() or elapsed>=1.0:
			for shot:Node in live():
				if shot._recall_state==1: shot.cancel_recall()
			phase="spin"; elapsed=0.0
			if not ring.is_empty(): unit.play_sound("allay.recall.spin",-3.0)
	elif phase=="spin" and elapsed>=unit.recall_spin_time:
		phase="collapse"; elapsed=0.0
	elif phase=="collapse" and elapsed>=unit.recall_collapse_time:
		finish()
		return
	if ring.is_empty() and live().is_empty():
		phase=""; selected.clear()
		return
	var progress:float=clampf(elapsed/maxf(unit.recall_spin_time,0.01),0.0,1.0)
	var speed:float=lerpf(4.0,32.0,progress*progress) if phase=="spin" else 4.0
	var radius:float=30.0
	if phase=="collapse":
		speed=32.0
		radius=30.0*pow(1.0-clampf(elapsed/maxf(unit.recall_collapse_time,0.01),0.0,1.0),2.0)
	for shot:Node in ring:
		shot._recall_angle+=speed*delta
		var from:Vector2=shot.global_position
		var desired:Vector2=unit.global_position+Vector2.from_angle(shot._recall_angle)*radius
		var to:Vector2=from.lerp(desired,1.0-exp(-24.0*maxf(delta,0.0))) if phase!="collapse" else desired
		if unit.CAPTURE.sweep_note(shot,from,to): continue
		if unit.CAPTURE.sweep(shot,from,to): continue
		shot.global_position=to
		if phase!="collapse": spin_contact(shot,from,to)
func spin_contact(shot:Node,from:Vector2,to:Vector2) -> void:
	for target:Node in unit.get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(unit,target) or target.is_queued_for_deletion(): continue
		if not unit.Team.is_empty() and target.Team==unit.Team: continue
		if U.segment_distance(target.global_position,from,to)>U.radius(target)+6.0: continue
		var id:int=target.get_instance_id()
		if unit.clock<float(spin_hits.get(id,-1000.0)): continue
		if not U.line_clear(unit,to,target.global_position): continue
		spin_hits[id]=unit.clock+0.2
		var amount:float=unit.effective_outgoing_damage(shot._recall_damage*0.15)
		if amount>0.0 and target.receive_positional_damage(amount,to,false,unit):
			var axis:Vector2=unit.global_position.direction_to(target.global_position)
			target.apply_knockback(axis if axis!=Vector2.ZERO else Vector2.RIGHT,8.0,120.0,0.0,0.0,{"source":unit,"stop_on_character":true})
func finish() -> void:
	last_consumed=0; last_damage=0.0
	for shot:Node in live(true):
		last_consumed+=1
		last_damage+=shot._recall_damage
		shot._spent=true
		shot.queue_free()
	last_damage*=1.2
	if last_consumed>=5:
		unit.play_sound("allay.recall.release",0.0)
		unit.spawn_recall_wave(unit.global_position,last_damage,true)
		if unit.multiplayer.has_multiplayer_peer(): unit._allay_recall_wave.rpc(unit.global_position)
	else: last_damage=0.0
	phase=""; selected.clear()
func clear() -> void:
	for shot:Node in live():
		shot._spent=true
		shot.queue_free()
	selected.clear(); phase=""; spin_hits.clear()
