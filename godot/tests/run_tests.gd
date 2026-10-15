extends SceneTree
## Headless-тесты куклы и контроллера.
## Запуск: godot --headless --path godot -s tests/run_tests.gd
## Код выхода 0 = всё прошло. Дополнительно пишет tests/out/gait.json (позы по фазам для контактного листа).

const Spec := preload("res://mannequin/skeleton_spec.gd")

var _fails := 0
var _checks := 0
var _dump := {}


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("  FAIL: ", msg)


func _info(msg: String) -> void:
	print("  ", msg)


func _run() -> void:
	print("== скелет")
	_test_skeleton()
	await _test_clips()
	await _test_tree()
	await _test_player()

	DirAccess.make_dir_recursive_absolute("res://tests/out")
	var f := FileAccess.open("res://tests/out/gait.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_dump))
	f.close()

	print("== итог: %d проверок, %d провалов" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# --------------------------------------------------------------------------------------------------
func _spawn_mannequin() -> Node3D:
	var m := (load("res://mannequin/mannequin.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(m)
	return m


func _test_skeleton() -> void:
	var m := _spawn_mannequin()
	var sk := m.get_node("Skeleton3D") as Skeleton3D
	var profile := SkeletonProfileHumanoid.new()

	_check(sk.get_bone_count() == Spec.BONES.size(), "число костей = таблице контракта")
	for i in profile.bone_size:
		if profile.is_required(i):
			_check(sk.find_bone(profile.get_bone_name(i)) >= 0, "обязательная кость профиля есть: " + profile.get_bone_name(i))
	for b in Spec.BONES:
		var bone_name: String = b[0]
		var idx := sk.find_bone(bone_name)
		var par := sk.get_bone_parent(idx)
		var par_name := sk.get_bone_name(par) if par >= 0 else ""
		_check(par_name == String(profile.get_bone_parent(profile.find_bone(bone_name))), "родитель %s совпадает с профилем" % bone_name)

	var head_y := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y
	_check(absf(head_y + 0.22 - Spec.HEIGHT) < 0.03, "рост ~1.75 м (голова %.3f)" % head_y)
	var lh := sk.get_bone_global_rest(sk.find_bone("LeftHand")).origin
	var rh := sk.get_bone_global_rest(sk.find_bone("RightHand")).origin
	_check(lh.x > 0.6 and rh.x < -0.6, "T-поза: левая рука в +X, правая в -X")
	_check(absf(lh.y - sk.get_bone_global_rest(sk.find_bone("LeftShoulder")).origin.y) < 0.02, "T-поза: руки горизонтально")
	var foot := sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin
	var toes := sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin
	_check(toes.z > foot.z + 0.1, "носок смотрит в +Z")
	_check(absf(foot.y - Spec.ANKLE_HEIGHT) < 0.005, "стопа в покое на высоте сустава (%.3f)" % foot.y)

	var atts := 0
	for c in sk.get_children():
		if c is BoneAttachment3D:
			atts += 1
	_check(atts > 15, "к костям прикреплены части куклы (%d)" % atts)
	m.queue_free()


func _seg_angle(sk: Skeleton3D, a: String, b: String) -> float:
	# Угол сегмента в сагиттальной плоскости: 0 = вниз, + = вперёд (+Z).
	var d := sk.get_bone_global_pose(sk.find_bone(b)).origin - sk.get_bone_global_pose(sk.find_bone(a)).origin
	return atan2(d.z, -d.y)


func _pose_at(ap: AnimationPlayer, anim: String, t: float) -> void:
	# Поза применяется сразу при seek(update=true); читать нужно в том же кадре, без await между вызовами.
	ap.play(anim)
	ap.seek(t, true)


func _test_clips() -> void:
	print("== клипы")
	var m := _spawn_mannequin()
	var sk := m.get_node("Skeleton3D") as Skeleton3D
	var ap := m.get_node("AnimationPlayer") as AnimationPlayer
	var tree := m.get_node("AnimationTree") as AnimationTree
	await process_frame  # _ready куклы включает дерево; ждём его и только потом выключаем
	tree.active = false  # иначе дерево перебивает проигрыватель
	await process_frame

	for name in ["idle", "walk", "run"]:
		_check(ap.has_animation(name), "клип есть: " + name)
		var a := ap.get_animation(name)
		_check(a.loop_mode == Animation.LOOP_LINEAR, name + ": зациклен")
		# Шов цикла: последний ключ каждой ротационной дорожки = первому.
		var worst := 0.0
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var n := a.track_get_key_count(t)
				var q0: Quaternion = a.track_get_key_value(t, 0)
				var q1: Quaternion = a.track_get_key_value(t, n - 1)
				worst = maxf(worst, 1.0 - absf(q0.dot(q1)))
		_check(worst < 1e-5, "%s: шов цикла чистый (%s)" % [name, str(worst)])

	# Кинематика по фазам.
	var speeds := {"walk": 1.4, "run": 4.5}
	var scales := {"walk": 1.0, "run": 1.45}
	for name in ["walk", "run"]:
		var a := ap.get_animation(name)
		var n := 24
		var thigh_l: Array[float] = []
		var thigh_r: Array[float] = []
		var arm_l: Array[float] = []
		var feet: Array = []  # [стояночная стопа: z, y, левая?]
		var frames: Array = []
		var min_knee := 9.0
		var min_elbow := 9.0
		var max_thigh := 0.0
		var grounded := 0
		for k in n + 1:
			var t := a.length * float(k) / n
			_pose_at(ap, name, t)
			var tl := _seg_angle(sk, "LeftUpperLeg", "LeftLowerLeg")
			var tr := _seg_angle(sk, "RightUpperLeg", "RightLowerLeg")
			var sl := _seg_angle(sk, "LeftLowerLeg", "LeftFoot")
			var sr := _seg_angle(sk, "RightLowerLeg", "RightFoot")
			var ul := _seg_angle(sk, "LeftUpperArm", "LeftLowerArm")
			var fl := _seg_angle(sk, "LeftLowerArm", "LeftHand")
			var ur := _seg_angle(sk, "RightUpperArm", "RightLowerArm")
			var fr := _seg_angle(sk, "RightLowerArm", "RightHand")
			min_knee = minf(min_knee, minf(tl - sl, tr - sr))
			min_elbow = minf(min_elbow, minf(fl - ul, fr - ur))
			max_thigh = maxf(max_thigh, absf(tl))
			if k < n:
				thigh_l.append(tl)
				thigh_r.append(tr)
				arm_l.append(ul)
			var fy_l := sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin
			var fy_r := sk.get_bone_global_pose(sk.find_bone("RightFoot")).origin
			var lowest := minf(fy_l.y, fy_r.y)
			_check(lowest > Spec.ANKLE_HEIGHT - 0.01, "%s t=%.2f: стопа не под землёй (%.3f)" % [name, t, lowest])
			if absf(lowest - Spec.ANKLE_HEIGHT) < 0.015:
				grounded += 1
			var stance_is_left := fy_l.y <= fy_r.y
			feet.append([fy_l.z if stance_is_left else fy_r.z, stance_is_left])
			var pose := {}
			for i in sk.get_bone_count():
				var o := sk.get_bone_global_pose(i).origin
				pose[sk.get_bone_name(i)] = [o.x, o.y, o.z]
			frames.append(pose)
			_check(sk.get_bone_global_pose(sk.find_bone("Head")).origin.y > 1.35, "%s t=%.2f: голова не провалилась" % [name, t])
		_dump[name] = frames

		_check(min_knee > -0.03, "%s: колено не гнётся назад (min %.3f рад)" % [name, min_knee])
		_check(min_elbow > -0.03, "%s: локоть не гнётся назад (min %.3f рад)" % [name, min_elbow])
		_check(max_thigh > deg_to_rad(20.0), "%s: размах бедра достаточный (%.1f°)" % [name, rad_to_deg(max_thigh)])
		var anti := 0.0
		var mean_l := 0.0
		var mean_r := 0.0
		for i in n:
			mean_l += thigh_l[i] / n
			mean_r += thigh_r[i] / n
		for i in n:
			anti = maxf(anti, absf((thigh_l[i] - mean_l) + (thigh_r[i] - mean_r)))
		_check(anti < 0.03, "%s: ноги в противофазе (макс. рассогласование %.3f рад)" % [name, anti])
		var share := float(grounded) / (n + 1)
		_info("%s: хотя бы одна стопа на земле в %.0f%% кадров" % [name, 100.0 * share])
		_check(share >= (0.9 if name == "walk" else 0.4), "%s: опора достаточная (%.0f%% кадров)" % [name, 100.0 * share])
		_check(_corr(thigh_l, arm_l) < -0.8, "%s: рука в противофазе с одноимённой ногой (corr %.2f)" % [name, _corr(thigh_l, arm_l)])

		# Скольжение: средняя скорость, с которой стояночная стопа уезжает назад относительно таза, против скорости тела.
		var sum := 0.0
		var cnt := 0
		var dt_real := a.length / n / float(scales[name])
		for k in n:
			if feet[k][1] == feet[k + 1][1]:
				sum += -(feet[k + 1][0] - feet[k][0]) / dt_real
				cnt += 1
		var foot_speed := sum / maxf(cnt, 1)
		_info("%s: стояночная стопа уезжает назад со скоростью %.2f м/с при скорости тела %.2f м/с (%.0f%%)" % [name, foot_speed, speeds[name], 100.0 * foot_speed / speeds[name]])
		_dump[name + "_slide_ratio"] = foot_speed / speeds[name]

	# Без активного tree проверим, что idle почти неподвижен.
	var zs: Array[float] = []
	for k in 8:
		_pose_at(ap, "idle", 4.0 * float(k) / 8.0)
		zs.append(sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin.z)
	_check(zs.max() - zs.min() < 0.005, "idle: стопы стоят на месте")
	m.queue_free()
	await process_frame


func _corr(a: Array[float], b: Array[float]) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))


func _test_tree() -> void:
	print("== дерево анимации")
	var m := _spawn_mannequin()
	var sk := m.get_node("Skeleton3D") as Skeleton3D
	var tree := m.get_node("AnimationTree") as AnimationTree
	_check(tree.active, "AnimationTree активно")
	await process_frame

	var ranges := {}
	for s in [0.0, 1.4, 4.5]:
		m.set_speed(s)
		var zmin := 9.0
		var zmax := -9.0
		for i in 60:
			tree.advance(0.033)
			var z := sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin.z
			if i >= 20:
				zmin = minf(zmin, z)
				zmax = maxf(zmax, z)
		ranges[s] = zmax - zmin
		_info("скорость %.1f м/с: размах левой стопы по Z %.2f м" % [s, ranges[s]])
	_check(ranges[0.0] < 0.02, "на нулевой скорости кукла стоит")
	_check(ranges[1.4] > 0.35, "на ходьбе стопа ходит")
	_check(ranges[4.5] > ranges[1.4] * 1.3, "бег размашистее ходьбы")
	m.queue_free()
	await process_frame


func _test_player() -> void:
	print("== игрок на арене")
	var arena := (load("res://scenes/test_arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	var player := arena.get_node("Player") as CharacterBody3D
	for i in 30:
		await physics_frame
	_check(player.is_on_floor(), "игрок стоит на полу")
	_check(absf(player.global_position.y) < 0.05, "высота на полу (%.3f)" % player.global_position.y)

	Input.action_press("move_forward")
	var start := player.global_position
	for i in 120:
		await physics_frame
	var walked := start.distance_to(player.global_position)
	var v_walk := Vector3(player.velocity.x, 0, player.velocity.z).length()
	_info("ходьба 2 с: пройдено %.2f м, скорость %.2f м/с" % [walked, v_walk])
	_check(player.global_position.z < start.z - 1.5, "W двигает вперёд по камере (-Z)")
	_check(absf(v_walk - 1.4) < 0.1, "скорость ходьбы ~1.4 м/с")

	Input.action_press("sprint")
	for i in 60:
		await physics_frame
	var v_run := Vector3(player.velocity.x, 0, player.velocity.z).length()
	_info("бег: скорость %.2f м/с" % v_run)
	_check(absf(v_run - 4.5) < 0.2, "скорость бега ~4.5 м/с")
	var model := player.get_node("Model") as Node3D
	_check(absf(angle_difference(model.rotation.y, PI)) < 0.2, "модель повёрнута по ходу (лицом в -Z)")

	Input.action_release("move_forward")
	Input.action_release("sprint")
	for i in 90:
		await physics_frame
	_check(Vector3(player.velocity.x, 0, player.velocity.z).length() < 0.05, "после отпускания клавиш останавливается")
	arena.queue_free()
	await process_frame
