extends CharacterBody3D
## Свободное движение от третьего лица с камерой через плечо.
## Кукла смотрит в +Z (конвенция glTF), поэтому её поворот = atan2(vx, vz).
##
## WASD ходьба, Shift бег, мышь камера, Esc отпустить курсор, ЛКМ вернуть.

const WALK_SPEED := 1.4
const RUN_SPEED := 4.5
const ACCEL := 14.0  ## набор/сброс скорости, м/с²
const TURN_RATE := 12.0  ## скорость доворота модели к направлению движения
const MOUSE_SENS := 0.0022
const PITCH_MIN := deg_to_rad(-70.0)
const PITCH_MAX := deg_to_rad(50.0)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _model: Node3D = $Model
@onready var _mannequin: Node3D = $Model/Mannequin
@onready var _cam_yaw: Node3D = $CameraYaw
@onready var _cam_pitch: Node3D = $CameraYaw/Pitch
@onready var _arm: SpringArm3D = $CameraYaw/Pitch/Shoulder/SpringArm3D


func _ready() -> void:
	ensure_input_actions()
	_arm.add_excluded_object(get_rid())
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_cam_yaw.rotation.y -= m.relative.x * MOUSE_SENS
		_cam_pitch.rotation.x = clampf(_cam_pitch.rotation.x - m.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, _cam_yaw.rotation.y) * Vector3(input.x, 0.0, input.y)
	var top_speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target := dir.normalized() * top_speed * minf(dir.length(), 1.0)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, ACCEL * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()

	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if speed > 0.2:
		var want := atan2(velocity.x, velocity.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, want, 1.0 - exp(-TURN_RATE * delta))
	_mannequin.set_speed(speed)


## Действия ввода заводим кодом, чтобы сцена жила без правок project.godot. Идемпотентно.
static func ensure_input_actions() -> void:
	var map := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT,
	}
	for action: String in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = map[action]
		InputMap.action_add_event(action, ev)
