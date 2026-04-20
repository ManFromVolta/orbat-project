extends Node

@export var assets_xml_path: String = "res://config/xml/assets.xml"
@export var units_xml_path: String = "res://config/xml/units.xml"
@export var red_unit_id: String = "unit.rifleman.red"
@export var blue_unit_id: String = "unit.rifleman.blue"
@export var units_per_team: int = 10
@export var red_anchor: Vector3 = Vector3(0.0, 0.9, -6.5)
@export var blue_anchor: Vector3 = Vector3(0.0, 0.9, 6.5)
@export var row_spacing: float = 1.7
@export_group("Spawn randomization")
## Случайный сдвиг по X и Z вокруг слота в строю (метры).
@export var spawn_jitter: float = 0.9
## Дополнительный разброс вдоль «глубины» строя (к своей/чужой стороне арены).
@export var spawn_depth_jitter: float = 1.1
## Перемешать порядок мест в линии, чтобы не всегда слева направо по индексу.
@export var shuffle_spawn_slots: bool = true


func _ready() -> void:
	add_to_group("arena_spawn_root")
	_load_and_spawn()


func _load_and_spawn() -> void:
	var assets := DemoXmlLoader.load_assets_xml(assets_xml_path)
	var units_map := DemoXmlLoader.load_units_xml(units_xml_path, assets)
	if units_map.is_empty():
		push_error("DemoArenaController: no units loaded from XML.")
		return

	var red_def: UnitDefinition = units_map.get(red_unit_id) as UnitDefinition
	var blue_def: UnitDefinition = units_map.get(blue_unit_id) as UnitDefinition
	if red_def == null or blue_def == null:
		push_error("DemoArenaController: missing unit id(s): %s / %s" % [red_unit_id, blue_unit_id])
		return
	if red_def.visual_scene.is_empty():
		push_error("DemoArenaController: red unit has no visual_scene (platform asset).")
		return
	if blue_def.visual_scene.is_empty():
		push_error("DemoArenaController: blue unit has no visual_scene (platform asset).")
		return

	_spawn_team(red_def, "red", red_anchor)
	_spawn_team(blue_def, "blue", blue_anchor)
	print("DemoArenaController: spawned %d vs %d units." % [units_per_team, units_per_team])


func _spawn_team(def: UnitDefinition, team_id: String, anchor: Vector3) -> void:
	var ps := load(def.visual_scene) as PackedScene
	if ps == null:
		push_error("DemoArenaController: failed to load unit scene: %s" % def.visual_scene)
		return

	var half_w := (units_per_team - 1) * 0.5 * row_spacing
	var xs: Array[float] = []
	for i in range(units_per_team):
		xs.append(-half_w + float(i) * row_spacing)
	if shuffle_spawn_slots:
		xs.shuffle()
	for i in range(units_per_team):
		var x: float = xs[i]
		var jitter := Vector3(
			randf_range(-spawn_jitter, spawn_jitter),
			0.0,
			randf_range(-spawn_depth_jitter, spawn_depth_jitter)
		)
		var pos := Vector3(anchor.x + x, anchor.y, anchor.z) + jitter
		var unit := ps.instantiate()
		add_child(unit)
		if unit.has_method("setup"):
			# Синхронно: к моменту спавна следующей стороны все юниты уже в группе demo_units.
			unit.call("setup", def, team_id, pos)
		else:
			push_error("DemoArenaController: unit scene has no setup(UnitDefinition, String, Vector3).")
