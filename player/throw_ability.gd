class_name ThrowAbility
extends Node
## Player inventory (decoys + keycards) and throwing.
## [aim] (RMB) shows the arc, [throw] (LMB) throws the selected decoy,
## [cycle_item] (R) switches between bottles and alarm clocks.

const THROWABLE_ITEMS: Array[StringName] = [&"bottle", &"clock"]
const ARC_STEPS := 40
const ARC_DT := 0.05

@export var throw_speed := 11.0
@export var throw_lift := 3.0

var items: Dictionary[StringName, int] = {}
var selected: StringName = &"bottle"

@onready var _player: Player = get_parent() as Player

var _arc: MeshInstance3D
var _arc_mesh: ImmediateMesh
var _aiming := false


func _ready() -> void:
	_arc_mesh = ImmediateMesh.new()
	_arc = MeshInstance3D.new()
	_arc.mesh = _arc_mesh
	_arc.top_level = true
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.6, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	_arc.material_override = material
	_arc.visible = false
	add_child.call_deferred(_arc)


func count(id: StringName) -> int:
	return items.get(id, 0)


func add_item(id: StringName, amount: int = 1) -> void:
	items[id] = count(id) + amount
	if id in THROWABLE_ITEMS and count(selected) == 0:
		selected = id
	_emit()


func take_item(id: StringName, amount: int = 1) -> bool:
	if count(id) < amount:
		return false
	items[id] = count(id) - amount
	if id in THROWABLE_ITEMS and count(selected) == 0:
		_cycle()
	_emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released(&"aim"):
		_aiming = false
		return
	if not _can_act():
		return
	if event.is_action_pressed(&"aim"):
		_aiming = true
	elif event.is_action_pressed(&"throw"):
		_throw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cycle_item"):
		_cycle()
		_emit()


func _process(_delta: float) -> void:
	var show := _aiming and _can_act() and count(selected) > 0
	_arc.visible = show
	if show:
		_draw_arc()


func _can_act() -> bool:
	return _player.state != Player.State.HIDDEN and _player.state != Player.State.DISABLED \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _cycle() -> void:
	var index := THROWABLE_ITEMS.find(selected)
	for step in THROWABLE_ITEMS.size():
		var candidate := THROWABLE_ITEMS[(index + step + 1) % THROWABLE_ITEMS.size()]
		if count(candidate) > 0:
			selected = candidate
			return


func _launch() -> Array[Vector3]:
	var aim := -_player.get_camera().global_basis.z
	var origin := _player.global_position + Vector3(0.0, 1.55, 0.0) + Vector3(aim.x, 0.0, aim.z).normalized() * 0.45
	return [origin, aim * throw_speed + Vector3.UP * throw_lift]


func _throw() -> void:
	var kind := selected # take_item() may switch the selection when this was the last one
	if not take_item(kind):
		return
	var launch := _launch()
	var thrown := Throwable.new()
	thrown.kind = kind
	_player.get_parent().add_child(thrown)
	thrown.global_position = launch[0]
	thrown.linear_velocity = launch[1]
	thrown.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_player.make_noise(1.0) # the throw itself is almost silent


func _draw_arc() -> void:
	var launch := _launch()
	var pos: Vector3 = launch[0]
	var vel: Vector3 = launch[1]
	var gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var space := _player.get_world_3d().direct_space_state
	_arc_mesh.clear_surfaces()
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_arc_mesh.surface_add_vertex(pos)
	for i in ARC_STEPS:
		var next := pos + vel * ARC_DT
		vel += gravity * ARC_DT
		var query := PhysicsRayQueryParameters3D.create(pos, next, Layers.WORLD)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			_arc_mesh.surface_add_vertex(hit.position)
			break
		_arc_mesh.surface_add_vertex(next)
		pos = next
	_arc_mesh.surface_end()


func _emit() -> void:
	EventBus.inventory_changed.emit(items.duplicate(), selected)
