extends "res://scripts/effects/我的世界/雷电.gd"
# Shared blue-white lightning and compact impact effects.
# Creeper thunder warns first; its impact sound layers with native trident thunder.
var caster:ball
var fixed_impact:bool = false
func _follow_parent_foot_until_impact() -> void:
	if not fixed_impact: super._follow_parent_foot_until_impact()
func _process(delta:float) -> void:
	if not is_instance_valid(caster) or caster.health<=0:
		queue_free()
		return
	if Game.now_stop_state or get_tree().paused or not caster.is_combat_runtime_active(): return
	super._process(delta)

func _start_impact() -> void:
	if _impact_started: return
	super._start_impact()
func _play_random_spatial_sfx(_streams:Array[AudioStream],volume_db:float,node_name:String) -> void:
	if not is_instance_valid(caster): return
	# Authority-originated, pause-aware feedback; replicated visuals never originate duplicates.
	if node_name=="CreeperThunderWarning":
		caster.native_feedback.request("entity.lightning_bolt.thunder",global_position,volume_db,0.0)
	elif node_name=="CreeperLightningImpact":
		caster.native_feedback.request("entity.generic.explode",global_position,volume_db,0.0)
		caster.native_feedback.request("item.trident.thunder",global_position,-5.0,0.0)
