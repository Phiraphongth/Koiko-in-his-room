class_name StalkerKillCutscene
extends Node
## Level 2 death cutscene, "it heard you". The Stalker has caught the player;
## this takes over the camera, the creature and the screen for four shots:
##  1. FACE   - it rears up right in front of you, turns its head upside down
##              one crack at a time and unhinges its jaw. The world falls away
##              behind it (dolly zoom).
##  2. POUNCE - it lunges and you are slammed onto your back.
##  3. PINNED - first person, on the floor: three savage bites, each one
##              shaken side to side like a dog with a rat. Blood on the lens,
##              colour draining, eyes failing.
##  4. BODY   - cut to an outside camera: it is eating what is left of you by
##              the light of your dropped torch, then drags the body off into
##              the dark, leaving a smear behind.
## play() returns on the last frame, eyes shut (black). The level then shows
## the death card.
##
##   var cutscene := StalkerKillCutscene.new()
##   add_child(cutscene)
##   await cutscene.play(player, stalker, fx)

const BLOOD := Color(0.28, 0.0, 0.015)

var _player: Player
var _stalker: BlindStalker
var _rig: StalkerRig
var _fx: HorrorFX
var _blood: BloodOverlay
var _particles: CPUParticles3D
var _blood_material: StandardMaterial3D
var _glow: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _origin := Vector3.ZERO # the player's feet
var _dir := Vector3.FORWARD # flat, from the player towards the Stalker
var _tracking := false # the player's eyes follow its head
var _aim := Vector3.ZERO
var _aim_jerk := Vector3.ZERO # the head being knocked about by each bite
var _colour := 1.0 # drains towards red with every hit


func play(player: Player, stalker: BlindStalker, fx: HorrorFX) -> void:
	_player = player
	_stalker = stalker
	_rig = stalker.rig
	_fx = fx
	_rng.randomize()
	_origin = player.global_position
	_dir = _pick_direction()
	_blood_material = StandardMaterial3D.new()
	_blood_material.albedo_color = BLOOD
	_blood_material.roughness = 0.12 # wet
	_blood_material.metallic_specular = 0.9
	_blood = BloodOverlay.new()
	add_child(_blood)
	_particles = _make_particles()
	_stalker.prepare_for_kill()
	await _shot_face()
	await _shot_pounce()
	await _shot_pinned()
	await _shot_body()


func _process(delta: float) -> void:
	if not _tracking:
		return
	_aim = _aim.lerp(_rig.get_head_position(), 1.0 - exp(-10.0 * delta))
	_aim_jerk = _aim_jerk.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	_player.cinematic_face(_aim + _aim_jerk)


# =========================================================================
# 1. FACE
# =========================================================================

func _shot_face() -> void:
	# A light of its own under its chin, so the face reads even in the dark.
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.78, 0.8, 0.9)
	_glow.light_energy = 0.0
	_glow.omni_range = 3.2
	_glow.position = Vector3(0.0, 0.9, 1.3)
	_stalker.add_child(_glow)
	create_tween().tween_property(_glow, "light_energy", 1.6, 0.8)

	# It is suddenly right there, and it rears up.
	var distance := clampf(_free_distance(_origin + Vector3.UP, _dir, 3.2) - 1.1, 1.0, 1.9)
	var stand := _origin + _dir * distance
	stand.y = _stalker.global_position.y
	var approach := create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	approach.tween_property(_stalker, "global_position", stand, 0.35)
	approach.tween_property(_stalker, "rotation:y", _stalker.yaw_towards(_origin), 0.35)
	approach.tween_property(_rig, "rear", 0.55, 0.6).set_trans(Tween.TRANS_BACK)
	approach.tween_property(_rig, "look_weight", 1.0, 0.4)
	_rig.look_target = _player.get_camera().global_position
	_stalker.screech()
	_player.add_heartbeat_spike(40.0)
	_aim = _rig.get_head_position()
	_tracking = true
	_player.cinematic_zoom(0.05, 58.0, 0.3)
	await _wait(0.75)

	# The dolly zoom: its face swells while the room falls away.
	_player.cinematic_zoom(0.05, 38.0, 2.6)
	_stalker.growl(true)
	# Its head turns over, one crack at a time.
	for i in 3:
		create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT) \
			.tween_property(_rig, "head_roll", 0.95 * (i + 1), 0.14)
		_stalker.make_sound(&"bone_crack", 3.0 - i)
		_rig.jolt(0.25)
		_player.cinematic_shake(0.01, 0.2)
		_player.add_heartbeat_spike(10.0)
		await _wait(0.45)
	# ... and the jaw keeps opening long past where a jaw should stop.
	var jaw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	jaw.tween_property(_rig, "jaw_open", 1.7, 1.0)
	jaw.tween_property(_rig, "jaw_stretch", 1.0, 1.0)
	_stalker.make_sound(&"bone_crack", 2.0)
	await _wait(0.5)
	_stalker.make_sound(&"bone_crack", 0.0)
	await _wait(0.65)


# =========================================================================
# 2. POUNCE
# =========================================================================

func _shot_pounce() -> void:
	_stalker.screech()
	var over := _origin + _dir * 0.85 # standing over you
	over.y = _stalker.global_position.y
	var pounce := create_tween().set_parallel()
	pounce.tween_property(_rig, "head_roll", 0.0, 0.12)
	pounce.tween_property(_rig, "rear", 0.2, 0.25)
	pounce.tween_property(_rig, "lunge", 0.7, 0.25)
	pounce.tween_property(_rig, "jaw_stretch", 0.6, 0.25)
	pounce.tween_property(_stalker, "global_position", over, 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_player.cinematic_zoom(0.05, 72.0, 0.25)
	await _wait(0.12)
	# Knocked flat onto your back.
	_player.cinematic_height(0.3, 0.32)
	_player.cinematic_roll(-0.4, 0.4)
	await _wait(0.22)
	_stalker.make_sound(&"thud", 8.0)
	_sound_at_player(&"gasp", 2.0)
	_impact(0.9)
	await _wait(0.45)


# =========================================================================
# 3. PINNED
# =========================================================================

func _shot_pinned() -> void:
	var bites: Array[StringName] = [&"bite", &"crunch", &"bite"]
	for i in bites.size():
		# It pulls its head back, mouth gaping...
		var wind := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
		wind.tween_property(_rig, "lunge", 0.15, 0.3)
		wind.tween_property(_rig, "jaw_open", 1.6, 0.3)
		await _wait(0.36 - i * 0.07) # faster every time
		# ...and drives it down into you.
		var strike := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		strike.tween_property(_rig, "lunge", 1.15, 0.09)
		strike.tween_property(_rig, "jaw_open", 0.0, 0.09)
		await _wait(0.09)
		_stalker.make_sound(bites[i], 5.0)
		if i == bites.size() - 1:
			_stalker.make_sound(&"bone_crack", 6.0)
		_rig.jolt(1.0)
		_spray(_rig.get_mouth_position(), 1.0)
		_impact(0.75 + 0.2 * i)
		# Shakes you like a dog with a rat.
		_stalker.make_sound(&"tear", 3.0)
		_rig.thrash = 1.0
		_player.cinematic_shake(0.05, 0.7)
		for k in 4:
			_aim_jerk += Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.15, 0.15),
				_rng.randf_range(-0.4, 0.4))
			await _wait(0.12)
		create_tween().tween_property(_rig, "thrash", 0.0, 0.15)
		# The eyes keep trying to close.
		var lids := create_tween().set_trans(Tween.TRANS_SINE)
		lids.tween_method(_set_blink, 0.0, 0.35 + 0.15 * i, 0.25)
		lids.tween_method(_set_blink, 0.35 + 0.15 * i, 0.1 * i, 0.3)
		_fx.effect_to(&"blur", 0.6 + 0.6 * i, 0.4)
		await _wait(0.25)
	await _wait(0.2)
	# Out. Hard cut.
	var out := create_tween()
	out.tween_method(_set_blink, 0.2, 1.0, 0.16)
	await out.finished
	_tracking = false


# =========================================================================
# 4. BODY
# =========================================================================

func _shot_body() -> void:
	# What is left of you, on its back, the Stalker crouched over the chest.
	var center := _origin + _dir * 0.1
	var body := _player.cinematic_corpse(center, _dir)
	var feeding := _origin + _dir * 0.95
	feeding.y = _stalker.global_position.y
	_stalker.global_position = feeding
	_stalker.rotation.y = _stalker.yaw_towards(_origin)
	_rig.rear = 0.0
	_rig.lunge = 0.4
	_rig.feed = 1.0
	_rig.jaw_open = 0.5
	_rig.jaw_stretch = 0.4
	_rig.look_weight = 0.0
	_rig.thrash = 0.0
	var pool := _make_pool(center)
	# New camera, new eyes: the lens blood stays with the dead.
	_blood.clear()
	_colour = 0.6
	_fx.tint_to(Color(1.0, 0.62, 0.6), 0.1)
	_fx.effect_to(&"vignette", 0.6, 0.1)
	var focus := center + _dir * 0.35 + Vector3.UP * 0.45
	var camera := _place_camera(focus)
	# The dropped torch, lying on the floor, rakes across the body.
	var torch := _player.get_flashlight()
	var side := _dir.cross(Vector3.UP).normalized()
	if side.dot(camera.global_position - focus) < 0.0:
		side = -side # on the camera's side, so it lights what we see
	torch.global_position = _origin - _dir * 0.5 + side * 0.9 + Vector3.UP * 0.08
	torch.look_at(center + _dir * 0.6 + Vector3.UP * 0.2)
	torch.visible = true
	_glow.light_energy = 1.2
	_glow.position = Vector3(0.0, 1.1, 0.4) # over its back, catching the spine
	_fx.effect_to(&"blur", 0.15, 0.2)
	await _wait(0.2)
	var open := create_tween()
	open.tween_method(_set_blink, 1.0, 0.0, 0.35)
	# Slow push in, tilting.
	var push := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	push.tween_property(camera, "global_position", camera.global_position.lerp(focus, 0.3), 6.0)
	push.tween_property(camera, "rotation:z", camera.rotation.z + 0.18, 6.0)

	# Feeding.
	for i in 2:
		var wind := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
		wind.tween_property(_rig, "lunge", 0.0, 0.3)
		wind.tween_property(_rig, "jaw_open", 1.4, 0.3)
		await _wait(0.35)
		var strike := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		strike.tween_property(_rig, "lunge", 0.9, 0.1)
		strike.tween_property(_rig, "jaw_open", 0.1, 0.1)
		await _wait(0.1)
		_stalker.make_sound(&"crunch" if i == 0 else &"bite", 4.0)
		_rig.jolt(0.8)
		_spray(_rig.get_mouth_position(), 1.3)
		_jolt_body(body)
		_fx.set_effect(&"pulse", 0.6)
		_fx.effect_to(&"pulse", 0.0, 0.4)
		_stalker.make_sound(&"tear", 2.0)
		_rig.thrash = 0.8
		await _wait(0.55)
		_rig.thrash = 0.0
		await _wait(0.15)

	# Jaws locked on the body, it drags you off into the dark.
	_rig.jaw_open = 0.25
	var room := clampf(_free_distance(feeding + Vector3.UP * 0.5, _dir, 4.0) - 1.3, 0.0, 1.8)
	var drag := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drag.tween_property(_rig, "feed", 0.45, 0.4)
	drag.tween_property(_rig, "lunge", 0.7, 0.4)
	drag.tween_property(_stalker, "global_position", feeding + _dir * room, 2.6)
	drag.tween_property(body, "global_position", body.global_position + _dir * room, 2.4).set_delay(0.2)
	_rig.move_speed = -0.7
	_stalker.growl(true)
	_leave_trail(body, pool, 2.6)
	await _wait(1.8)
	# The torch gutters out.
	for k in 6:
		torch.visible = not torch.visible
		await _wait(_rng.randf_range(0.04, 0.14))
	torch.visible = false
	await _wait(0.4)
	_rig.move_speed = 0.0
	var close := create_tween()
	close.tween_method(_set_blink, 0.0, 1.0, 0.6)
	await close.finished


# =========================================================================
# Helpers
# =========================================================================

## The hit lands: shake, blood on the lens, colour draining, head knocked about.
func _impact(strength: float) -> void:
	_player.cinematic_shake(0.12 * strength, 0.6)
	_player.add_heartbeat_spike(30.0 * strength)
	_blood.splat(strength)
	_fx.set_effect(&"pulse", 1.0)
	_fx.effect_to(&"pulse", 0.0, 0.5)
	_colour = maxf(_colour - 0.17 * strength, 0.25)
	_fx.tint_to(Color(1.0, 0.75 * _colour, 0.72 * _colour), 0.2)
	_aim_jerk = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3),
		_rng.randf_range(-0.5, 0.5)) * strength
	_player.cinematic_roll(_rng.randf_range(-0.6, 0.6), 0.12)


func _set_blink(value: float) -> void:
	_fx.set_effect(&"blink", value)


## Burst of blood droplets from the mouth.
func _spray(at: Vector3, amount: float) -> void:
	_particles.global_position = at
	_particles.amount = int(40 * amount)
	_particles.restart()


func _jolt_body(body: Node3D) -> void:
	var rest := body.global_position
	var kick := create_tween().set_trans(Tween.TRANS_QUAD)
	kick.tween_property(body, "global_position", rest + Vector3.UP * 0.08 + _dir * 0.06, 0.06)
	kick.tween_property(body, "global_position", rest, 0.22)


func _make_particles() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 40
	particles.lifetime = 1.1
	particles.explosiveness = 0.92
	particles.direction = Vector3.UP
	particles.spread = 60.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 3.4
	particles.gravity = Vector3(0.0, -9.8, 0.0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.8
	var drop := SphereMesh.new()
	drop.radius = 0.014
	drop.height = 0.028
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = _blood_material
	particles.mesh = drop
	add_child(particles)
	return particles


## A pool that spreads out under the body (three overlapping discs, so the
## edge is not a perfect circle).
func _make_pool(at: Vector3) -> Node3D:
	var pool := Node3D.new()
	add_child(pool)
	pool.global_position = Vector3(at.x, _origin.y + 0.006, at.z)
	pool.scale = Vector3(0.1, 1.0, 0.1)
	for i in 3:
		var disc := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.45
		mesh.bottom_radius = 0.45
		mesh.height = 0.004
		mesh.radial_segments = 18
		disc.mesh = mesh
		disc.material_override = _blood_material
		disc.position = Vector3(_rng.randf_range(-0.25, 0.25), 0.001 * i, _rng.randf_range(-0.3, 0.3))
		disc.scale = Vector3(_rng.randf_range(0.6, 1.1), 1.0, _rng.randf_range(0.7, 1.3))
		pool.add_child(disc)
	create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC) \
		.tween_property(pool, "scale", Vector3(1.4, 1.0, 1.4), 5.0)
	return pool


## Smears left behind the body while it is dragged.
func _leave_trail(body: Node3D, from: Node3D, duration: float) -> void:
	var last := from.global_position
	var elapsed := 0.0
	while elapsed < duration:
		await _wait(0.1)
		elapsed += 0.1
		var here := body.global_position + _dir * 0.95 # torso, not feet
		here.y = _origin.y + 0.007
		if here.distance_to(last) < 0.22:
			continue
		var smear := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 0.004
		mesh.radial_segments = 12
		smear.mesh = mesh
		smear.material_override = _blood_material
		add_child(smear)
		smear.global_position = (here + last) * 0.5
		smear.rotation.y = atan2(_dir.x, _dir.z)
		smear.scale = Vector3(_rng.randf_range(0.35, 0.55), 1.0, here.distance_to(last) * 1.3)
		last = here


## Outside camera for the last shot: the first angle around the body with
## room for it, side-on views first.
func _place_camera(focus: Vector3) -> Camera3D:
	var best := Vector3.ZERO
	var best_room := -1.0
	for angle: float in [90.0, -90.0, 60.0, -60.0, 120.0, -120.0, 35.0, -35.0, 150.0, -150.0, 180.0]:
		var offset := _dir.rotated(Vector3.UP, deg_to_rad(angle)) * 2.8 + Vector3.UP * 0.75
		var room := _free_distance(focus, offset.normalized(), offset.length())
		if room > best_room:
			best_room = room
			best = focus + offset.normalized() * maxf(room - 0.25, 0.5)
		if room >= offset.length():
			break
	var camera := Camera3D.new()
	camera.fov = 52.0
	add_child(camera)
	camera.global_position = best
	camera.look_at(focus)
	camera.make_current()
	return camera


## The line to stage the scene along: the way it came from if there is room
## for its whole body there, else the open direction nearest to it. (Dragged
## out of a locker it is right on top of you, with the locker behind.)
func _pick_direction() -> Vector3:
	const NEEDED := 3.0 # stand-off distance plus its body length
	var candidates: Array[Vector3] = []
	var to := _stalker.global_position - _origin
	to.y = 0.0
	if to.length() > 0.8:
		candidates.append(to.normalized())
	var facing := _player.get_facing_direction()
	for angle: float in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
		candidates.append(facing.rotated(Vector3.UP, deg_to_rad(angle)))
	var best := candidates[0]
	var best_room := -1.0
	for dir in candidates:
		var room := _free_distance(_origin + Vector3.UP * 0.6, dir, NEEDED)
		if room >= NEEDED:
			return dir
		if room > best_room:
			best_room = room
			best = dir
	return best


## Distance to the first wall along `dir` (up to `max_distance`).
func _free_distance(from: Vector3, dir: Vector3, max_distance: float) -> float:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * max_distance, Layers.WORLD)
	var hit := space.intersect_ray(query)
	return from.distance_to(hit.position) if hit else max_distance


func _sound_at_player(id: StringName, volume_db: float) -> void:
	var sound := AudioStreamPlayer.new()
	sound.bus = "SFX"
	sound.stream = ProceduralAudio.get_stream(id)
	sound.volume_db = volume_db
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
