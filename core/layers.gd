class_name Layers
extends RefCounted
## Physics layer bitmasks. Must match [layer_names] in project.godot.

const WORLD := 1 << 0        # layer 1
const PLAYER := 1 << 1       # layer 2
const ENEMY := 1 << 2        # layer 3
const INTERACTABLE := 1 << 3 # layer 4
const NPC := 1 << 4          # layer 5
