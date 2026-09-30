extends RefCounted
## Haochen task 10 (user: "它的复制的东西还是会攻击友军"): a guarded copy and
## everything it spawns (projectiles, summons, AOE, bleeds, family members) never hurt
## its side -- Haochen, his other copies, teammates of the same effective Team and
## their summons -- whether the global Have_Team_Damage setting is on or off.
## Members: Haochen (joins in _ready) and every copy whose shared copy profile carries
## `friendly_guard` (joins on every peer in 投稿角色工具.apply_character_copy_profile).
## The shared damage entries (hitbox contact, receive_positional_damage, spatial and
## internal status damage in ball.gd) ask ball.is_guarded_from_friendly_copy(source),
## which calls blocks(); with no member in the tree that is a single has_group() check.
## Duck-typed on purpose (no `ball` type) so ball.gd can load it without a cycle.

const GROUP:StringName = &"character_copy_friendly_guard"
const MAX_STEPS:int = 16
## Damage attempts stopped by blocks() (a copy's hit that reached its own side).
## Diagnostic only; tests read it to prove target selection never aims at allies.
static var blocked_count:int = 0

static func mark(unit:Node) -> void:
	if is_instance_valid(unit) and not unit.is_in_group(GROUP): unit.add_to_group(GROUP)

## True when `source` descends from a guard member and `target` is on that member's side.
static func blocks(target:Node,source:Variant) -> bool:
	if not side_of(target,source): return false
	blocked_count += 1
	return true

## Target selection entry: `seeker` (a guarded copy, or anything it launched or
## summoned) must never pick `candidate` as an enemy. Every custom enemy predicate
## (_is_enemy, _is_valid_enemy, mc_enemy ...) asks this before its own team rules,
## because those rules treat teammates as enemies when team damage is on.
static func skips_target(seeker:Variant,candidate:Variant) -> bool:
	return is_instance_valid(candidate) and candidate is Node and side_of(candidate as Node,seeker)

static func side_of(target:Node,source:Variant) -> bool:
	if not is_instance_valid(target) or not is_instance_valid(source) or not (source is Node) or not target.is_inside_tree(): return false
	if not target.get_tree().has_group(GROUP): return false
	var guard:Node = guard_in_chain(source as Node)
	if guard == null or guard == target: return false # a unit's own self-damage keeps its normal rules
	return is_on_side(target,guard)

## Nearest guard member reached by climbing the source's ownership chain.
static func guard_in_chain(source:Node) -> Node:
	var scene_root:Node = source.get_tree().current_scene if source.is_inside_tree() else null
	var current:Node = source
	var seen:Dictionary = {}
	for _i:int in range(MAX_STEPS):
		if current == null or current == scene_root: return null
		if current.is_in_group(GROUP): return current
		var id:int = current.get_instance_id()
		if seen.has(id): return null
		seen[id] = true
		# World family identity (world.bind_battle_lifecycle): partners/babies/backup
		# squads a copy spawns carry Haochen as their family root without a Master link.
		var family:Variant = current.get_meta(&"battle_lifecycle_identity",{})
		if family is Dictionary:
			var root:Object = instance_from_id(int((family as Dictionary).get("root",0))) if int((family as Dictionary).get("root",0)) != 0 else null
			if is_instance_valid(root) and root is Node and (root as Node).is_in_group(GROUP): return root as Node
		var next:Node = null
		var has_master:bool = "Master" in current
		if has_master:
			var master:Variant = current.get("Master")
			if is_instance_valid(master) and master is Node: next = master as Node
		if next == null and "Master_name" in current:
			var master_name:String = str(current.get("Master_name"))
			if not master_name.is_empty():
				for base:Node in [current.get_parent(),scene_root]:
					if next == null and is_instance_valid(base): next = base.get_node_or_null(NodePath(master_name))
		if next == null: next = declared_launcher(current)
		# Hitbox/Area children of a projectile or effect: climb to their holder.
		if next == null and not has_master and not ("Master_name" in current): next = current.get_parent()
		current = next
	return null

## Launcher links used by projectiles that deliberately keep Master empty: Area bolts
## (_src_ref), neutral MC ghast fireballs (launch_owner_id; a reflected fireball
## belongs to whoever reflected it) and bat cohorts.
static func declared_launcher(node:Node) -> Node:
	var ref:Variant = node.get("_src_ref")
	if ref is WeakRef:
		var shooter:Variant = (ref as WeakRef).get_ref()
		if is_instance_valid(shooter) and shooter is Node: return shooter as Node
	var launcher_id:Variant = node.get("launch_owner_id")
	if launcher_id is int and int(launcher_id) != 0 and not bool(node.get("reflected")):
		var launcher:Object = instance_from_id(int(launcher_id))
		if is_instance_valid(launcher) and launcher is Node: return launcher as Node
	var cohort:int = int(node.get_meta(&"mc_bat_cohort",0))
	if cohort != 0 and cohort != node.get_instance_id():
		var leader:Object = instance_from_id(cohort)
		if is_instance_valid(leader) and leader is Node: return leader as Node
	return null

## Haochen's side: same non-empty effective Team, or (free-for-all / no team) anything
## belonging to the same Haochen -- himself, his copies and their offspring.
static func is_on_side(target:Node,guard:Node) -> bool:
	var team:String = effective_team(guard)
	var target_guard:Node = target if target.is_in_group(GROUP) else guard_in_chain(target)
	if target_guard != null and guard_root(target_guard) == guard_root(guard): return true
	if team.is_empty(): return false
	if target_guard != null and effective_team(target_guard) == team: return true
	return effective_team(target) == team

## Stable per-peer identity of the Haochen a member belongs to (copies: Master_name).
static func guard_root(member:Node) -> String:
	var master_name:String = str(member.get("Master_name")) if "Master_name" in member else ""
	return master_name if not master_name.is_empty() else str(member.name)

## Same resolution as hitbox._effective_team: forced combat team first, then Team, and
## a Master's team for legacy summons still on the "Ball"/empty default.
static func effective_team(entity:Node) -> String:
	if not is_instance_valid(entity): return ""
	var forced:String = str(entity.get_meta(&"forced_combat_team","")).strip_edges()
	if not forced.is_empty() and forced != "Ball": return forced
	var team:String = str(entity.get("Team")).strip_edges() if "Team" in entity else ""
	if (team.is_empty() or team == "Ball") and "Master" in entity:
		var master:Variant = entity.get("Master")
		if is_instance_valid(master) and master is Node and master != entity: return effective_team(master as Node)
	return "" if team == "Ball" else team
