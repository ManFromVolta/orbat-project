extends Area3D

var _velocity: Vector3 = Vector3.ZERO
var _shooter_team: String = ""
var _shooter: Node3D = null
var _ttl: float = 10.0


func setup(
		origin: Vector3,
		direction: Vector3,
		speed: float,
		shooter_team: String,
		shooter: Node3D = null
	) -> void:
	global_position = origin
	_shooter_team = shooter_team
	_shooter = shooter
	if direction.length_squared() < 1e-8:
		direction = Vector3.FORWARD
	_velocity = direction.normalized() * speed


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_ttl -= delta
	if _ttl <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == null:
		return
	# Не уничтожать снаряд при касании своей же капсулы (спавн внутри коллайдера).
	if _shooter != null and body == _shooter:
		return
	if body.has_method("apply_hit_from_projectile"):
		var consumed: Variant = body.call("apply_hit_from_projectile", self, _shooter_team)
		if consumed == true:
			queue_free()
		return
	queue_free()
