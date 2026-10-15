extends RefCounted
## Генератор клипов idle / walk / run и дерева смешивания.
##
## Клипы процедурные: поза каждой кости задаётся как ГЛОБАЛЬНАЯ ориентация сегмента относительно T-позы
## (бедро наклонено на a градусов вперёд и т.п.), локальные кватернионы решает прямая кинематика по
## реальному скелету. Так не нужно помнить, как повёрнуты локальные оси костей профиля.
## Высота таза подбирается так, чтобы нижняя стопа стояла на земле (без IK, только по вертикали); если для этого таз
## пришлось бы просадить глубже max_drop, стопа остаётся над землёй (фаза полёта в беге).
##
## Углы в градусах, положительный угол = вперёд (+Z). Это заглушка до настоящих анимаций из Blender/mocap.

const Spec := preload("res://mannequin/skeleton_spec.gd")
const MANNEQUIN := "res://mannequin/mannequin.tscn"
const LIB_OUT := "res://mannequin/locomotion.tres"
const SAMPLES := 24
const ARM_ABDUCT := 5.0  # руки чуть отведены от корпуса, градусы

## thigh/bias: размах бедра вокруг смещённого вперёд среднего положения; knee0/knee: сгибание колена в опоре и в махе;
## arm/elbow0/elbow: мах руки и сгибание локтя; yaw_p/yaw_c: поворот таза и встречный поворот плеч; lean: наклон корпуса;
## foot_k: насколько стопа повторяет наклон голени; breath: дыхание (idle); max_drop: на сколько таз может опуститься,
## чтобы дотянуться стопой до земли (остальное = фаза полёта).
const IDLE := {
	"length": 4.0, "thigh": 0.0, "bias": 0.0, "knee0": 0.0, "knee": 0.0, "arm": 0.0, "elbow0": 8.0, "elbow": 0.0,
	"yaw_p": 0.0, "yaw_c": 0.0, "lean": 0.0, "foot_k": 0.0, "breath": 1.2, "max_drop": 0.02,
}
const WALK := {
	"length": 1.0, "thigh": 25.0, "bias": 3.0, "knee0": 6.0, "knee": 60.0, "arm": 22.0, "elbow0": 14.0, "elbow": 14.0,
	"yaw_p": 5.0, "yaw_c": 7.0, "lean": 2.0, "foot_k": 0.7, "breath": 0.0, "max_drop": 0.06,
}
const RUN := {
	"length": 1.0, "thigh": 38.0, "bias": 14.0, "knee0": 18.0, "knee": 105.0, "arm": 45.0, "elbow0": 90.0, "elbow": 12.0,
	"yaw_p": 8.0, "yaw_c": 10.0, "lean": 10.0, "foot_k": 0.6, "breath": 0.0, "max_drop": 0.09,
}


static func build() -> void:
	var scene := load(MANNEQUIN) as PackedScene
	var probe := scene.instantiate()
	var sk := probe.get_node("Skeleton3D") as Skeleton3D

	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _make(sk, IDLE))
	lib.add_animation("walk", _make(sk, WALK))
	lib.add_animation("run", _make(sk, RUN))
	assert(ResourceSaver.save(lib, LIB_OUT) == OK)
	print("animations: saved ", LIB_OUT)
	probe.free()

	# Второй проход: докладываем AnimationPlayer и AnimationTree в сцену куклы.
	var root := scene.instantiate()
	for old in ["AnimationPlayer", "AnimationTree"]:
		var n := root.get_node_or_null(old)
		if n:
			root.remove_child(n)
			n.free()

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.owner = root
	ap.add_animation_library("", load(LIB_OUT))

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.owner = root
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.tree_root = _make_tree()
	tree.active = true

	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, MANNEQUIN) == OK)
	print("animations: player + tree added to ", MANNEQUIN)
	root.free()


static func _make_tree() -> AnimationNodeBlendTree:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 4.5
	bs.sync = true
	var points := [["idle", 0.0], ["walk", 1.4], ["run", 4.5]]
	for p in points:
		var an := AnimationNodeAnimation.new()
		an.animation = StringName(p[0])
		bs.add_blend_point(an, p[1], -1, StringName(p[0]))

	var bt := AnimationNodeBlendTree.new()
	bt.add_node("locomotion", bs, Vector2(0, 100))
	bt.add_node("time_scale", AnimationNodeTimeScale.new(), Vector2(320, 100))
	bt.connect_node("time_scale", 0, "locomotion")
	bt.connect_node("output", 0, "time_scale")
	return bt


static func _make(sk: Skeleton3D, P: Dictionary) -> Animation:
	var length: float = P["length"]
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR

	var tracks := {}
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n == "Root":
			continue
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Skeleton3D:" + n))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		tracks[n] = t
	var tp := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(tp, NodePath("Skeleton3D:Hips"))
	anim.track_set_interpolation_type(tp, Animation.INTERPOLATION_LINEAR)

	var hips_rest := sk.get_bone_rest(sk.find_bone("Hips")).origin
	var prev := {}
	for k in SAMPLES + 1:
		var phi := float(k) / SAMPLES
		var solved := _solve(sk, _deltas(P, phi))
		var locals: Dictionary = solved["locals"]
		var fix: float = Spec.ANKLE_HEIGHT - minf(solved["pos"]["LeftFoot"].y, solved["pos"]["RightFoot"].y)
		var dy := maxf(fix, -float(P["max_drop"]))
		for n in tracks:
			var q: Quaternion = locals[n]
			if prev.has(n) and (prev[n] as Quaternion).dot(q) < 0.0:
				q = -q
			prev[n] = q
			anim.rotation_track_insert_key(tracks[n], phi * length, q)
		anim.position_track_insert_key(tp, phi * length, hips_rest + Vector3(0, dy, 0))
	return anim


## Целевая ориентация сегментов в мировых осях: G_цель = Δ * G_покоя. Кости, которых нет в словаре, наследуют родителя.
static func _deltas(P: Dictionary, phi: float) -> Dictionary:
	var th := TAU * phi
	var d := {}
	var yaw_p := deg_to_rad(P["yaw_p"]) * sin(th)
	var yaw_c := deg_to_rad(P["yaw_c"]) * sin(th)
	var lean := deg_to_rad(P["lean"])
	var breath := deg_to_rad(P["breath"]) * sin(th)

	# Таз вращается так, чтобы выносимое вперёд бедро шло вместе с тазом; плечи вращаются навстречу.
	var r_pelvis := Basis(Vector3.UP, -yaw_p)
	var r_torso_yaw := Basis(Vector3.UP, yaw_c)
	d["Hips"] = r_pelvis
	var r_chest := Basis(Vector3.RIGHT, lean) * r_torso_yaw * Basis(Vector3.RIGHT, breath)
	d["Chest"] = r_chest
	d["UpperChest"] = r_chest
	d["Head"] = Basis(Vector3.RIGHT, lean * 0.25)

	for side in ["Left", "Right"]:
		var is_left: bool = side == "Left"
		var ph := th + (0.0 if is_left else PI)

		# Ноги. alpha: бедро вперёд; kappa: сгибание колена (пятка назад).
		var alpha := deg_to_rad(P["bias"]) + deg_to_rad(P["thigh"]) * sin(ph)
		var kappa := deg_to_rad(P["knee0"]) + deg_to_rad(P["knee"]) * pow(maxf(0.0, cos(ph)), 1.3)
		var shin := alpha - kappa
		d[side + "UpperLeg"] = r_pelvis * Basis(Vector3.RIGHT, -alpha)
		d[side + "LowerLeg"] = r_pelvis * Basis(Vector3.RIGHT, -shin)
		d[side + "Foot"] = r_pelvis * Basis(Vector3.RIGHT, -float(P["foot_k"]) * shin)

		# Руки: противофаза с одноимённой ногой. Сначала опускаем руку из T-позы вниз (поворот вокруг Z),
		# потом качаем вокруг X.
		var swing := -deg_to_rad(P["arm"]) * sin(ph)
		var elbow := deg_to_rad(P["elbow0"]) + deg_to_rad(P["elbow"]) * maxf(0.0, -sin(ph))
		var hang_angle := (90.0 - ARM_ABDUCT)
		var hang := Basis(Vector3(0, 0, 1), deg_to_rad(-hang_angle if is_left else hang_angle))
		d[side + "UpperArm"] = r_torso_yaw * Basis(Vector3.RIGHT, -swing) * hang
		d[side + "LowerArm"] = r_torso_yaw * Basis(Vector3.RIGHT, -(swing + elbow)) * hang
	return d


## Прямая кинематика: из мировых целевых ориентаций получаем локальные кватернионы костей и мировые позиции суставов.
## Считаем сами на Transform/Basis, а не через Skeleton3D: вне дерева сцены его глобальные позы не пересчитываются.
## Таз стоит в позе покоя по высоте; сдвиг по вертикали вычисляет вызывающий.
static func _solve(sk: Skeleton3D, deltas: Dictionary) -> Dictionary:
	var g_des := {}
	var g_pos := {}
	var locals := {}
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var par := sk.get_bone_parent(i)
		var par_g: Basis = Basis.IDENTITY
		var par_p: Vector3 = Vector3.ZERO
		if par >= 0:
			var pn := sk.get_bone_name(par)
			par_g = g_des[pn]
			par_p = g_pos[pn]
		var rest := sk.get_bone_rest(i)
		var g: Basis
		if deltas.has(n):
			g = (deltas[n] as Basis) * sk.get_bone_global_rest(i).basis
		else:
			g = par_g * rest.basis
		g_des[n] = g
		g_pos[n] = par_p + par_g * rest.origin
		locals[n] = (par_g.inverse() * g).get_rotation_quaternion()
	return {"locals": locals, "pos": g_pos}
