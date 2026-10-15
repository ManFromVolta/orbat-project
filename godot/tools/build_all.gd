extends SceneTree
## Пересобирает все сгенерированные ресурсы (кукла, клипы, дерево, игрок, арена).
## Запуск: godot --headless --path godot -s tools/build_all.gd
## ВНИМАНИЕ: перезаписывает mannequin.tscn, locomotion.tres, player.tscn, test_arena.tscn.
## Руками правишь эти файлы в редакторе: сначала убери соответствующий шаг отсюда.

const BuildMannequin := preload("res://tools/build_mannequin.gd")
const BuildAnimations := preload("res://tools/build_animations.gd")
const BuildWorld := preload("res://tools/build_world.gd")


func _initialize() -> void:
	BuildMannequin.build()
	BuildAnimations.build()
	BuildWorld.build()
	quit()
