extends SceneTree
## Снимки арены с игроком (вид от камеры через плечо): стоит и бежит. Нужен рендер, см. shot.gd.
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --resolution 960x540 -s tools/shot_arena.gd -- /путь/для/png


func _initialize() -> void:
	_go()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _go() -> void:
	var out_dir := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var arena := (load("res://scenes/test_arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await create_timer(0.8).timeout
	await _shot(out_dir + "/arena_idle.png")

	Input.action_press("move_forward")
	await create_timer(1.0).timeout
	await _shot(out_dir + "/arena_walk.png")
	Input.action_press("sprint")
	await create_timer(1.2).timeout
	await _shot(out_dir + "/arena_run.png")
	print("arena shots saved to ", out_dir)
	quit()
