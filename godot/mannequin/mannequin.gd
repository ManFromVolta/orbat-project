extends Node3D
## Кукла человека. Весь анимационный интерфейс наружу: set_speed().
##
## Контроллер игрока, ИИ юнитов и адаптер ORBAT говорят кукле только скорость в м/с.
## Какие клипы играть и как их смешивать, решает дерево внутри куклы.

const WALK_REF := 1.4  ## скорость, на которой клип walk не растянут по времени, м/с
const RUN_REF := 4.5  ## скорость клипа run, м/с
## Во сколько раз быстрее играем цикл на RUN_REF (каденс бега выше каденса ходьбы).
const RUN_TIME_SCALE := 1.45

@onready var _tree: AnimationTree = $AnimationTree
@onready var skeleton: Skeleton3D = $Skeleton3D


func _ready() -> void:
	_tree.active = true


## speed: горизонтальная скорость тела, м/с.
func set_speed(speed: float) -> void:
	_tree.set("parameters/locomotion/blend_position", speed)
	var k := clampf((speed - WALK_REF) / (RUN_REF - WALK_REF), 0.0, 1.0)
	_tree.set("parameters/time_scale/scale", lerpf(1.0, RUN_TIME_SCALE, k))
