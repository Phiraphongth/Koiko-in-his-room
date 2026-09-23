class_name WardenNPC
extends RefCounted
## One of the other players trapped with you in The Warden's Game.
## Stats are 0-10. Fear: how likely they fail / panic. Selfishness: how
## likely they hoard or betray. Trust: how much they follow and protect you.

enum Archetype { BRAVE, COWARD, SCHEMER, LOYAL, DRIFTER }

const NAMES: Array[String] = ["Aoi", "Daichi", "Ren", "Mika", "Sora", "Kenji", "Yuna", "Taro",
	"Hana", "Riku", "Nami", "Shun", "Emi", "Kaito"]
const COLORS: Array[Color] = [Color(0.85, 0.35, 0.3), Color(0.35, 0.65, 0.45), Color(0.4, 0.55, 0.9),
	Color(0.85, 0.7, 0.3), Color(0.7, 0.45, 0.8)]
const STAT_LABELS: Dictionary[StringName, String] = {&"fear": "Fear", &"selfishness": "Selfishness", &"trust": "Trust"}

var id := 0
var name := ""
var archetype: Archetype = Archetype.DRIFTER
var color := Color.WHITE
var fear := 5
var selfishness := 5
var trust := 5
var alive := true


static func create(npc_id: int, npc_name: String, type: Archetype, rng: RandomNumberGenerator) -> WardenNPC:
	var npc := WardenNPC.new()
	npc.id = npc_id
	npc.name = npc_name
	npc.archetype = type
	npc.color = COLORS[npc_id % COLORS.size()]
	match type:
		Archetype.BRAVE:
			npc._roll(rng, Vector2i(1, 3), Vector2i(2, 5), Vector2i(4, 6))
		Archetype.COWARD:
			npc._roll(rng, Vector2i(7, 9), Vector2i(3, 6), Vector2i(4, 6))
		Archetype.SCHEMER:
			npc._roll(rng, Vector2i(3, 5), Vector2i(7, 9), Vector2i(2, 4))
		Archetype.LOYAL:
			npc._roll(rng, Vector2i(3, 6), Vector2i(1, 3), Vector2i(6, 8))
		Archetype.DRIFTER:
			npc._roll(rng, Vector2i(2, 8), Vector2i(2, 8), Vector2i(3, 7))
	return npc


func change(stat: StringName, amount: int) -> int:
	var before: int = get(stat)
	set(stat, clampi(before + amount, 0, 10))
	return int(get(stat)) - before


## Chance to succeed at a dangerous task (scouting, repairs).
func task_chance() -> float:
	return clampf(0.9 - fear * 0.07, 0.2, 0.9)


func is_traitor_risk() -> bool:
	return alive and selfishness >= 6 and trust <= 3


## Short read of their body language, shown in the UI.
func demeanor() -> String:
	if not alive:
		return "Eliminated"
	var parts: PackedStringArray = []
	if fear >= 7:
		parts.append("trembling")
	elif fear <= 2:
		parts.append("steady")
	if selfishness >= 7:
		parts.append("hoarding")
	elif selfishness <= 2:
		parts.append("selfless")
	if trust >= 7:
		parts.append("trusts you")
	elif trust <= 2:
		parts.append("watching you")
	return ", ".join(parts) if not parts.is_empty() else "quiet"


func _roll(rng: RandomNumberGenerator, fear_range: Vector2i, selfish_range: Vector2i, trust_range: Vector2i) -> void:
	fear = rng.randi_range(fear_range.x, fear_range.y)
	selfishness = rng.randi_range(selfish_range.x, selfish_range.y)
	trust = rng.randi_range(trust_range.x, trust_range.y)
