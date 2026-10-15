extends RefCounted
## Генератор player.tscn и scenes/test_arena.tscn.

const PLAYER_OUT := "res://player/player.tscn"
const ARENA_OUT := "res://scenes/test_arena.tscn"


static func build() -> void:
	_build_player()
	_build_arena()


static func _own(root: Node, node: Node) -> void:
	node.owner = root
	for c in node.get_children():
		_own(root, c)


static func _build_player() -> void:
	var root := CharacterBody3D.new()
	root.name = "Player"
	root.set_script(load("res://player/player.gd"))

	var col := CollisionShape3D.new()
	col.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	root.add_child(col)

	var model := Node3D.new()
	model.name = "Model"
	model.rotation.y = PI  # на старте смотрит в -Z, от камеры (камера стоит за спиной на +Z)
	root.add_child(model)

	# Камера через плечо: Yaw (мышь по горизонтали) → Pitch (по вертикали) → Shoulder (смещение вправо) → SpringArm → Camera.
	var yaw := Node3D.new()
	yaw.name = "CameraYaw"
	yaw.position = Vector3(0, 1.55, 0)
	root.add_child(yaw)
	var pitch := Node3D.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)
	var shoulder := Node3D.new()
	shoulder.name = "Shoulder"
	shoulder.position = Vector3(0.5, 0, 0)
	pitch.add_child(shoulder)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 2.4
	arm.margin = 0.2
	var s := SphereShape3D.new()
	s.radius = 0.15
	arm.shape = s
	shoulder.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 65.0
	arm.add_child(cam)

	_own(root, col)
	_own(root, model)
	_own(root, yaw)

	var mannequin := (load("res://mannequin/mannequin.tscn") as PackedScene).instantiate()
	model.add_child(mannequin)
	mannequin.owner = root  # только корень экземпляра: сцена куклы остаётся ссылкой

	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, PLAYER_OUT) == OK)
	print("world: saved ", PLAYER_OUT)
	root.free()


static func _build_arena() -> void:
	var root := Node3D.new()
	root.name = "TestArena"

	# Земля с шахматкой 1x1 м: по ней видно масштаб и скольжение стоп.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(80, 1, 80)
	gcol.shape = gshape
	gcol.position = Vector3(0, -0.5, 0)
	ground.add_child(gcol)
	var gmesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	gmesh.mesh = plane
	var shader := Shader.new()
	shader.code = """shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(wp.xz);
	float k = mod(c.x + c.y, 2.0);
	ALBEDO = mix(vec3(0.27, 0.29, 0.26), vec3(0.36, 0.38, 0.34), k);
	ROUGHNESS = 1.0;
}
"""
	var gmat := ShaderMaterial.new()
	gmat.shader = shader
	gmesh.material_override = gmat
	ground.add_child(gmesh)
	root.add_child(ground)

	# Препятствия для масштаба и проверки камеры.
	var obstacles := [
		["Crate1", Vector3(1, 1, 1), Vector3(3, 0.5, -3)],
		["Crate2", Vector3(1.5, 1.5, 1.5), Vector3(6, 0.75, 2)],
		["Crate3", Vector3(1, 1, 1), Vector3(-4, 0.5, -5)],
		["Wall", Vector3(6, 2, 0.3), Vector3(0, 1, -14)],
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.38, 0.28)
	mat.roughness = 0.9
	for o in obstacles:
		var body := StaticBody3D.new()
		body.name = o[0]
		body.position = o[2]
		var c := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = o[1]
		c.shape = sh
		body.add_child(c)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = o[1]
		m.mesh = bm
		m.material_override = mat
		body.add_child(m)
		root.add_child(body)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = env
	root.add_child(we)

	for c in root.get_children():
		_own(root, c)

	var player := (load(PLAYER_OUT) as PackedScene).instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 0)
	root.add_child(player)
	player.owner = root

	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, ARENA_OUT) == OK)
	print("world: saved ", ARENA_OUT)
	root.free()
