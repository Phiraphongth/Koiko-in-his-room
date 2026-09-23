class_name SceneBuilder
extends Node
## Base for offline scene-generator tools (run the tool scene with F6 or
## headless). Subclasses implement _output_path() and _build(), filling
## `_root`; this class owns saving plus the shared material / node helpers.
## Nodes appended to `_unique` get %UniqueName access in the saved scene.

const FLICKER := preload("res://gameplay/flicker_light.gd")
const DOOR := preload("res://gameplay/door.gd")
const INTERACTABLE := preload("res://core/interactable.gd")
const EXAMINABLE := preload("res://gameplay/examinable.gd")
const TRIGGER := preload("res://gameplay/trigger_zone.gd")
const STALKER := preload("res://gameplay/stalker_figure.gd")
const ANNOUNCER := preload("res://gameplay/announcer.gd")
const HUD := preload("res://ui/game_hud.gd")
const FX := preload("res://ui/horror_fx.gd")
const SOUND := preload("res://audio/procedural_sound.gd")
const SOUND_3D := preload("res://audio/procedural_sound_3d.gd")

enum Light { STEADY, FLICKER, BROKEN, OFF } # mirrors FlickerLight.Mode

const TUBE_COLOR := Color(0.82, 0.92, 1.0)
const WARM := Color(1.0, 0.76, 0.48)
const BLOOD_RED := Color(1.0, 0.07, 0.04)

var _root: Node3D
var _unique: Array[Node] = []
var _m: Dictionary[String, Material] = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 42
	_root = Node3D.new()
	_build()
	_set_owner(_root)
	for node in _unique:
		node.unique_name_in_owner = true
	var output := _output_path()
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		err = ResourceSaver.save(packed, output)
	print("%s: %s -> %s" % [get_script().resource_path.get_file(), output, error_string(err)])
	_root.free()
	get_tree().quit()


## Override: where the generated scene is saved.
func _output_path() -> String:
	return ""


## Override: name `_root`, set its script and add every node under it.
func _build() -> void:
	pass


# =========================================================================
# Materials
# =========================================================================

func _noise(freq: float, c1: Color, c2: Color, seed_value: int, normal: bool = false) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = freq
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	if normal:
		tex.as_normal_map = true
		tex.bump_strength = 6.0
	else:
		var gradient := Gradient.new()
		gradient.set_color(0, c1)
		gradient.set_color(1, c2)
		tex.color_ramp = gradient
	return tex


func _textured(c1: Color, c2: Color, freq: float, seed_value: int, roughness: float, uv_scale: Vector3, extra: Dictionary = {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise(freq, c1, c2, seed_value)
	m.roughness = roughness
	m.normal_enabled = true
	m.normal_texture = _noise(freq * 3.0, Color.BLACK, Color.WHITE, seed_value + 100, true)
	m.normal_scale = 0.35
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for key: String in extra:
		m.set(key, extra[key])
	return m


func _flat(color: Color, roughness: float, extra: Dictionary = {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	for key: String in extra:
		m.set(key, extra[key])
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# =========================================================================
# Environment & shared systems
# =========================================================================

func _environment(fog_density: float = 0.03, ambient: Color = Color(0.05, 0.06, 0.09)) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.5
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.75, 0.75, 0.78)
	env.volumetric_fog_length = 40.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.75
	env.adjustment_contrast = 1.12
	var world := WorldEnvironment.new()
	world.environment = env
	_add(_root, world, "WorldEnvironment")


## HorrorFX, HUD, Announcer and the ambient drone every level needs.
func _add_core_systems(ambience_db: float = -8.0) -> void:
	var fx := CanvasLayer.new()
	fx.set_script(FX)
	_add(_root, fx, "HorrorFX")
	_unique.append(fx)
	var hud := CanvasLayer.new()
	hud.set_script(HUD)
	_add(_root, hud, "HUD")
	var announcer := Node.new()
	announcer.set_script(ANNOUNCER)
	_add(_root, announcer, "Announcer")
	_unique.append(announcer)
	var ambience := AudioStreamPlayer.new()
	ambience.set_script(SOUND)
	ambience.set("sound_id", &"drone")
	ambience.set("play_on_ready", true)
	ambience.set("audio_bus", "BGM")
	ambience.volume_db = ambience_db
	_add(_root, ambience, "Ambience")


# =========================================================================
# Node helpers
# =========================================================================

func _csg(parent: Node, node_name: String, center: Vector3, size: Vector3, material: Material, subtract: bool = false) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = size
	box.material = material
	if subtract:
		box.operation = CSGShape3D.OPERATION_SUBTRACTION
	_add(parent, box, node_name).position = center
	return box



## Returns the node untyped so callers can chain `.position = ...`.
func _add(parent: Node, node: Node, node_name: String):
	node.name = node_name
	parent.add_child(node, true)
	return node


func _group(parent: Node, node_name: String) -> Node3D:
	return _add(parent, Node3D.new(), node_name) as Node3D


## Box prop. collide=true wraps it in a StaticBody3D.
func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, material: Material, collide: bool = true, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	if not collide:
		_add(parent, mesh, node_name)
		mesh.position = pos
		mesh.rotation_degrees = rot
		return mesh
	var body := StaticBody3D.new()
	_add(parent, body, node_name)
	body.position = pos
	body.rotation_degrees = rot
	_add(body, mesh, "Mesh")
	_box_shape(body, size, Vector3.ZERO)
	return body


func _box_shape(parent: Node, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_add(parent, shape, "Shape").position = pos


func _mesh(parent: Node, node_name: String, mesh: Mesh, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	_add(parent, instance, node_name)
	instance.position = pos
	instance.rotation_degrees = rot
	instance.scale = scale
	return instance


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


func _label(parent: Node, text: String, pos: Vector3, rot: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	_add(parent, label, "Label")
	label.position = pos
	label.rotation_degrees = rot
	return label


func _card(parent: Node, pos: Vector3, index: int) -> void:
	var card := _box(parent, "Card", Vector3(0.063, 0.003, 0.088), pos, _m.card, false, Vector3(0, _rng.randf_range(0, 360), 0))
	var diamond := index % 2 == 0
	_label(card, "♦" if diamond else "♣", Vector3(0, 0.002, 0), Vector3(-90, 0, 0), 96, 0.0004,
		Color(0.8, 0.05, 0.05) if diamond else Color(0.05, 0.05, 0.05))


func _omni(parent: Node, node_name: String, pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool, mode: int) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	light.set_script(FLICKER)
	light.set("on_energy", energy)
	light.set("mode", mode)
	_add(parent, light, node_name).position = pos
	return light


func _spot(parent: Node, node_name: String, pos: Vector3, rot: Vector3, color: Color, energy: float, light_range: float, angle: float, shadows: bool, mode: int, hum: bool) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.spot_range = light_range
	light.spot_angle = angle
	light.shadow_enabled = shadows
	light.set_script(FLICKER)
	light.set("on_energy", energy)
	light.set("mode", mode)
	light.set("hum", hum)
	_add(parent, light, node_name)
	light.position = pos
	light.rotation_degrees = rot
	return light


## kind: 0 = hinged (hinge at origin, panel along +x), 1 = sliding (centered).
func _door(parent: Node, node_name: String, pos: Vector3, yaw: float, size: Vector3, material: Material, kind: int, props: Dictionary) -> Node3D:
	var door := Node3D.new()
	door.set_script(DOOR)
	door.set("kind", kind)
	for key: String in props:
		door.set(key, props[key])
	_add(parent, door, node_name)
	door.position = pos
	door.rotation_degrees = Vector3(0, yaw, 0)
	var panel := AnimatableBody3D.new()
	_add(door, panel, "Panel")
	var center := Vector3(size.x * 0.5, size.y * 0.5, 0.0) if kind == 0 else Vector3(0.0, size.y * 0.5, 0.0)
	_box(panel, "Mesh", size, center, material, false)
	_box_shape(panel, size, center)
	if kind == 0:
		_mesh(panel, "Knob", _sphere(0.03), Vector3(size.x - 0.1, 1.0, size.z * 0.5 + 0.03), _m.pipe)
		_mesh(panel, "KnobBack", _sphere(0.03), Vector3(size.x - 0.1, 1.0, -size.z * 0.5 - 0.03), _m.pipe)
	var area := Area3D.new()
	area.set_script(INTERACTABLE)
	_add(panel, area, "Interactable")
	_box_shape(area, size + Vector3(0.0, 0.0, 0.3), center)
	return door


func _trigger(parent: Node, node_name: String, pos: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.set_script(TRIGGER)
	_add(parent, area, node_name).position = pos
	_box_shape(area, size, Vector3.ZERO)
	_unique.append(area)


func _sound_3d(parent: Node, node_name: String, id: StringName, pos: Vector3, autoplay: bool) -> AudioStreamPlayer3D:
	var sound := AudioStreamPlayer3D.new()
	sound.set_script(SOUND_3D)
	sound.set("sound_id", id)
	sound.set("play_on_ready", autoplay)
	_add(parent, sound, node_name).position = pos
	return sound


func _set_owner(node: Node) -> void:
	for child in node.get_children():
		child.owner = _root
		if child.scene_file_path == "":
			_set_owner(child)
