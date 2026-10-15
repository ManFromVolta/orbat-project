extends SceneTree
## Снимки поз куклы сбоку для контактного листа. Нужен рендер (не --headless), например под xvfb:
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --resolution 420x520 -s tools/shot.gd -- /путь/для/png
## Камера ортографическая, смотрит вдоль +X: кукла идёт вправо по кадру.

const PHASES := [0, 3, 6, 9, 12, 15, 18, 21]
const SAMPLES := 24


func _initialize() -> void:
	_go()


func _go() -> void:
	var out_dir := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var m := (load("res://mannequin/mannequin.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(m)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.27, 0.25)
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.2
	root.add_child(cam)
	cam.look_at_from_position(Vector3(-5, 0.95, 0), Vector3(0, 0.95, 0), Vector3.UP)
	cam.current = true

	await process_frame
	(m.get_node("AnimationTree") as AnimationTree).active = false
	await process_frame
	var ap := m.get_node("AnimationPlayer") as AnimationPlayer

	for anim in ["idle", "walk", "run"]:
		var a := ap.get_animation(anim)
		var phases: Array = PHASES if anim != "idle" else [0]
		for k in phases:
			ap.play(anim)
			ap.seek(a.length * float(k) / SAMPLES, true)
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%02d.png" % [out_dir, anim, k])
	print("shots saved to ", out_dir)
	quit()
