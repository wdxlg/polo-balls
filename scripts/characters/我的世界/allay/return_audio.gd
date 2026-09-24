extends RefCounted
const NATIVE = preload("res://scripts/characters/我的世界/new5/audio.gd")
const MC = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const BANK = preload("res://scripts/effects/我的世界/mc16_sound_bank.gd")
const LOCAL = preload("res://scripts/audio/local_positional_sfx.gd")
static func describe(shot:Node,source:Node) -> Dictionary:
	if shot.has_meta("allay_launch_sound"): return shot.get_meta("allay_launch_sound").duplicate(true)
	var path:String=shot.get_script().resource_path
	if path.ends_with("骷髅箭.gd"): return {"bank":"stream","path":"res://audio/characters/骷髅/射箭.ogg","volume":2.0}
	if path.ends_with("烈焰弹.gd"): return {"bank":"stream","path":"res://audio/characters/我的世界/烈焰人/烈焰弹发射.ogg","volume":-2.0}
	if path.ends_with("女巫药水.gd"): return {"bank":"stream","path":"res://audio/characters/女巫/药水扔出.ogg","volume":0.8}
	if path.ends_with("凑企鹅石头.gd") or path.ends_with("knife.gd"): return {"bank":"stream","path":"res://audio/sfx/shooter/Knife_throw.ogg","volume":0.0}
	if path.ends_with("fireball.gd"): return {"bank":"new5","event":"entity.ghast.shoot","volume":-5.0}
	if path.ends_with("三叉戟.gd"): return {"bank":"mc16","event":"item.trident.throw","volume":-6.0}
	if path.ends_with("猎人_霰弹.gd"): return {"bank":"registered","event":"霰弹枪攻击","volume":-5.0}
	if path.ends_with("数学老师公式弹.gd"): return {"bank":"stream","path":"res://audio/characters/数学老师/扔笔.wav","volume":2.0}
	if path.ends_with("收债人_钱.gd"): return {"bank":"stream","path":"res://audio/characters/收债人/钞票.mp3","volume":13.0}
	if path.ends_with("clown_projectile.gd") or (shot.get("projectile_mode")!=null and shot.get("impact_damage")!=null):
		match int(shot.projectile_mode):
			0: return {"bank":"registered","event":"战士attack1","pitch":1.35}
			1: return gun_sound(0)
			2: return gun_sound(4)
			3: return {"bank":"registered","event":"KnifeThrow1","pitch":0.88}
	if is_instance_valid(source):
		if source.get("shoot_audio") is String and not str(source.get("shoot_audio")).is_empty(): return {"bank":"registered","event":source.get("shoot_audio")}
		if source.get("typing_audio_group") is String and not str(source.get("typing_audio_group")).is_empty(): return {"bank":"group","event":source.get("typing_audio_group")}
	if is_instance_valid(source) and source.get("Unique_Attack_Audio") is AudioStream:
		return {"bank":"stream","stream":source.Unique_Attack_Audio,"volume":source.Unique_Audio_Volume_DB,"pitch":source.Unique_Audio_Pitch_Scale}
	if is_instance_valid(source):
		var script:Script=source.get_script()
		while script!=null:
			var constants:Dictionary=script.get_script_constant_map()
			for key:String in ["SHOOT_SFX","THROW_SFX","SHOT_SFX","FIREBALL_LAUNCH_SFX","FIRE_SFX","THROW_AUDIO","ATTACK_SFX"]:
				if constants.get(key) is AudioStream: return {"bank":"stream","stream":constants[key]}
			script=script.get_base_script()
	return {}

static func play(owner_ball:ball,data:Dictionary,point:Vector2) -> Node:
	if data.is_empty(): return null
	var volume:float=float(data.get("volume",0.0))
	var event:String=str(data.get("event",""))
	match str(data.get("bank","")):
		"new5": return NATIVE.play(owner_ball,event,point,volume)
		"mc": return MC.play(owner_ball,event,point,volume)
		"group":
			Audios.play_sfx_from_node(event,{},false,true)
			return null
		"registered":
			Audios.play_sfx(event,{"volume":volume,"pitch":float(data.get("pitch",1.0))},false,true)
			return null
		"local":
			LOCAL.play(owner_ball,event,point,volume,float(data.get("pitch",1.0)),900.0)
			return null
	var stream:AudioStream=data.get("stream")
	if str(data.get("bank",""))=="mc16":
		var choices:Array=BANK.EVENTS.get(event,[])
		if not choices.is_empty(): stream=choices.pick_random()
	elif data.has("path"):
		stream=load(str(data.path))
	if stream==null: return null
	var player:=AudioStreamPlayer2D.new()
	player.stream=stream
	player.volume_db=volume
	player.pitch_scale=float(data.get("pitch",1.0))
	player.set_meta("allay_original_launch",true)
	player.set_meta("mc_sound_event",event)
	owner_ball.get_tree().current_scene.add_child(player)
	player.global_position=point
	player.finished.connect(player.queue_free)
	player.play()
	return player

static func gun_sound(gun_type:int) -> Dictionary:
	match gun_type:
		0: return {"bank":"registered","event":"狙击枪发射","volume":-2.0}
		1: return {"bank":"local","event":"gun_a","volume":-8.0,"pitch":1.1}
		2: return {"bank":"local","event":"gun_b","volume":-4.0,"pitch":0.9}
		3: return {"bank":"local","event":"gun_b","volume":-9.0,"pitch":1.08}
		4: return {"bank":"registered","event":"火箭筒发射","volume":-5.0}
		5: return {"bank":"stream","path":"res://audio/sfx/战斗/加特林发射.mp3","volume":-7.0}
	return {}
