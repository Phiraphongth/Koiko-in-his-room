extends Node
## Threaded scene loader with fade (Autoload: LevelLoader).
## Only GameManager should call change_level(); everything else asks via EventBus.

signal load_started(path: String)
signal load_progress(ratio: float)
signal load_finished(path: String)

var is_loading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func change_level(path: String, fade: bool = true) -> void:
	if is_loading:
		push_warning("LevelLoader: already loading, ignored request for %s" % path)
		return
	is_loading = true
	load_started.emit(path)
	if fade:
		await SceneTransition.fade_out()

	var packed := await _load_threaded(path)
	if packed == null:
		push_error("LevelLoader: failed to load %s" % path)
		is_loading = false
		if fade:
			await SceneTransition.fade_in()
		return

	get_tree().change_scene_to_packed(packed)
	await get_tree().scene_changed
	is_loading = false
	load_finished.emit(path)
	if fade:
		await SceneTransition.fade_in()


func reload_current(fade: bool = true) -> void:
	var current := get_tree().current_scene
	if current:
		change_level(current.scene_file_path, fade)


func _load_threaded(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path, "PackedScene", true) != OK:
		return null
	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		load_progress.emit(progress[0])
		await get_tree().process_frame
	load_progress.emit(1.0)
	return ResourceLoader.load_threaded_get(path) as PackedScene
