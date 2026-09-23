class_name StalkerFigure
extends Node3D
## A pitch-black human silhouette for scripted scares: appears, stares at
## the player, vanishes. Reuses the character model with a black material.

const MODEL := preload("res://Simple_Character_PSX/model/glb/simple-character-psx.glb")
const ANIMATIONS := preload("res://player/animations/player_animations.res")

@export var animation: StringName = &"idle_tense"
@export var animation_speed := 0.3
@export var face_player := true

var _anim: AnimationPlayer


func _ready() -> void:
	var model := MODEL.instantiate() as Node3D
	add_child(model)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.004, 0.004, 0.004)
	black.roughness = 1.0
	black.metallic_specular = 0.0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = black
	_anim = AnimationPlayer.new()
	model.add_child(_anim)
	_anim.add_animation_library(&"", ANIMATIONS)
	play_animation(animation, animation_speed)
	visible = false


func play_animation(anim_name: StringName, speed: float = 1.0) -> void:
	_anim.play(anim_name, 0.3)
	_anim.speed_scale = speed


func appear() -> void:
	visible = true
	if not face_player:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player:
		var target := Vector3(player.global_position.x, global_position.y, player.global_position.z)
		if not target.is_equal_approx(global_position):
			look_at(target, Vector3.UP, true)


func vanish() -> void:
	visible = false
