extends CanvasLayer
## Shared presentation-only compositor; never modifies the battle camera or world coordinates.
var rect:ColorRect
var shader_material:ShaderMaterial
var summon_left:float=0.0
var summon_duration:float=3.0
var shake_left:float=0.0
var shake_clock:float=0.0
var shake_offset:Vector2=Vector2.ZERO
var _shake_source:WeakRef
var inversion_left:float=0.0
var _summon_source:WeakRef
var _invert_source:WeakRef
var _charge_source:WeakRef
var _summon_origin:Vector2
var _invert_gap:float=0.0
var charge_elapsed:float=0.0
var release_left:float=0.0
var release_amount:float=0.0
var zoom_amount:float=0.0
var focus:Vector2=Vector2(0.5,0.5)
static func ensure(actor:Node) -> Node:
	var world:Node=actor.get_tree().current_scene
	var existing:Node=world.get_node_or_null("MCWardenScreenFX")
	if existing!=null: return existing
	var result:Node=load("res://scripts/characters/我的世界/frontier/warden_screen.gd").new()
	result.name="MCWardenScreenFX"
	world.add_child(result)
	return result
func _ready() -> void:
	layer=120
	add_to_group("BattleTransient")
	rect=ColorRect.new(); rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(rect); rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader:=Shader.new()
	shader.code="""shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform float inversion=0.0;
uniform float darkness=0.0;
uniform float view_zoom=1.0;
uniform vec2 focus=vec2(0.5);
uniform vec2 shake_uv=vec2(0.0);
uniform vec2 ring_center=vec2(0.5);
uniform vec2 viewport_size=vec2(1280.0,720.0);
uniform float ring_radius=0.0;
uniform float ring_alpha=0.0;
void fragment(){
 vec2 uv=focus+(SCREEN_UV-focus)/view_zoom+shake_uv;
 vec3 base=texture(screen_texture,clamp(uv,vec2(0.0),vec2(1.0))).rgb;
 vec3 color=mix(base,vec3(1.0)-base,inversion)*(1.0-darkness);
 float d=length((SCREEN_UV-ring_center)*viewport_size);
 float band=1.0-smoothstep(6.0,20.0,abs(d-ring_radius));
 color=mix(color,vec3(0.03,0.40,0.95),band*ring_alpha);
 COLOR=vec4(color,1.0);
}"""
	shader_material=ShaderMaterial.new(); shader_material.shader=shader
	rect.material=shader_material; rect.hide()
func trigger(actor:Node,kind:String) -> void:
	if kind=="summon_screen":
		if summon_left<=0.0:
			summon_duration=actor.emerge_duration; summon_left=summon_duration; _summon_source=weakref(actor); _summon_origin=actor.global_position
	elif kind=="sonic_charge_screen":
		if not source_live(_charge_source) or zoom_amount<=0.0:
			_charge_source=weakref(actor); charge_elapsed=0.0; release_left=0.0
	elif kind=="sonic_screen":
		shake_left=0.32; _shake_source=weakref(actor)
		if _invert_gap<=0.0:
			inversion_left=0.10; _invert_gap=0.45; _invert_source=weakref(actor)
		if _charge_source!=null and _charge_source.get_ref()==actor:
			release_amount=zoom_amount; release_left=0.6
func source_live(ref:WeakRef) -> bool:
	var actor:Variant=ref.get_ref() if ref!=null else null
	return is_instance_valid(actor) and actor.health>0 and not actor.is_queued_for_deletion() and actor.is_combat_runtime_active()
func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused:
		rect.hide()
		return
	if not source_live(_summon_source): summon_left=0.0
	if not source_live(_invert_source): inversion_left=0.0
	if not source_live(_charge_source): zoom_amount=0.0; release_left=0.0; _charge_source=null
	_update_zoom(delta)
	_update_shake(delta)
	_summon_step(delta)
func _update_zoom(delta:float) -> void:
	if _charge_source==null: return
	var actor:Node2D=_charge_source.get_ref()
	var size:Vector2=get_viewport().get_visible_rect().size
	var position_uv:Vector2=actor.get_global_transform_with_canvas().origin/size
	focus=Vector2(0.5,0.5).lerp(position_uv.clamp(Vector2.ZERO,Vector2.ONE),0.65)
	if release_left>0.0:
		release_left=maxf(0.0,release_left-delta)
		var elapsed:float=0.6-release_left
		zoom_amount=release_amount*exp(-7.0*elapsed)*cos(14.0*elapsed)
		if release_left<=0.0: zoom_amount=0.0; _charge_source=null
	elif actor.sonic_left>0.0:
		charge_elapsed+=delta
		var p:float=clampf(charge_elapsed/maxf(actor.sonic_windup,0.01),0,1)
		zoom_amount=0.07*(p*p*(3.0-2.0*p))
	else:
		release_amount=zoom_amount; release_left=0.6
func _update_shake(delta:float) -> void:
	shake_clock+=delta
	if not source_live(_shake_source): shake_left=0.0
	shake_left=maxf(0.0,shake_left-delta)
	var strength:float=0.0
	if shake_left>0.0: strength=14.0*pow(shake_left/0.32,0.7)
	elif source_live(_charge_source):
		var caster:Node2D=_charge_source.get_ref()
		if caster.sonic_left>0.0 and release_left<=0.0: strength=0.6+0.8*clampf(charge_elapsed/maxf(caster.sonic_windup,0.01),0,1)
	shake_offset=Vector2(sin(shake_clock*113.0)+sin(shake_clock*71.0)*0.3,cos(shake_clock*97.0)+sin(shake_clock*137.0)*0.3)*strength/1.3
func _summon_step(delta:float) -> void:
	summon_left=maxf(0.0,summon_left-delta)
	inversion_left=maxf(0.0,inversion_left-delta)
	_invert_gap=maxf(0.0,_invert_gap-delta)
	var darkness:float=0.0
	var ring_alpha:float=0.0
	var radius:float=0.0
	var size:Vector2=get_viewport().get_visible_rect().size
	if summon_left>0.0:
		var elapsed:float=summon_duration-summon_left
		if elapsed<0.14: darkness=0.55*elapsed/0.14
		elif elapsed<0.35: darkness=lerpf(0.55,0.18,(elapsed-0.14)/0.21)
		else: darkness=(0.18+0.12*(0.5+0.5*sin((elapsed-0.35)*TAU*2.0)))*clampf(summon_left/0.18,0,1)
		if elapsed<0.48:
			var actor:Node2D=_summon_source.get_ref()
			var center:Vector2=(actor.get_canvas_transform()*_summon_origin)/size
			shader_material.set_shader_parameter("ring_center",center)
			var p:float=clampf(elapsed/0.48,0,1)
			radius=size.length()*1.25*(1.0-pow(1.0-p,2.0))
			ring_alpha=0.9*(1.0-p)
	var invert:float=1.0 if inversion_left>0.0 else 0.0
	shader_material.set_shader_parameter("inversion",invert)
	shader_material.set_shader_parameter("darkness",darkness)
	shader_material.set_shader_parameter("viewport_size",size)
	shader_material.set_shader_parameter("ring_radius",radius)
	shader_material.set_shader_parameter("ring_alpha",ring_alpha)
	shader_material.set_shader_parameter("view_zoom",1.0+zoom_amount)
	shader_material.set_shader_parameter("focus",focus)
	shader_material.set_shader_parameter("shake_uv",shake_offset/size)
	rect.visible=darkness>0.0 or invert>0.0 or absf(zoom_amount)>0.00001 or ring_alpha>0.0 or shake_offset.length_squared()>0.00001
