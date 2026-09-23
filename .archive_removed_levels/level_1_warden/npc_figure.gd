class_name NPCFigure
extends Node3D
## 3D body of a WardenNPC standing at the table: tinted character model,
## floating name tag, idle animation that turns tense as fear rises, and
## death presentations (laser execution, or simply gone).

const MODEL := preload("res://Simple_Character_PSX/model/glb/simple-character-psx.glb")
const ANIMATIONS := preload("res://player/animations/player_animations.res")

var npc: WardenNPC

var _model: Node3D
var _anim: AnimationPlayer
var _name_tag: Label3D
var _current_anim: StringName = &""


## Call before adding to the tree.
func setup(p_npc: WardenNPC) -> NPCFigure:
	npc = p_npc
	return self


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	_tint(npc.color)
	_anim = AnimationPlayer.new()
	_model.add_child(_anim)
	_anim.add_animation_library(&"", ANIMATIONS)
	set_fear(npc.fear)
	_anim.seek(randf() * 4.0, true) # desync the idles

	_name_tag = Label3D.new()
	_name_tag.text = npc.name
	_name_tag.font_size = 40
	_name_tag.pixel_size = 0.0028
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.modulate = npc.color.lightened(0.35)
	_name_tag.outline_size = 8
	_name_tag.position = Vector3(0.0, 2.3, 0.0)
	add_child(_name_tag)


func set_fear(fear: int) -> void:
	var target := &"idle_tense" if fear >= 6 else &"idle"
	if target != _current_anim:
		_current_anim = target
		_anim.play(target, 0.6)
	_anim.speed_scale = 1.0 + fear * 0.06 # faster breathing when scared


## AIB-style execution: a red laser from the ceiling, then the body drops.
func execute() -> void:
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = 1.6
	beam.mesh = cylinder
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.05, 0.03)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.05, 0.03)
	glow.emission_energy_multiplier = 16.0
	beam.material_override = glow
	beam.position = Vector3(0.0, 2.75, 0.0)
	add_child(beam)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.1, 0.05)
	flash.light_energy = 6.0
	flash.omni_range = 4.0
	flash.position = Vector3(0.0, 2.0, 0.0)
	add_child(flash)
	_play_sound(&"bang")
	await get_tree().create_timer(0.18).timeout
	beam.queue_free()
	create_tween().tween_property(flash, "light_energy", 0.0, 0.6)
	_name_tag.visible = false
	_anim.pause()
	var fall := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(_model, "rotation_degrees:x", -84.0, 0.45)
	fall.tween_callback(_leave_stain)


## Taken off-screen (vent, tunnel, the Hound): the spot is simply empty.
func vanish() -> void:
	_play_sound(&"slam")
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.0, 0.001, 1.0), 0.15)
	tween.tween_callback(func() -> void: visible = false)


func _leave_stain() -> void:
	var stain := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.004, 1.6)
	stain.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.01, 0.01)
	material.roughness = 0.1
	stain.material_override = material
	stain.position = Vector3(0.0, 0.025, -0.9)
	add_child(stain)


func _tint(color: Color) -> void:
	var body := _model.find_child("body", true, false) as MeshInstance3D
	if body == null:
		return
	for surface in body.get_surface_override_material_count():
		var material := body.get_active_material(surface) as StandardMaterial3D
		if material:
			var tinted := material.duplicate() as StandardMaterial3D
			tinted.albedo_color = Color.WHITE.lerp(color, 0.55)
			body.set_surface_override_material(surface, tinted)


func _play_sound(id: StringName) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = ProceduralAudio.get_stream(id)
	sound.position = Vector3(0.0, 1.5, 0.0)
	add_child(sound)
	sound.play()
