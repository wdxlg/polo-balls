extends Control
## 阵容席位保持匿名；独立候选转盘只作展示，最终落点来自 authority 已决定的结果。
const INK := Color("101619")
const PAPER := Color("e8eee5")
const MUTED := Color("8d9b99")
const XP := Color("80ff20")
const BOARD := Rect2(24,176,572,572)
const ROULETTE = preload("res://scripts/ui/random_character_roulette.gd")
const DRAFT_FX = preload("res://scripts/ui/random_character_draft_fx.gd")
const DRAFT_AUDIO = preload("res://scripts/ui/random_character_draft_audio.gd")
var _sound:Node
var _fx:Control
var _animated_slots:Array[int] = []
var _pulsing_teams:Array[int] = []
var _intro_age:float = 0.0
var _rest_position:Vector2
var _gain_age:float = 1.0
var _roulette:Control
var _roulette_pool:Array[Dictionary] = []
var _preview_factory:Callable
var _preview_cache:Dictionary = {}
# Unmodified Mojang PNGs; verified source and hashes live beside the assets.
const XP_BACKGROUND = preload("res://Images/UI/minecraft_xp/experience_bar_background.png")
const XP_PROGRESS = preload("res://Images/UI/minecraft_xp/experience_bar_progress.png")
const XP_ORIGIN := Vector2(37,796)
const XP_ROW_LIMIT:int = 45
var _xp_segments:Array[Rect2] = []
var _xp_rows:Array[Dictionary] = []
var revealed_count:int = 0
var total:int = 0
var revealed:bool = false
var _design:Control
var _counter:Label
var _roster:Control
var _slots:Array[Dictionary] = []
var _groups:Array[Dictionary] = []
var _active:int = -1
var _mode:String = "manual"
var _boss_team:String = "Team1"
var _factor:float = 1.0
var _clock:float = 0.0
var _flash:float = 0.0
var _last_tick:int = 0
var _xp_display:float = 0.0
const EXIT_SECONDS:float = 0.42
var _exit_started_at:int = -1
var _exit_duration:float = EXIT_SECONDS
var _exit_done:bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://ui/default.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_design = Control.new()
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.size = Vector2(620,830)
	add_child(_design)
	_roulette = ROULETTE.new()
	_roulette.position = Vector2(24,24)
	_roulette.size = Vector2(572,132)
	_design.add_child(_roulette)
	_counter = _label(_design,Rect2(24,758,572,32),23,XP)
	_counter.add_theme_color_override("font_shadow_color",Color.BLACK)
	_counter.add_theme_constant_override("shadow_offset_x",2)
	_counter.add_theme_constant_override("shadow_offset_y",2)
	_fx = DRAFT_FX.new()
	_fx.size = _design.size
	_design.add_child(_fx)
	_sound = DRAFT_AUDIO.new()
	add_child(_sound)
	_roulette.cell_passed.connect(_sound.play_tick)
	_fx.portrait_arrived.connect(_sound.play_arrival)
	_counter.pivot_offset = _counter.size*0.5
	_last_tick = Time.get_ticks_msec()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _copy(zh:String,en:String) -> String:
	return zh if Game.get_ui_locale().begins_with("zh") else en

func _label(parent:Control,rect:Rect2,font_size:int,color:Color) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func _layout() -> void:
	if not is_instance_valid(_design): return
	var viewport:Vector2 = get_viewport_rect().size
	_factor = maxf(0.01,minf(viewport.x/652.0,viewport.y/(_design.size.y+32.0)))
	_design.scale = Vector2.ONE*_factor
	_rest_position = (viewport-_design.size*_factor)*0.5
	_design.position = _rest_position
	if _exit_started_at>=0: _apply_exit_pose()
	queue_redraw()

func configure_roster(records:Array,mode:String,boss_team:String = "Team1",team_colors:Array = []) -> void:
	# Only slot identity and presentation team are retained here. Never cache hidden character names.
	if is_instance_valid(_roster):
		_design.remove_child(_roster)
		_roster.queue_free()
	_roster = Control.new()
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(_roster)
	_roulette.hide()
	_animated_slots.clear()
	_pulsing_teams.clear()
	_sound.reset_round()
	_exit_started_at = -1
	_exit_done = false
	modulate.a = 1.0
	_design.move_child(_fx,_design.get_child_count()-1)
	_slots.clear()
	_groups.clear()
	_active = -1
	revealed_count = 0
	revealed = false
	_xp_display = 0.0
	total = records.size()
	_mode = mode
	_boss_team = boss_team
	var teams:Array[String] = []
	for record:Dictionary in records:
		var team:String = str(record.get("display_team",record.get("team","")))
		if team not in teams: teams.append(team)
	if mode in ["rotation","boss"]:
		for team:String in ["Team0","Team1"]:
			if team not in teams: teams.append(team)
	teams.sort_custom(func(a:String,b:String): return a.naturalnocasecmp_to(b)<0)
	if mode == "boss" and boss_team in teams:
		teams.erase(boss_team)
		teams.push_front(boss_team)
	var content:Rect2 = BOARD.grow(-12)
	var columns:int = 1 if teams.size()<=1 or mode in ["rotation","boss"] else ceili(sqrt(float(teams.size())))
	var rows:int = maxi(1,ceili(float(teams.size())/columns))
	var group_gap:float = minf(10.0,content.size.x/columns*0.12)
	var cell:Vector2 = (content.size-Vector2(columns-1,rows-1)*group_gap)/Vector2(columns,rows)
	for group_index:int in range(teams.size()):
		var team:String = teams[group_index]
		var rect := Rect2(content.position+Vector2(group_index%columns,group_index/columns)* (cell+Vector2.ONE*group_gap),cell)
		var color := Color("a6b7ac")
		if not team.is_empty():
			var number:int = int(team.trim_prefix("Team")) if team.begins_with("Team") else group_index
			color = team_colors[number%team_colors.size()] if not team_colors.is_empty() else Color.from_hsv(fmod(number*0.19,1.0),0.55,0.95)
		var indices:Array[int] = []
		for index:int in range(records.size()):
			if str(records[index].get("display_team",records[index].get("team",""))) == team: indices.append(index)
		var title:String = Game.ui_t(team) if not team.is_empty() else Game.ui_t("UI_NONE")
		if mode == "boss": title = ("BOSS / " if team==boss_team else _copy("挑战方 / ","CHALLENGERS / "))+title
		elif mode == "rotation": title += _copy(" · 出场顺序"," / LINEUP")
		var padding:float = minf(8.0,minf(rect.size.x,rect.size.y)*0.06)
		var header_height:float = minf(32.0,rect.size.y*0.18) if rect.size.x>=80 and rect.size.y>=50 else 0.0
		var header:Label = _label(_roster,Rect2(rect.position+Vector2(padding,0),Vector2(rect.size.x-padding*2,header_height)),mini(17,maxi(7,int(header_height*0.65))),color)
		header.visible = header_height>0
		header.pivot_offset = header.size*0.5
		_groups.append({"rect":rect,"color":color,"indices":indices,"label":header,"title":title,"count":0,"pulse":1.0})
		var area := Rect2(rect.position+Vector2(padding,header_height+padding),rect.size-Vector2(padding*2,header_height+padding*2))
		var grid:Vector2i = _grid_shape(indices.size(),area.size)
		var gap:float = 5.0 if indices.size()<100 else 1.0
		var side:float = minf((area.size.x-gap*(grid.x-1))/grid.x,(area.size.y-gap*(grid.y-1))/grid.y)
		side = maxf(1.0,floorf(side))
		var origin:Vector2 = area.position+(area.size-(Vector2(grid)*side+Vector2(grid-Vector2i.ONE)*gap))*0.5
		for order:int in range(indices.size()):
			var index:int = indices[order]
			var at:Vector2 = origin+Vector2(order%grid.x,order/grid.x)*(side+gap)
			var card := Control.new()
			card.position = at
			card.size = Vector2.ONE*side
			card.pivot_offset = card.size*0.5
			card.clip_contents = true
			card.mouse_filter = Control.MOUSE_FILTER_PASS
			card.tooltip_text = title+" / %02d / ?" % [order+1]
			_roster.add_child(card)
			var question:Label = _label(card,Rect2(0,0,side,side*0.76),maxi(7,int(minf(64,side*0.42))),MUTED)
			question.text = "?"
			var name_label:Label = _label(card,Rect2(side*0.04,side*0.77,side*0.92,side*0.21),maxi(7,int(minf(17,side*0.14))),PAPER)
			name_label.text = _copy("待揭晓","UNREVEALED")
			name_label.visible = side>=38
			if side>=60:
				var number_label:Label = _label(card,Rect2(4,3,32,18),mini(13,int(side*0.13)),color)
				number_label.text = "%02d" % [order+1]
				number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			var slot:Dictionary = {"index":index,"id":records[index].get("id",index),"group":group_index,"rect":Rect2(at,Vector2.ONE*side),"card":card,"question":question,"name":name_label,"done":false,"portrait":null}
			_slots.append(slot)
	_slots.sort_custom(func(a:Dictionary,b:Dictionary): return int(a.index)<int(b.index))
	_rebuild_experience_bar()
	_update_counts()
	queue_redraw()

func _grid_shape(count:int,extent:Vector2) -> Vector2i:
	var best := Vector2i(1,maxi(count,1))
	var best_size:float = 0.0
	for columns:int in range(1,count+1):
		var rows:int = ceili(float(count)/columns)
		var gap:float = 5.0 if count<100 else 1.0
		var side:float = minf((extent.x-gap*(columns-1))/columns,(extent.y-gap*(rows-1))/rows)
		if side>best_size:
			best_size = side
			best = Vector2i(columns,rows)
	return best

func configure_roulette(candidates:Array,preview_factory:Callable) -> void:
	_preview_factory = preview_factory
	_preview_cache.clear()
	_roulette_pool.clear()
	# Bounded cosmetic sample from the entire eligible pool, not the hidden results list.
	# This does not call draft.rng or choose any battle identities.
	var count:int = mini(8,candidates.size())
	for index:int in range(count):
		var record:Dictionary = candidates[index*candidates.size()/count]
		_roulette_pool.append(_roulette_entry(record))

func _roulette_entry(record:Dictionary) -> Dictionary:
	var key:String = str(record.get("scene_path",record.get("char","")))
	if not _preview_cache.has(key):
		var preview:Node2D = null
		if _preview_factory.is_valid():
			preview = _preview_factory.call(str(record.get("char","")),str(record.get("scene_path","")),false)
		if _preview_cache.size()>=32: _preview_cache.erase(_preview_cache.keys()[0])
		_preview_cache[key] = _texture_from_preview(preview)
		if is_instance_valid(preview): preview.queue_free()
	return {"name":Game.ui_t(str(record.get("char","?"))),"texture":_preview_cache[key]}

func _texture_from_preview(portrait:Node2D) -> Texture2D:
	if not is_instance_valid(portrait): return null
	var image:Node2D = portrait.get_node_or_null("PreviewImage") as Node2D
	var texture:Texture2D = null
	if image is Sprite2D:
		var sprite := image as Sprite2D
		texture = sprite.texture
		if texture != null and (sprite.region_enabled or sprite.hframes>1 or sprite.vframes>1):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			var frame_size:Vector2 = (sprite.region_rect.size if sprite.region_enabled else texture.get_size())/Vector2(sprite.hframes,sprite.vframes)
			var start:Vector2 = sprite.region_rect.position if sprite.region_enabled else Vector2.ZERO
			atlas.region = Rect2(start+Vector2(sprite.frame_coords)*frame_size,frame_size)
			texture = atlas
	elif image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		if animated.sprite_frames != null and animated.sprite_frames.get_frame_count(animated.animation)>0:
			texture = animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
	return texture

func begin_ticket(index:int,count:int,record:Dictionary,_candidates:Array[String],roll_seconds:float = 0.6) -> void:
	# The roster stays anonymous; only the separate cosmetic reel shows eligible candidates.
	total = count
	_active = index
	revealed = false
	_sound.begin_ticket()
	_roulette.start_roll(_roulette_pool,_roulette_entry(record),roll_seconds,index)
	queue_redraw()

func reveal_ticket(record:Dictionary,portrait:Node2D = null) -> void:
	if _active<0 or _active>=_slots.size() or bool(_slots[_active].done):
		if is_instance_valid(portrait): portrait.queue_free()
		return
	var slot:Dictionary = _slots[_active]
	revealed = true
	revealed_count += 1
	slot.done = true
	_groups[int(slot.group)].count += 1
	_flash = 1.0
	var character_name:String = Game.ui_t(str(record.get("char","")))
	slot.name.text = character_name
	slot.card.tooltip_text = character_name+" / "+Game.ui_t(str(record.get("category","")))+" / "+str(_groups[int(slot.group)].title)
	# A cold/missing preview still reveals identity, rather than leaving a misleading '?'.
	slot.question.text = character_name.left(1)
	slot.question.add_theme_color_override("font_color",PAPER)
	var texture:Texture2D = _texture_from_preview(portrait)
	if texture==null: texture = _preview_cache.get(str(record.get("scene_path",record.get("char",""))))
	_sound.play_confirmation()
	_roulette.confirm_result(character_name,texture)
	_start_reveal_animation(slot,texture)
	if texture != null:
		# Static texture cards keep all portraits without retaining 1024 live preview subtrees.
		var thumb := TextureRect.new()
		thumb.texture = texture
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side:float = slot.rect.size.x
		thumb.position = Vector2.ONE*side*0.09
		thumb.size = Vector2(side*0.82,side*0.65)
		slot.card.add_child(thumb)
		slot.portrait = thumb
		slot.question.hide()
	if is_instance_valid(portrait): portrait.queue_free()
	_update_counts()
	queue_redraw()

func _start_reveal_animation(slot:Dictionary,texture:Texture2D) -> void:
	if _animated_slots.size()>=24:
		var old_slot:Dictionary = _slots[_animated_slots.pop_front()]
		old_slot.card.scale = Vector2.ONE
		old_slot.card.modulate.a = 1.0
	slot["reveal_age"] = 0.0
	slot.card.modulate.a = 0.0
	slot.card.scale = Vector2(0.08,1.03)
	_animated_slots.append(int(slot.index))
	var group_index:int = slot.group
	_groups[group_index].pulse = 0.0
	if group_index not in _pulsing_teams: _pulsing_teams.append(group_index)
	var color:Color = _groups[group_index].color
	var rect:Rect2 = slot.rect
	var destination:Vector2 = rect.position+Vector2(rect.size.x*0.5,rect.size.y*0.42)
	_fx.launch_result(texture,_roulette.position+_roulette.size*0.5,destination,color,rect.size.x*0.65)
	_fx.ripple(rect,color)
	_gain_age = 0.0
	var row_index:int = (revealed_count-1)/XP_ROW_LIMIT
	if row_index>=0 and row_index<_xp_rows.size():
		var row:Dictionary = _xp_rows[row_index]
		var pixel:float = _experience_pixel_scale()
		var body:Rect2i = row.bodies[revealed_count-1-int(row.first)]
		var origin := Vector2((size.x-182*pixel)*0.5,_design.position.y+row.origin.y*_factor)
		var screen_point:Vector2 = origin+Vector2(body.end.x,0)*pixel
		_fx.experience_gain((screen_point-_design.position)/maxf(_factor,0.01))

func _advance_reveal_animations(delta:float) -> void:
	_gain_age = minf(1.0,_gain_age+delta)
	var counter_pop:float = sin(clampf(_gain_age/0.32,0,1)*PI)*0.10
	_counter.scale = Vector2.ONE*(1+counter_pop)
	for index:int in range(_animated_slots.size()-1,-1,-1):
		var slot:Dictionary = _slots[_animated_slots[index]]
		slot.reveal_age += delta
		var age:float = slot.reveal_age
		var turn:float = clampf((age-0.19)/0.25,0,1)
		var opened:float = 1-pow(1-turn,3.0)
		slot.card.modulate.a = clampf((age-0.19)/0.07,0,1)
		slot.card.scale = Vector2(lerpf(0.08,1.0,opened),1.0+sin(turn*PI)*0.035)
		if age>=0.5:
			slot.card.scale = Vector2.ONE
			slot.card.modulate.a = 1.0
			_animated_slots.remove_at(index)
	for index:int in range(_pulsing_teams.size()-1,-1,-1):
		var group:Dictionary = _groups[_pulsing_teams[index]]
		group.pulse += delta
		group.label.scale = Vector2.ONE*(1+sin(clampf(float(group.pulse)/0.36,0,1)*PI)*0.055)
		if float(group.pulse)>=0.36:
			group.label.scale = Vector2.ONE
			_pulsing_teams.remove_at(index)

func _finish_reveal_animations() -> void:
	for index:int in _animated_slots:
		_slots[index].card.scale = Vector2.ONE
		_slots[index].card.modulate.a = 1.0
	_animated_slots.clear()
	for index:int in _pulsing_teams: _groups[index].label.scale = Vector2.ONE
	_pulsing_teams.clear()
	_counter.scale = Vector2.ONE

func _update_counts() -> void:
	_counter.text = "%d / %d" % [revealed_count,total]
	_xp_display = float(revealed_count)/maxi(total,1)
	for group:Dictionary in _groups:
		group.label.text = str(group.title)+"  %d/%d" % [int(group.count),group.indices.size()]

func show_finishing() -> void:
	_sound.stop_ticks()

func show_complete() -> void:
	_finish_reveal_animations()
	_fx.finish()
	_fx.ripple(BOARD,Color("a5d97a"))
	_sound.play_complete()
	_xp_display = float(revealed_count)/maxi(total,1)
	_flash = 1.0
	queue_redraw()

func completion_sound_seconds() -> float:
	return _sound.completion_duration()

func begin_exit(seconds:float = EXIT_SECONDS) -> void:
	# Owned, wall-clock transition: no detached Tween/coroutine survives cancel.
	if _exit_started_at>=0: return
	_finish_reveal_animations()
	_fx.finish()
	_sound.stop_ticks()
	_intro_age = 1.0
	_design.modulate.a = 1.0
	_exit_duration = maxf(seconds,0.0)
	_exit_started_at = Time.get_ticks_msec()
	_apply_exit_pose()
	queue_redraw()

func is_exit_finished() -> bool:
	return _exit_done

func _apply_exit_pose() -> void:
	var progress:float = 1.0 if _exit_duration<=0.0 else clampf(float(Time.get_ticks_msec()-_exit_started_at)/(1000.0*_exit_duration),0.0,1.0)
	var eased:float = progress*progress*(3.0-2.0*progress)
	var shrink:float = 1.0-0.025*eased
	modulate.a = 1.0-eased
	_design.scale = Vector2.ONE*(_factor*shrink)
	_design.position = _rest_position+_design.size*_factor*(1.0-shrink)*0.5+Vector2(0,18.0*_factor*eased)
	_exit_done = progress>=1.0

func _process(_delta:float) -> void:
	var tick:int = Time.get_ticks_msec()
	var elapsed:float = clampf(float(tick-_last_tick)/1000.0,0.0,0.1)
	_last_tick = tick
	_clock += elapsed
	_flash = maxf(0.0,_flash-elapsed*2.5)
	if _exit_started_at>=0:
		_apply_exit_pose()
	else:
		_intro_age = minf(1.0,_intro_age+elapsed)
		var intro:float = 1.0-pow(1.0-clampf(_intro_age/0.25,0,1),3.0)
		_design.position = _rest_position+Vector2(0,14*(1-intro))
		_design.modulate.a = intro
	_advance_reveal_animations(elapsed)
	_fx.advance(elapsed)
	queue_redraw()

func _draw() -> void:
	# Opaque backdrop: do not let underlying battle HUD text bleed through the clean UI.
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	# Small, deterministic ambient motes; never touch the battle random stream.
	for index:int in range(20):
		var x:float = fmod(index*173.0+47,maxf(size.x,1))
		var y:float = fposmod(index*239.0-_clock*(5+index%3),maxf(size.y,1))
		draw_rect(Rect2(x,y,2,2),Color(0.45,0.67,0.52,0.08+0.04*sin(_clock+index)))
	if not is_instance_valid(_design): return
	draw_set_transform(_design.position,0,_design.scale)
	for halo:int in range(3,0,-1):
		draw_rect(BOARD.grow(5+halo*4),Color(0.42,0.65,0.48,0.02+_flash*0.012),false,3)
	draw_rect(BOARD.grow(5),Color("070a09"))
	draw_rect(BOARD,Color("27312d"))
	draw_rect(BOARD,Color("69786b"),false,2)
	draw_line(BOARD.position,Vector2(BOARD.end.x,BOARD.position.y),Color("9bab94"),3)
	for group:Dictionary in _groups:
		var rect:Rect2 = group.rect
		var color:Color = group.color
		draw_rect(rect,Color("171f20"))
		draw_rect(rect,Color(color,0.28),false,1)
		draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),color)
		if _mode=="boss" and str(group.title).begins_with("BOSS"):
			draw_rect(rect.grow(1),Color("dfb761"),false,2)
	for slot:Dictionary in _slots:
		var rect:Rect2 = slot.rect
		var color:Color = _groups[int(slot.group)].color
		var active:bool = int(slot.index)==_active
		var done:bool = slot.done
		draw_rect(rect,Color("303c36") if done else Color("101719"))
		draw_rect(rect.grow(-1),Color(color,0.6 if done else 0.16),false,1)
		if done: draw_rect(Rect2(rect.position+Vector2(1,rect.size.y-3),Vector2(rect.size.x-2,2)),color)
		if active:
			draw_rect(rect.grow(2),Color(PAPER,0.8 if done else 0.55+0.25*sin(_clock*6)),false,2)
			if _flash>0: draw_rect(rect,Color(color,_flash*0.18))
	_draw_experience_bar()

func _rebuild_experience_bar() -> void:
	_xp_segments.clear()
	_xp_rows.clear()
	for first:int in range(0,total,XP_ROW_LIMIT):
		var count:int = mini(XP_ROW_LIMIT,total-first)
		var origin:Vector2 = XP_ORIGIN+Vector2(0,_xp_rows.size()*21)
		var bodies:Array[Rect2i] = []
		var cursor:int = 1
		var available:int = 180-(count-1)
		for index:int in range(count):
			var width:int = (index+1)*available/count-index*available/count
			bodies.append(Rect2i(cursor,0,width,5))
			_xp_segments.append(Rect2(origin+Vector2(cursor*3,0),Vector2(width*3,15)))
			cursor += width+1
		_xp_rows.append({"first":first,"count":count,"origin":origin,"bodies":bodies,
			"empty":_compose_experience_row(XP_BACKGROUND,bodies,first),
			"full":_compose_experience_row(XP_PROGRESS,bodies,first)})
	var extra_height:float = maxi(0,_xp_rows.size()-1)*21.0
	_design.size.y = 830+extra_height
	_fx.size = _design.size
	_layout()

func _compose_experience_row(texture:Texture2D,bodies:Array[Rect2i],first:int) -> ImageTexture:
	var source:Image = texture.get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var image := Image.create(182,5,false,Image.FORMAT_RGBA8)
	image.blit_rect(source,Rect2i(0,0,1,5),Vector2i.ZERO)
	image.blit_rect(source,Rect2i(181,0,1,5),Vector2i(181,0))
	for index:int in range(bodies.size()):
		var body:Rect2i = bodies[index]
		# Copy 1:1 columns; wider segments TILE original pixels, never stretch them.
		for x:int in range(body.size.x):
			var source_x:int = 1+((first+index)%18)*10+x%9
			image.blit_rect(source,Rect2i(source_x,0,1,5),Vector2i(body.position.x+x,0))
		if index<bodies.size()-1:
			image.blit_rect(source,Rect2i(10,0,1,5),Vector2i(body.end.x,0))
	return ImageTexture.create_from_image(image)

func _experience_filled_segments() -> int:
	return clampi(revealed_count,0,total)

func _experience_pixel_scale() -> float:
	# canvas_items stretches the logical viewport to the real window. Snap at the
	# physical-pixel level, rather than applying the roster's fractional design scale.
	var window_ratio:float = float(get_window().size.x)/maxf(get_viewport_rect().size.x,1.0)
	var physical_pixel:int = maxi(1,int(floorf(3.0*_factor*window_ratio)))
	return float(physical_pixel)/maxf(window_ratio,0.001)

func _draw_experience_bar() -> void:
	var filled:int = _experience_filled_segments()
	var pixel:float = _experience_pixel_scale()
	var window_ratio:float = float(get_window().size.x)/maxf(get_viewport_rect().size.x,1.0)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	for row:Dictionary in _xp_rows:
		var origin := Vector2((size.x-182*pixel)*0.5,_design.position.y+row.origin.y*_factor)
		origin = (origin*window_ratio).round()/maxf(window_ratio,0.001)
		draw_texture_rect(row.empty,Rect2(origin,Vector2(182,5)*pixel),false)
		var row_filled:int = clampi(filled-int(row.first),0,int(row.count))
		if row_filled<=0: continue
		var width:int = 182 if row_filled==int(row.count) else int(row.bodies[row_filled-1].end.x)
		draw_texture_rect_region(row.full,Rect2(origin,Vector2(width,5)*pixel),Rect2(0,0,width,5))
		# Brief light on the newly filled segment only; native geometry never scales or stretches.
		if _gain_age<0.22 and filled<=int(row.first)+int(row.count):
			var body:Rect2i = row.bodies[row_filled-1]
			var highlight := Rect2(origin+Vector2(body.position)*pixel,Vector2(body.size)*pixel)
			draw_rect(highlight,Color(0.8,1.0,0.5,(1.0-_gain_age/0.22)*0.3))
