class_name SwingBar
extends Area3D
## A gymnastics bar hanging from the ceiling (Level 3). Jump into it to grab
## on; the player swings like a pendulum and jumps off with whatever speed
## the swing has built up — the last bar needs a full "dyno" swing to reach
## the roof ledge.

const BAR_COLOR := Color(0.9, 0.85, 0.5)

@export var length := 1.8 ## bar width the player hangs from
@export var rope_length := 1.6


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitorable = false
	add_to_group(&"climbable") # ClimbAbility looks for these
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 1.2, 0.9)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	add_child(shape)

	var material := StandardMaterial3D.new()
	material.albedo_color = BAR_COLOR * 0.6
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = BAR_COLOR
	material.emission_energy_multiplier = 0.8
	var bar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = length
	bar.mesh = cylinder
	bar.material_override = material
	bar.rotation_degrees.z = 90.0
	add_child(bar)

	# Ropes up to the ceiling mount.
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.25, 0.22, 0.2)
	for side in [-1.0, 1.0]:
		var rope := MeshInstance3D.new()
		var thin := CylinderMesh.new()
		thin.top_radius = 0.02
		thin.bottom_radius = 0.02
		thin.height = rope_length
		rope.mesh = thin
		rope.material_override = rope_material
		rope.position = Vector3(side * length * 0.45, rope_length * 0.5, 0)
		add_child(rope)
