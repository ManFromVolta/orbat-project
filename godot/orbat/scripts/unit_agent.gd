extends CharacterBody3D

var definition: UnitDefinition
var team: String = ""
var spawn_position: Vector3 = Vector3.ZERO

var _alive: bool = true
var _respawn_remaining: float = 0.0
var _fire_cd: float = 0.0
var _nav_map_rid: RID

@onready var _nav: NavigationAgent3D = $NavigationAgent3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D


func setup(unit_def: UnitDefinition, team_id: String, pos: Vector3) -> void:
	definition = unit_def
	team = team_id
	spawn_position = pos
	global_position = pos
	add_to_group("demo_units")
	_apply_team_color()
	_nav.max_speed = definition.move_speed
	call_deferred("_snap_position_to_navmesh")


func is_unit_alive() -> bool:
	return _alive


func apply_hit_from_projectile(_proj: Node, shooter_team: String) -> bool:
	if not _alive:
		return false
	if shooter_team.is_empty() or shooter_team == team:
		return false
	_die()
	return true


func _physics_process(delta: float) -> void:
	if definition == null:
		return
	if not _alive:
		_respawn_remaining -= delta
		if _respawn_remaining <= 0.0:
			_respawn()
		return

	_fire_cd = maxf(0.0, _fire_cd - delta)
	var target := _find_nearest_enemy()
	if target == null:
		velocity = Vector3.ZERO
		move_and_slide()
		_clamp_position_to_navmesh(delta)
		return

	var dist := _horizontal_distance(global_position, target.global_position)
	_nav.target_position = target.global_position

	# attack_range в XML — дистанция «встать и вести огонь»; weapon_range — макс. дальность выстрела.
	# Если attack_range >= стартового разрыва между командами, юниты никогда не идут — только стоят и стреляют.
	var halt_range: float = definition.attack_range
	var max_fire: float = definition.weapon_range if definition.weapon_range > 0.0 else halt_range

	if dist <= halt_range:
		velocity = Vector3.ZERO
		move_and_slide()
		_clamp_position_to_navmesh(delta)
		_face_toward(target.global_position)
		if dist <= max_fire:
			_try_fire(target)
		return

	var next_pos := _nav.get_next_path_position()
	var to_next := next_pos - global_position
	to_next.y = 0.0
	var to_enemy_h := target.global_position - global_position
	to_enemy_h.y = 0.0
	var dir_horiz := Vector3.ZERO
	if to_next.length() > 0.1:
		dir_horiz = to_next.normalized()
	elif to_enemy_h.length() > 0.05:
		dir_horiz = to_enemy_h.normalized()
	velocity = dir_horiz * definition.move_speed
	move_and_slide()
	_clamp_position_to_navmesh(delta)
	_face_toward(target.global_position)


func _find_nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("demo_units"):
		if n == self:
			continue
		var other: Node = n as Node
		if other == null:
			continue
		if other.has_method("is_unit_alive") and not other.is_unit_alive():
			continue
		if other.has_method("get_team") and str(other.get_team()) == team:
			continue
		var node3d := n as Node3D
		if node3d == null:
			continue
		var d := _horizontal_distance(global_position, node3d.global_position)
		if d < best_d and d <= definition.aggro_range:
			best_d = d
			best = node3d
	return best


func get_team() -> String:
	return team


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var aa := a
	var bb := b
	aa.y = 0.0
	bb.y = 0.0
	return aa.distance_to(bb)


func _try_fire(target: Node3D) -> void:
	if definition.fire_rate <= 0.0:
		return
	var interval := 1.0 / definition.fire_rate
	if _fire_cd > 0.0:
		return
	var scene_path := definition.weapon_projectile_scene
	if scene_path.is_empty():
		return
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("UnitAgent: cannot load projectile scene: %s" % scene_path)
		return
	var proj := ps.instantiate() as Node3D
	if proj == null:
		return
	var root := get_tree().get_first_node_in_group("arena_spawn_root")
	if root == null:
		root = get_parent()
	root.add_child(proj)

	var muzzle_y := 0.85
	var to_target := target.global_position + Vector3(0.0, 0.6, 0.0) - (global_position + Vector3(0.0, muzzle_y, 0.0))
	to_target.y = 0.0
	if to_target.length_squared() < 1e-6:
		to_target = -global_basis.z
		to_target.y = 0.0
	var dir := to_target.normalized()
	# Вынести точку вылета из капсулы стрелка, иначе Area3D сразу получает body_entered(self).
	var origin := global_position + Vector3(0.0, muzzle_y, 0.0) + dir * 1.05
	if proj.has_method("setup"):
		proj.call("setup", origin, dir, definition.projectile_speed, team, self)
	else:
		proj.global_position = origin
	_fire_cd = interval


func _face_toward(world_point: Vector3) -> void:
	var p := world_point
	p.y = global_position.y
	var from := global_position
	var flat := p - from
	flat.y = 0.0
	if flat.length_squared() < 1e-6:
		return
	look_at(from + flat.normalized(), Vector3.UP)


func _die() -> void:
	_alive = false
	collision_layer = 0
	visible = false
	_respawn_remaining = definition.respawn_sec
	velocity = Vector3.ZERO
	_nav.target_position = global_position


func _respawn() -> void:
	_alive = true
	global_position = spawn_position
	collision_layer = 2
	visible = true
	_fire_cd = 0.0
	call_deferred("_snap_position_to_navmesh")


func _find_arena_root() -> Node:
	var p: Node = get_parent()
	while p != null and str(p.name) != "Arena":
		p = p.get_parent()
	return p


func _get_nav_map_rid() -> RID:
	if _nav_map_rid.is_valid():
		return _nav_map_rid
	var arena := _find_arena_root()
	if arena == null:
		return RID()
	var nr := arena.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if nr == null:
		return RID()
	_nav_map_rid = nr.get_navigation_map()
	return _nav_map_rid


## Полная подстановка closest каждый кадр тянет всех к одной кромке сетки / шумит одинаково.
## У «нормального» положения сохраняем XZ, правим только высоту; если явно ушли с меша — догоняем к своей closest.
func _clamp_position_to_navmesh(delta: float) -> void:
	var map_rid := _get_nav_map_rid()
	if not map_rid.is_valid():
		return
	var p := global_position
	# Редкий кадр: позиция ещё 0 — запрос даёт одну общую точку для всех.
	if p.length_squared() < 1e-6 and spawn_position.length_squared() > 1e-6:
		p = spawn_position
	var closest := NavigationServer3D.map_get_closest_point(map_rid, p)
	var dist := p.distance_to(closest)
	const ON_MESH_TOL := 0.35
	if dist < ON_MESH_TOL:
		global_position = Vector3(p.x, closest.y, p.z)
	else:
		var max_step: float = maxf(4.0 * delta, 0.15)
		global_position = p.move_toward(closest, max_step)


func _snap_position_to_navmesh() -> void:
	# Нельзя брать global_position: в call_deferred он иногда ещё (0,0,0) — тогда
	# map_get_closest_point даёт одну точку у центра для всех юнитов.
	var map_rid := _get_nav_map_rid()
	if not map_rid.is_valid():
		return
	var closest := NavigationServer3D.map_get_closest_point(map_rid, spawn_position)
	# Сохраняем строй спавна по XZ, поджимаем только высоту к поверхности сетки.
	global_position = Vector3(spawn_position.x, closest.y, spawn_position.z)


func _apply_team_color() -> void:
	var mat := StandardMaterial3D.new()
	if team == "red":
		mat.albedo_color = Color(0.85, 0.2, 0.15)
	elif team == "blue":
		mat.albedo_color = Color(0.2, 0.35, 0.9)
	else:
		mat.albedo_color = Color(0.7, 0.7, 0.65)
	_mesh.material_override = mat
