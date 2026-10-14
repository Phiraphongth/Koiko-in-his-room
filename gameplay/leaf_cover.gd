class_name LeafCover
extends MultiMeshInstance3D
## Leaf clumps baked by a scene builder (Level 1's hedges). A MultiMesh keeps
## its instance data in the RenderingServer, which the headless builder does
## not have, so the builder stores the data here and it is uploaded on load.

## Per instance: 12 floats of transform (MultiMesh row-major layout) + RGBA.
@export var instances: PackedFloat32Array


func _ready() -> void:
	multimesh.instance_count = instances.size() / 16
	multimesh.buffer = instances
