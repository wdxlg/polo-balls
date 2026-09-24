extends ball
const ITEM_DEATH=preload("res://scripts/effects/我的世界/item_fragments.gd")
var _item_death_sent:bool=false
var _item_death_local:bool=false
func Die() -> void:
	if _item_death_sent: return
	_item_death_sent=true
	if is_multiplayer_authority():
		if multiplayer.has_multiplayer_peer(): _item_shatter.rpc()
		else: _item_shatter()
	super.Die()
@rpc("authority","call_local","reliable")
func _item_shatter() -> void:
	if _item_death_local: return
	_item_death_local=true
	ITEM_DEATH.spawn(self)
