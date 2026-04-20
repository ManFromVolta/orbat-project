extends Node3D
## Обзорная RTS-камера в духе Total War: панорама (WASD + ПКМ),
## зум колёсиком, СКМ влево-вправо — поворот (yaw), СКМ вверх-вниз — наклон (pitch).
## Повесьте на Node3D; дочерний Camera3D подхватится автоматически.

@export var camera_path: NodePath

@export_group("Старт")
@export var initial_focus: Vector3 = Vector3.ZERO
@export var initial_yaw_degrees: float = -35.0
@export var initial_distance: float = 14.0

@export_group("Движение")
@export var pan_speed: float = 18.0
@export var mouse_pan_sensitivity: float = 0.035
@export var zoom_per_scroll: float = 1.25
@export var rotate_key_speed: float = 1.8
@export var mouse_rotate_sensitivity: float = 0.004
## Градусы наклона на пиксель при зажатом СКМ (вертикальное движение мыши).
@export var middle_mouse_pitch_sensitivity: float = 0.12

@export_group("Зум")
@export var min_distance: float = 4.0
@export var max_distance: float = 80.0

@export_group("Угол наклона (pitch)")
@export var pitch_degrees: float = 48.0
@export var pitch_degrees_min: float = 20.0
@export var pitch_degrees_max: float = 78.0
@export var focus_height: float = 0.0

@export_group("Границы фокуса (XZ, опционально)")
@export var limit_focus: bool = false
@export var focus_min: Vector2 = Vector2(-50.0, -50.0)
@export var focus_max: Vector2 = Vector2(50.0, 50.0)

var _camera: Camera3D
var _focus: Vector3 = Vector3.ZERO
var _pitch_degrees: float = 48.0
var _yaw: float = 0.0
var _distance: float = 14.0

var _rmb_panning: bool = false
var _mmb_rotating: bool = false


func _ready() -> void:
	_camera = _resolve_camera()
	if _camera == null:
		push_error("RTSCameraController: не найден Camera3D (добавьте дочерний Camera3D или camera_path).")
		set_process(false)
		return

	_focus = initial_focus
	_pitch_degrees = pitch_degrees
	_yaw = deg_to_rad(initial_yaw_degrees)
	_distance = clampf(initial_distance, min_distance, max_distance)
	_camera.current = true
	_apply_camera_transform()


func _resolve_camera() -> Camera3D:
	if camera_path != NodePath():
		var n := get_node_or_null(camera_path)
		if n is Camera3D:
			return n
	for c in get_children():
		if c is Camera3D:
			return c
	return null


func _process(delta: float) -> void:
	if _camera == null:
		return
	_pan_keyboard(delta)
	_rotate_keys(delta)
	_clamp_focus()
	_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rmb_panning = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_mmb_rotating = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = clampf(_distance - zoom_per_scroll, min_distance, max_distance)
					_apply_camera_transform()
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = clampf(_distance + zoom_per_scroll, min_distance, max_distance)
					_apply_camera_transform()
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rmb_panning:
			_pan_mouse(mm.relative)
		if _mmb_rotating:
			_yaw -= mm.relative.x * mouse_rotate_sensitivity
			# Вертикаль: меняем угол наклона к горизонту (не высоту точки на земле).
			_pitch_degrees -= mm.relative.y * middle_mouse_pitch_sensitivity
			_pitch_degrees = clampf(_pitch_degrees, pitch_degrees_min, pitch_degrees_max)


func _pan_keyboard(delta: float) -> void:
	var ax := Input.get_axis(&"ui_left", &"ui_right")
	var ay := Input.get_axis(&"ui_up", &"ui_down")
	if is_zero_approx(ax) and is_zero_approx(ay):
		# WASD без привязки к Input Map
		if Input.is_physical_key_pressed(KEY_A):
			ax -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			ax += 1.0
		if Input.is_physical_key_pressed(KEY_W):
			ay += 1.0
		if Input.is_physical_key_pressed(KEY_S):
			ay -= 1.0
	if is_zero_approx(ax) and is_zero_approx(ay):
		return

	var right_forward := _camera_horizontal_axes()
	var right: Vector3 = right_forward[0]
	var forward: Vector3 = right_forward[1]
	var move := (right * ax + forward * ay)
	if move.length_squared() > 1e-8:
		_focus += move.normalized() * pan_speed * delta


func _rotate_keys(delta: float) -> void:
	var r := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		r -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		r += 1.0
	if not is_zero_approx(r):
		_yaw += r * rotate_key_speed * delta


func _pan_mouse(screen_delta: Vector2) -> void:
	var right_forward := _camera_horizontal_axes()
	var right: Vector3 = right_forward[0]
	var forward: Vector3 = right_forward[1]
	# Мышь вверх — сдвиг обзора «вперёд» по земле (без перевёрнутой вертикали)
	var pan := (-right * screen_delta.x + forward * screen_delta.y) * mouse_pan_sensitivity
	_focus += pan


func _camera_horizontal_axes() -> Array[Vector3]:
	var cam := _camera
	var right := cam.global_basis.x
	right.y = 0.0
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var forward := -cam.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	return [right, forward]


func _clamp_focus() -> void:
	if not limit_focus:
		return
	_focus.x = clampf(_focus.x, focus_min.x, focus_max.x)
	_focus.z = clampf(_focus.z, focus_min.y, focus_max.y)


func _apply_camera_transform() -> void:
	var target := Vector3(_focus.x, focus_height, _focus.z)
	var pitch := deg_to_rad(clampf(_pitch_degrees, pitch_degrees_min, pitch_degrees_max))
	var d := _distance

	var offset := Vector3(
		d * cos(pitch) * sin(_yaw),
		d * sin(pitch),
		d * cos(pitch) * cos(_yaw)
	)

	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)
