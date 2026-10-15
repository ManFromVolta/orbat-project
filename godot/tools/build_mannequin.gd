extends RefCounted
## Генератор mannequin.tscn: скелет по контракту (skeleton_spec.gd) и кукла из примитивов,
## прикреплённых к костям через BoneAttachment3D. Лево/право окрашены по-разному, нос показывает +Z.

const Spec := preload("res://mannequin/skeleton_spec.gd")
const OUT := "res://mannequin/mannequin.tscn"

static var _attachments: Dictionary = {}


static func build() -> void:
	_attachments.clear()
	var profile := SkeletonProfileHumanoid.new()
	var root := Node3D.new()
	root.name = "Mannequin"
	root.set_script(load("res://mannequin/mannequin.gd"))

	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.owner = root

	for b in Spec.BONES:
		var bone_name: String = b[0]
		var parent_name: String = b[1]
		var offset: Vector3 = b[2]
		var idx := sk.add_bone(bone_name)
		if parent_name != "":
			sk.set_bone_parent(idx, sk.find_bone(parent_name))
		# Ориентация осей кости: из профиля движка. Позиция: наши пропорции.
		var ref_basis: Basis = profile.get_reference_pose(profile.find_bone(bone_name)).basis
		sk.set_bone_rest(idx, Transform3D(ref_basis, offset))
	sk.reset_bone_poses()

	_add_body(root, sk)

	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	var err := ResourceSaver.save(packed, OUT)
	assert(err == OK)
	print("mannequin: saved ", OUT, " (", sk.get_bone_count(), " bones)")
	root.free()


static func _add_body(root: Node3D, sk: Skeleton3D) -> void:
	var neutral := _mat(Color(0.62, 0.62, 0.60))
	var left := _mat(Color(0.55, 0.64, 0.78))
	var right := _mat(Color(0.78, 0.58, 0.55))
	var accent := _mat(Color(0.90, 0.78, 0.45))

	# Торс и голова. Боксы выровнены по мировым осям в T-позе.
	_box(root, sk, "Hips", Vector3(0.32, 0.17, 0.19), Vector3(0, -0.02, 0), neutral)
	_box(root, sk, "Spine", Vector3(0.30, 0.11, 0.19), Vector3(0, 0.05, 0), neutral)
	_box(root, sk, "Chest", Vector3(0.33, 0.13, 0.21), Vector3(0, 0.06, 0), neutral)
	_box(root, sk, "UpperChest", Vector3(0.38, 0.17, 0.22), Vector3(0, 0.07, 0), neutral)
	_capsule(root, sk, "Neck", 0.045, 0.09, neutral)
	var head := SphereMesh.new()
	head.radius = 0.105
	head.height = 0.21
	_mesh(root, sk, "Head", head, Vector3(0, 0.10, 0), neutral)
	_box(root, sk, "Head", Vector3(0.03, 0.03, 0.05), Vector3(0, 0.095, 0.115), accent)  # нос = +Z

	# Руки.
	for side in ["Left", "Right"]:
		var m: StandardMaterial3D = left if side == "Left" else right
		var sgn := 1.0 if side == "Left" else -1.0
		_capsule(root, sk, side + "Shoulder", 0.04, 0.14, m)
		_capsule(root, sk, side + "UpperArm", 0.045, 0.30, m)
		_capsule(root, sk, side + "LowerArm", 0.038, 0.27, m)
		_box(root, sk, side + "Hand", Vector3(0.17, 0.035, 0.09), Vector3(0.085 * sgn, 0, 0), m)

		# Ноги.
		_capsule(root, sk, side + "UpperLeg", 0.075, 0.43, m)
		_capsule(root, sk, side + "LowerLeg", 0.055, 0.40, m)
		_box(root, sk, side + "Foot", Vector3(0.10, 0.09, 0.21), Vector3(0, -0.045, 0.045), m)
		_box(root, sk, side + "Toes", Vector3(0.10, 0.04, 0.07), Vector3(0, -0.07, 0.035), m)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


static func _attachment(root: Node3D, sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	if _attachments.has(bone):
		return _attachments[bone]
	var ba := BoneAttachment3D.new()
	ba.name = "Att_" + bone
	ba.bone_name = bone
	sk.add_child(ba)
	ba.owner = root
	_attachments[bone] = ba
	return ba


static func _place(root: Node3D, ba: BoneAttachment3D, mesh: Mesh, xform: Transform3D, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mesh" + str(ba.get_child_count())
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xform
	ba.add_child(mi)
	mi.owner = root


## Бокс, выровненный по мировым осям в T-позе. size и world_offset заданы в мировых осях.
static func _box(root: Node3D, sk: Skeleton3D, bone: String, size: Vector3, world_offset: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(root, sk, bone, mesh, world_offset, mat)


static func _mesh(root: Node3D, sk: Skeleton3D, bone: String, mesh: Mesh, world_offset: Vector3, mat: Material) -> void:
	var ba := _attachment(root, sk, bone)
	var g_inv := sk.get_bone_global_rest(sk.find_bone(bone)).basis.inverse()
	_place(root, ba, mesh, Transform3D(g_inv, g_inv * world_offset), mat)


## Капсула вдоль оси Y кости (ось Y смотрит к дочерней кости) длиной length от начала кости.
static func _capsule(root: Node3D, sk: Skeleton3D, bone: String, radius: float, length: float, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length + radius
	_place(root, _attachment(root, sk, bone), mesh, Transform3D(Basis.IDENTITY, Vector3(0, length * 0.5, 0)), mat)
