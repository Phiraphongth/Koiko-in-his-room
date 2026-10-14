extends SceneBuilder
## Offline tool: generates scenes/endings/dream/dream_ending.tscn — the
## ending dream after Level 4. An endless, still, mirror-like sea under a warm
## golden sky; a lone bed and nightstand in the middle, the phone on it
## ringing. God rays, drifting motes of light and soft clouds on the horizon.
## Built for the GL Compatibility renderer: no volumetrics, the reflections of
## the bed are mirrored copies under a translucent water surface.
##
## Run: open build_dream_ending.tscn and press F6, or
##   godot --headless --path . res://tools/scene_builder/build_dream_ending.tscn
## Re-running overwrites dream_ending.tscn, so make layout changes here.

const DREAM_SCRIPT := preload("res://scenes/endings/dream/dream_ending.gd")
const ALARM_PHONE := preload("res://gameplay/alarm_phone.gd")

const SKY_TOP := Color(0.36, 0.6, 0.86)
const SKY_HORIZON := Color(1.0, 0.74, 0.5)
const SUN_COLOR := Color(1.0, 0.9, 0.72)
const WATER_TINT := Color(0.86, 0.8, 0.74)
const BOUNDS := 32.0 ## invisible edge of the dream (it still looks endless)

const RAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float intensity = 0.3;
uniform float phase = 0.0;
void fragment() {
	float sides = pow(sin(UV.x * PI), 2.5);
	float ends = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.6, 1.0, UV.y));
	float shimmer = 0.75 + 0.25 * sin(TIME * 0.45 + phase + UV.y * 4.0);
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb * intensity * sides * ends * shimmer * facing;
}
"""

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D noise : repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.65, 0.8);
uniform float drift = 0.002;
void fragment() {
	vec2 c = UV - 0.5;
	float shape = 1.0 - smoothstep(0.15, 0.5, length(c * vec2(1.0, 2.6)));
	float n = texture(noise, UV * vec2(1.6, 0.7) + vec2(TIME * drift, 0.0)).r;
	ALBEDO = tint.rgb;
	ALPHA = shape * smoothstep(0.4, 0.75, n) * tint.a;
}
"""


func _output_path() -> String:
	return "res://scenes/endings/dream/dream_ending.tscn"


func _build() -> void:
	_root.name = "DreamEnding"
	_root.set_script(DREAM_SCRIPT)
	_root.set("level_id", &"dream_ending")
	_root.set("autostart", false)
	_materials()
	_dream_environment()
	_sea()
	var bed := _bed_set(_root, "BedSet", false)
	_phone(bed)
	# The reflection: the same set, upside down under the water.
	var mirror := _bed_set(_root, "Reflection", true)
	mirror.scale = Vector3(1, -1, 1)
	_light_shafts()
	_motes()
	_clouds()
	_systems()


# =========================================================================
# Materials
# =========================================================================

func _materials() -> void:
	_m.wood = _flat(Color(0.8, 0.62, 0.44), 0.55)
	_m.wood_dark = _flat(Color(0.62, 0.46, 0.32), 0.6)
	_m.linen = _flat(Color(0.98, 0.95, 0.9), 0.9)
	_m.pillow = _flat(Color(1.0, 0.98, 0.95), 0.85)
	_m.metal = _flat(Color(0.72, 0.62, 0.45), 0.35, {"metallic": 0.8})
	_m.phone = _flat(Color(0.08, 0.08, 0.1), 0.3)
	# The reflection is a little darker and doesn't cast shadows on itself.
	for key: String in ["wood", "wood_dark", "linen", "pillow", "metal", "phone"]:
		var mirrored := (_m[key] as StandardMaterial3D).duplicate() as StandardMaterial3D
		mirrored.albedo_color = mirrored.albedo_color.darkened(0.12)
		_m["mirror_" + key] = mirrored


# =========================================================================
# Sky, sun, water
# =========================================================================

func _dream_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.sky_curve = 0.18
	sky_material.ground_horizon_color = SKY_HORIZON
	# The lower half mirrors the sky: seen through the clear water it reads
	# as the sky's reflection.
	sky_material.ground_bottom_color = SKY_TOP.lerp(Color.WHITE, 0.2)
	sky_material.ground_curve = 0.14
	sky_material.sun_angle_max = 40.0
	sky_material.sun_curve = 0.06
	sky_material.energy_multiplier = 0.85
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.85
	# Haze melts the horizon into the sky, so the sea has no end.
	env.fog_enabled = true
	env.fog_light_color = Color(1.0, 0.82, 0.62)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_saturation = 1.1
	var world := WorldEnvironment.new()
	world.environment = env
	_add(_root, world, "WorldEnvironment")
	_unique.append(world)

	# Low, warm sun behind and to the right of the bed (where the rays come from).
	var sun := DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.light_angular_distance = 2.0
	sun.directional_shadow_max_distance = 40.0
	_add(_root, sun, "Sun")
	var sun_at := Vector3(30, 22, -40)
	sun.transform = Transform3D(Basis.looking_at(-sun_at, Vector3.UP), sun_at)


func _sea() -> void:
	# Walkable floor: a thin slab just under the surface.
	var floor_body := StaticBody3D.new()
	_add(_root, floor_body, "Floor")
	_box_shape(floor_body, Vector3(BOUNDS * 2.6, 1.0, BOUNDS * 2.6), Vector3(0, -0.5, 0))
	# The surface: pale, glossy, slightly see-through (the mirrored set shows
	# through it as a reflection), with slow ripples.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(WATER_TINT, 0.32)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic = 0.7
	water.roughness = 0.02
	water.metallic_specular = 0.8
	water.normal_enabled = true
	water.normal_texture = _noise(0.006, Color.BLACK, Color.WHITE, 7, true)
	water.normal_scale = 0.12
	water.uv1_scale = Vector3(18, 18, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var surface := _mesh(_root, "Water", plane, Vector3(0, 0.002, 0), water)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_unique.append(surface)
	# Invisible walls far out: the dream looks endless, but you can't get lost.
	var walls := _group(_root, "Bounds")
	for i in 16:
		var angle := TAU * i / 16.0
		var body := StaticBody3D.new()
		_add(walls, body, "Wall%d" % i)
		body.position = Vector3(cos(angle), 0, sin(angle)) * BOUNDS + Vector3(0, 2, 0)
		body.rotation.y = -angle
		_box_shape(body, Vector3(1.0, 6.0, BOUNDS * 0.45), Vector3.ZERO)
	var spawn := Marker3D.new()
	_add(_root, spawn, "SpawnPoint").position = Vector3(2.4, 0.05, 6.5)
	spawn.rotation_degrees = Vector3(0, 20.0, 0)


# =========================================================================
# Bed, nightstand, phone
# =========================================================================

## mirrored = the upside-down reflection copy (no collision, mirrored materials).
func _bed_set(parent: Node, node_name: String, mirrored: bool) -> Node3D:
	var group := _group(parent, node_name)
	var p := "mirror_" if mirrored else ""
	var collide := not mirrored
	# Bed: 1.1 m wide, 2.1 m long, headboard at -Z.
	var bed := _group(group, "Bed")
	for leg in [Vector3(-0.5, 0.06, -0.98), Vector3(0.5, 0.06, -0.98), Vector3(-0.5, 0.06, 0.98), Vector3(0.5, 0.06, 0.98)]:
		_box(bed, "Leg", Vector3(0.06, 0.12, 0.06), leg, _m[p + "wood"], false)
	_box(bed, "Frame", Vector3(1.1, 0.16, 2.1), Vector3(0, 0.2, 0), _m[p + "wood"], collide)
	_box(bed, "Mattress", Vector3(1.02, 0.18, 2.0), Vector3(0, 0.37, 0), _m[p + "linen"], false)
	_box(bed, "Headboard", Vector3(1.16, 0.62, 0.07), Vector3(0, 0.62, -1.06), _m[p + "wood"], collide)
	_box(bed, "HeadboardTrim", Vector3(1.2, 0.05, 0.09), Vector3(0, 0.95, -1.06), _m[p + "wood_dark"], false)
	# Duvet draped over the lower two thirds, with a frilled skirt falling to the frame.
	_box(bed, "Duvet", Vector3(1.1, 0.07, 1.45), Vector3(0, 0.49, 0.3), _m[p + "linen"], false)
	_box(bed, "DuvetFold", Vector3(1.1, 0.05, 0.22), Vector3(0, 0.53, -0.36), _m[p + "pillow"], false, Vector3(-8, 0, 0))
	for side in [-1.0, 1.0]:
		for k in 7:
			var z := -0.35 + k * 0.215
			_box(bed, "Frill", Vector3(0.02, 0.24, 0.2), Vector3(side * 0.56, 0.36, z), _m[p + "linen"], false, Vector3(0, 0, side * (4.0 + (k % 2) * 3.0)))
	_box(bed, "FrillEnd", Vector3(1.12, 0.24, 0.02), Vector3(0, 0.36, 1.03), _m[p + "linen"], false)
	_mesh(bed, "Pillow", _sphere(0.5), Vector3(0, 0.53, -0.76), _m[p + "pillow"], Vector3(6, 0, 0), Vector3(0.78, 0.2, 0.42))
	# Nightstand to the right of the headboard.
	var stand := _group(group, "Nightstand")
	stand.position = Vector3(0.92, 0, -0.82)
	_box(stand, "Body", Vector3(0.46, 0.5, 0.42), Vector3(0, 0.27, 0), _m[p + "wood"], collide)
	_box(stand, "Top", Vector3(0.5, 0.04, 0.46), Vector3(0, 0.54, 0), _m[p + "wood_dark"], false)
	_box(stand, "Drawer", Vector3(0.38, 0.14, 0.02), Vector3(0, 0.4, 0.215), _m[p + "wood_dark"], false)
	_mesh(stand, "Knob", _sphere(0.018), Vector3(0, 0.4, 0.235), _m[p + "metal"])
	for leg in [Vector3(-0.2, 0.01, -0.18), Vector3(0.2, 0.01, -0.18), Vector3(-0.2, 0.01, 0.18), Vector3(0.2, 0.01, 0.18)]:
		_box(stand, "Foot", Vector3(0.04, 0.04, 0.04), leg, _m[p + "wood_dark"], false)
	if mirrored:
		# A flat stand-in for the phone so its reflection is there too.
		_box(stand, "PhoneReflection", Vector3(0.075, 0.012, 0.15), Vector3(0.02, 0.565, 0.02), _m.mirror_phone, false, Vector3(0, 15, 0))
	for mesh: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
		if mirrored:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return group


func _phone(bed_set: Node3D) -> void:
	var stand := bed_set.get_node("Nightstand") as Node3D
	var phone := Area3D.new()
	phone.set_script(ALARM_PHONE)
	_add(stand, phone, "Phone")
	phone.position = Vector3(0.02, 0.565, 0.02)
	_unique.append(phone)
	var body := _group(phone, "Body")
	body.rotation_degrees = Vector3(0, 15, 0)
	_box(body, "Case", Vector3(0.075, 0.012, 0.15), Vector3.ZERO, _m.phone, false)
	var screen_material := _emissive(Color(0.75, 0.88, 1.0), 1.2)
	_box(body, "Screen", Vector3(0.066, 0.002, 0.136), Vector3(0, 0.007, 0), screen_material, false)
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 0.9, 1.0)
	light.omni_range = 1.6
	light.light_energy = 0.0
	_add(phone, light, "ScreenLight").position = Vector3(0, 0.12, 0)
	var alarm := _sound_3d(phone, "AlarmAudio3D", &"phone_alarm", Vector3.ZERO, false)
	alarm.unit_size = 4.0
	alarm.max_distance = 45.0
	alarm.volume_db = -2.0
	alarm.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# Generous interaction zone so it is easy to aim at a tiny phone.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.35, 0.45)
	shape.shape = box
	_add(phone, shape, "CollisionShape3D").position = Vector3(0, 0.1, 0)


# =========================================================================
# Light: god rays, motes, clouds
# =========================================================================

func _light_shafts() -> void:
	var shader := Shader.new()
	shader.code = RAY_SHADER
	var shafts := _group(_root, "LightShafts")
	# Slanted columns of light falling from the sun's side across the bed.
	var rays := [
		[Vector3(1.5, 6.5, -2.0), 2.2, 0.5],
		[Vector3(3.5, 7.0, -3.5), 3.0, 0.42],
		[Vector3(-0.5, 6.0, -0.5), 1.4, 0.32],
		[Vector3(5.5, 7.5, -6.0), 4.0, 0.36],
		[Vector3(0.8, 6.8, 2.5), 1.8, 0.22],
		[Vector3(-3.0, 7.2, -4.0), 2.6, 0.2],
	]
	# Each quad's length (local Y) runs back up the sunbeam towards the sun.
	var up := Vector3(30, 22, -40).normalized()
	var across := up.cross(Vector3.FORWARD).normalized()
	var beam := Basis(across, up, across.cross(up)).orthonormalized()
	for i in rays.size():
		var spec: Array = rays[i]
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("intensity", spec[2])
		material.set_shader_parameter("phase", i * 1.7)
		var ray := _group(shafts, "Ray%d" % i)
		ray.position = spec[0]
		ray.basis = beam
		for k in 2: # two crossed quads read as a volume from any angle
			var quad := QuadMesh.new()
			quad.size = Vector2(spec[1], 16.0)
			var mesh := _mesh(ray, "Quad%d" % k, quad, Vector3.ZERO, material, Vector3(0, 90.0 * k, 0))
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _motes() -> void:
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = gradient
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = glow
	material.albedo_color = Color(1.0, 0.92, 0.7)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = material
	var motes := CPUParticles3D.new()
	motes.amount = 160
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.mesh = quad
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(14, 3.5, 14)
	motes.direction = Vector3.UP
	motes.spread = 180.0
	motes.gravity = Vector3(0, 0.04, 0)
	motes.initial_velocity_min = 0.02
	motes.initial_velocity_max = 0.15
	motes.scale_amount_min = 0.4
	motes.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	motes.color_ramp = fade
	_add(_root, motes, "Motes").position = Vector3(0, 3.6, -1.0)


func _clouds() -> void:
	var shader := Shader.new()
	shader.code = CLOUD_SHADER
	var noise := _noise(0.008, Color.BLACK, Color.WHITE, 21)
	var clouds := _group(_root, "Clouds")
	for i in 9:
		var angle := deg_to_rad(-150.0 + i * 38.0 + _rng.randf_range(-10, 10))
		var distance := _rng.randf_range(150, 190)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("noise", noise)
		material.set_shader_parameter("tint", Color(1.0, _rng.randf_range(0.7, 0.8), _rng.randf_range(0.55, 0.65), 0.85))
		material.set_shader_parameter("drift", _rng.randf_range(0.001, 0.003))
		var quad := QuadMesh.new()
		quad.size = Vector2(_rng.randf_range(70, 120), _rng.randf_range(12, 20))
		var pos := Vector3(cos(angle), 0, sin(angle)) * distance + Vector3(0, _rng.randf_range(10, 26), 0)
		var cloud := _mesh(clouds, "Cloud%d" % i, quad, pos, material)
		# Face the middle of the dream (a QuadMesh faces +Z).
		cloud.basis = Basis.looking_at(pos - Vector3(0, pos.y, 0), Vector3.UP)
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# =========================================================================
# Systems
# =========================================================================

func _systems() -> void:
	var hud := CanvasLayer.new()
	hud.set_script(HUD)
	_add(_root, hud, "HUD")
	var music := AudioStreamPlayer.new()
	music.set_script(SOUND)
	music.set("sound_id", &"dream_pad")
	music.set("audio_bus", "BGM")
	music.volume_db = -9.0
	_add(_root, music, "DreamMusic")
	_unique.append(music)
