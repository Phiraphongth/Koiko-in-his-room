extends Node
const OUT := "C:/Users/ASUS/AppData/Local/Temp/claude/C--Users-ASUS-Documents-kopiko-in-hisroom/ca2dfa9f-23cc-406c-8230-0245cf203837/scratchpad/garden"
var lvl: Node
var p: Player
func wait(s: float) -> void: await get_tree().create_timer(s).timeout
func save(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
	img.save_png(OUT + "/" + n + ".png"); print("saved ", n)
func place(pos: Vector3, target: Vector3) -> void:
	p.global_position = pos; p.velocity = Vector3.ZERO
	var d := target - (pos + Vector3.UP * 1.6)
	p.set_facing(atan2(-d.x, -d.z))
	p.get_node("CameraYaw/CameraPitch").rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_run.call_deferred()
func _run() -> void:
	SettingsManager.set_locale("th")
	lvl = load("res://scenes/levels/level_1_maze/level_1.tscn").instantiate()
	add_child(lvl)
	EventBus.message_requested.connect(func(_t, _b): (func():
		await wait(0.5); lvl.get_node("HUD")._close_message()).call(), CONNECT_ONE_SHOT)
	while not lvl.is_running: await wait(0.5)
	p = lvl.player
	p.get_flashlight().available = true
	p.get_flashlight().visible = true
	await wait(0.6); await save("1_start")
	place(Vector3(0, 0.1, 6.0), Vector3(0, 1.2, -6.0))
	await wait(1.2); await save("2_inside")
	place(Vector3(-6.0, 0.1, 2.0), Vector3(4.0, 1.0, -4.0))
	await wait(1.2); await save("3_corner")
	# มุมสูงมองลงมาเห็นทั้งสวน
	place(Vector3(14.0, 16.0, 20.0), Vector3(0, 1.0, -2.0))
	await wait(1.2); await save("4_overview")
	print("DONE"); get_tree().quit()
