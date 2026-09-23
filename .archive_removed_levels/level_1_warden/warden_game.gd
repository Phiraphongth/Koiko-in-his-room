class_name WardenGame
extends RefCounted
## Pure game logic for Level 1, "The Warden's Game" (♦ intelligence / ♣ teamwork).
## No nodes and no UI: the level director and CardUI listen to the signals,
## which also makes the rules testable headless.
##
## Loop: each day has a DAY card and a NIGHT card, then upkeep eats FOOD and
## POWER. After DAYS days comes the Warden's final judgment.
## Lose when FOOD, POWER or MORALE hits 0, THREAT hits 10, or you die.
##
## Flow for the UI: card_presented -> choose(i) -> outcome_presented -> advance()

signal resources_changed(resources: Dictionary)
signal npcs_changed(npcs: Array)
signal npc_died(npc: WardenNPC, cause: StringName)
signal phase_changed(day: int, is_night: bool)
signal card_presented(card: Dictionary)
signal outcome_presented(outcome: Dictionary)
signal warden_spoke(line: String)
signal effect_requested(effect: StringName)
signal game_won(survivors: Array)
signal game_lost(reason: StringName, title: String, text: String)

const DAYS := 3
const RESOURCE_LABELS: Dictionary[StringName, String] = {
	&"supplies": "FOOD", &"power": "POWER", &"morale": "MORALE", &"threat": "THREAT"}
const LOSS: Dictionary[StringName, Array] = {
	&"supplies": ["STARVATION", "The last crumbs are gone. Hunger makes the cell silent... then violent."],
	&"power": ["DARKNESS", "The lamp dies. In the dark, something slides between the bars."],
	&"morale": ["MUTINY", "The others have had enough of you. They hold you down and call for the Warden."],
	&"threat": ["EXECUTION", "A red dot settles on your forehead. The Warden has lost patience with you."],
	&"killed": ["ELIMINATED", "You gambled with your own life. The Warden collects."],
	&"sacrifice": ["SACRIFICE", "You step into the red light. Behind you, the door opens — for them."],
}
const RIDDLES: Array[Dictionary] = [
	{"q": "I have keys but open no locks. I have space but no room. You can enter, but you cannot go inside. What am I?",
		"a": ["A keyboard", "A prison", "A piano"], "correct": 0},
	{"q": "A man points at a portrait: \"Brothers and sisters I have none, but that man's father is my father's son.\" Who is in the portrait?",
		"a": ["The man himself", "His son", "His father"], "correct": 1},
	{"q": "In a standard deck of 52 cards, how many cards are both red AND clubs?",
		"a": ["Zero", "Thirteen", "Twenty-six"], "correct": 0},
	{"q": "The more of me you take, the more you leave behind. What am I?",
		"a": ["Time", "Breath", "Footsteps"], "correct": 2},
]

var rng := RandomNumberGenerator.new()
var day := 1
var is_night := false
var finished := false
var resources: Dictionary[StringName, int] = {}
var npcs: Array[WardenNPC] = []

var _deck: Array[Dictionary] = []
var _uses: Dictionary[StringName, int] = {}
var _current: Dictionary = {}
var _deltas: Dictionary[StringName, int] = {}
var _notes: PackedStringArray = []
var _after_outcome := Callable()
var _pending_loss: StringName = &""
var _pending_win := false
var _player_dead := false
var _betrayer: WardenNPC


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	_register_deck()


## Creates the cast and resources. Call before spawning 3D figures.
func setup(npc_count: int = -1) -> void:
	resources = {&"supplies": 4, &"power": 4, &"morale": 5, &"threat": 3}
	var count := npc_count if npc_count > 0 else rng.randi_range(3, 4)
	var names := WardenNPC.NAMES.duplicate()
	var types: Array = WardenNPC.Archetype.values()
	_shuffle(names)
	_shuffle(types)
	for i in count:
		npcs.append(WardenNPC.create(i, names[i], types[i], rng))


## Deals the first card.
func begin() -> void:
	resources_changed.emit(resources)
	npcs_changed.emit(npcs)
	phase_changed.emit(day, is_night)
	_present_next()


func choose(index: int) -> void:
	if finished or _current.is_empty():
		return
	var options: Array = _current.options
	if index < 0 or index >= options.size() or options[index].get("disabled", false):
		return
	var card := _current
	_current = {}
	_deltas.clear()
	_notes.clear()
	var text: String = (card.resolve as Callable).call(options[index])
	if not _pending_win:
		_check_loss()
	_after_outcome = _advance_phase if card.id != &"final" else Callable()
	_emit_outcome(card.title, text)


## Continue after an outcome has been shown.
func advance() -> void:
	if finished:
		return
	if _pending_loss != &"":
		finished = true
		game_lost.emit(_pending_loss, LOSS[_pending_loss][0], LOSS[_pending_loss][1])
	elif _pending_win:
		finished = true
		game_won.emit(alive_npcs())
	elif _after_outcome.is_valid():
		var next := _after_outcome
		_after_outcome = Callable()
		next.call()


func alive_npcs() -> Array[WardenNPC]:
	var result: Array[WardenNPC] = []
	for npc in npcs:
		if npc.alive:
			result.append(npc)
	return result


func average_trust() -> float:
	var alive := alive_npcs()
	if alive.is_empty():
		return 0.0
	var total := 0
	for npc in alive:
		total += npc.trust
	return float(total) / alive.size()


# =========================================================================
# Turn flow
# =========================================================================

func _advance_phase() -> void:
	if not is_night:
		is_night = true
		phase_changed.emit(day, is_night)
		_present_next()
	else:
		_upkeep()


func _upkeep() -> void:
	_deltas.clear()
	_notes.clear()
	var mouths := alive_npcs().size() + 1
	_change(&"supplies", -2 if mouths >= 5 else -1)
	_change(&"power", -1)
	var text := "Night %d passes. Everyone eats what little there is; the lamp burns lower." % day
	if resources[&"power"] <= 2:
		text += "\nThe dim light frays everyone's nerves."
		for npc in alive_npcs():
			_npc(npc, &"fear", 1)
	if resources[&"supplies"] <= 2:
		text += "\nHungry eyes keep drifting toward you."
		for npc in alive_npcs():
			_npc(npc, &"trust", -1)
	_check_loss()
	_after_outcome = func() -> void:
		day += 1
		is_night = false
		phase_changed.emit(day, is_night)
		_present_next()
	_emit_outcome("NIGHT %d ENDS" % day, text)


func _present_next() -> void:
	var card := _final_card() if day >= DAYS and is_night else _draw()
	_current = card
	if card.get("warden", false):
		warden_spoke.emit(card.title)
	if card.has("effect"):
		effect_requested.emit(card.effect)
	card_presented.emit(card)


func _draw() -> Dictionary:
	var phase := &"night" if is_night else &"day"
	var pool: Array[Dictionary] = []
	var total := 0.0
	for entry in _deck:
		if entry.phase != &"any" and entry.phase != phase:
			continue
		if day < entry.get("min_day", 1) or _uses.get(entry.id, 0) >= entry.get("max_uses", 1):
			continue
		var condition: Callable = entry.get("condition", Callable())
		if condition.is_valid() and not condition.call():
			continue
		pool.append(entry)
		total += entry.weight
	var roll := rng.randf() * total
	var chosen: Dictionary = pool.back()
	for entry in pool:
		roll -= entry.weight
		if roll <= 0.0:
			chosen = entry
			break
	_uses[chosen.id] = _uses.get(chosen.id, 0) + 1
	var card: Dictionary = (chosen.build as Callable).call()
	card.id = chosen.id
	return card


func _emit_outcome(title: String, text: String) -> void:
	resources_changed.emit(resources)
	npcs_changed.emit(npcs)
	outcome_presented.emit({"title": title, "text": text, "deltas": _deltas.duplicate(), "notes": _notes.duplicate()})


func _check_loss() -> void:
	if _player_dead:
		_pending_loss = &"killed"
	elif resources[&"supplies"] <= 0:
		_pending_loss = &"supplies"
	elif resources[&"power"] <= 0:
		_pending_loss = &"power"
	elif resources[&"morale"] <= 0:
		_pending_loss = &"morale"
	elif resources[&"threat"] >= 10:
		_pending_loss = &"threat"


# =========================================================================
# Effect helpers (they also record deltas for the outcome screen)
# =========================================================================

func _change(resource: StringName, amount: int) -> void:
	var before := resources[resource]
	resources[resource] = clampi(before + amount, 0, 10)
	var delta := resources[resource] - before
	if delta != 0:
		_deltas[resource] = _deltas.get(resource, 0) + delta


func _npc(npc: WardenNPC, stat: StringName, amount: int) -> void:
	if not npc.alive:
		return
	var delta := npc.change(stat, amount)
	if delta != 0:
		_notes.append("%s  %s %s" % [npc.name, WardenNPC.STAT_LABELS[stat], ("+%d" % delta) if delta > 0 else str(delta)])


func _all(stat: StringName, amount: int, except: WardenNPC = null) -> void:
	for npc in alive_npcs():
		if npc != except:
			_npc(npc, stat, amount)


func _kill(npc: WardenNPC, cause: StringName) -> void:
	npc.alive = false
	_notes.append("%s was eliminated." % npc.name)
	npc_died.emit(npc, cause)


func _roll(chance: float) -> bool:
	return rng.randf() < chance


## Alive NPC with the highest (or lowest) value of a stat.
func _most(stat: StringName, highest: bool = true) -> WardenNPC:
	var best: WardenNPC = null
	for npc in alive_npcs():
		if best == null or (int(npc.get(stat)) > int(best.get(stat)) if highest else int(npc.get(stat)) < int(best.get(stat))):
			best = npc
	return best


func _any(predicate: Callable) -> bool:
	for npc in alive_npcs():
		if predicate.call(npc):
			return true
	return false


func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


## preview: resource -> +1 / -1 / 0 (unknown). Shown when hovering a choice.
func _opt(label: String, preview: Dictionary = {}, detail: String = "", extra: Dictionary = {}) -> Dictionary:
	var option := {"label": label, "preview": preview, "detail": detail}
	option.merge(extra)
	return option


## Options for "who do we send?" cards.
func _assign_options(verb: String, self_chance: float, nobody_preview: Dictionary) -> Array:
	var options := []
	for npc in alive_npcs():
		options.append(_opt("%s %s" % [verb, npc.name], {}, "%d%% chance" % roundi(npc.task_chance() * 100.0), {"npc": npc}))
	options.append(_opt("Go yourself", {}, "%d%% chance" % roundi(self_chance * 100.0), {"self": true}))
	options.append(_opt("Send no one", nobody_preview, "", {"nobody": true}))
	return options


# =========================================================================
# Deck
# =========================================================================

func _register_deck() -> void:
	_add(&"vent_scout", &"day", 1.0, _card_vent)
	_add(&"generator", &"day", 1.0, _card_generator)
	_add(&"food_offer", &"day", 1.0, _card_food_offer)
	_add(&"confession", &"day", 1.0, _card_confession)
	_add(&"riddle", &"day", 1.2, _card_riddle)
	_add(&"stranger", &"day", 1.0, _card_stranger)
	_add(&"bait", &"day", 1.2, _card_bait, {"min_day": 2})
	_add(&"vote", &"day", 1.5, _card_vote, {"min_day": 2, "condition": func() -> bool: return alive_npcs().size() >= 2})
	_add(&"lights_out", &"any", 0.8, _card_lights_out)
	_add(&"thief", &"any", 2.0, _card_thief, {"condition": func() -> bool: return _any(func(n: WardenNPC) -> bool: return n.selfishness >= 6)})
	_add(&"panic", &"any", 2.0, _card_panic, {"max_uses": 2, "condition": func() -> bool: return _any(func(n: WardenNPC) -> bool: return n.fear >= 7)})
	_add(&"whisper", &"any", 3.0, _card_whisper, {"condition": func() -> bool: return _betrayer == null and _any(func(n: WardenNPC) -> bool: return n.is_traitor_risk())})
	_add(&"bond", &"any", 1.5, _card_bond, {"max_uses": 2, "condition": func() -> bool: return _any(func(n: WardenNPC) -> bool: return n.trust >= 6)})
	_add(&"hound", &"night", 1.5, _card_hound, {"max_uses": 2})
	_add(&"betrayal", &"night", 10.0, _card_betrayal, {"condition": func() -> bool: return _betrayer != null and _betrayer.alive})
	_add(&"watch", &"night", 1.5, _card_watch, {"condition": func() -> bool: return _any(func(n: WardenNPC) -> bool: return n.fear <= 3 and n.trust >= 6)})
	_add(&"rations", &"night", 0.7, _card_rations, {"max_uses": 99})
	_add(&"crying", &"night", 0.5, _card_crying, {"max_uses": 99})


func _add(id: StringName, phase: StringName, weight: float, build: Callable, extra: Dictionary = {}) -> void:
	var entry := {"id": id, "phase": phase, "weight": weight, "build": build}
	entry.merge(extra)
	_deck.append(entry)


func _card(title: String, suit: String, text: String, options: Array, resolve: Callable, extra: Dictionary = {}) -> Dictionary:
	var card := {"title": title, "suit": suit, "text": text, "options": options, "resolve": resolve}
	card.merge(extra)
	return card


# --- Day cards ------------------------------------------------------------

func _card_vent() -> Dictionary:
	return _card("NOISE IN THE VENT", "♣",
		"Scratching inside the ventilation shaft. It might lead to the storage room... or to whatever is making that noise.",
		_assign_options("Send", 0.6, {&"morale": -1}), _resolve_vent)


func _resolve_vent(option: Dictionary) -> String:
	if option.has("nobody"):
		_change(&"morale", -1)
		return "Nobody moves. The scratching continues all day, and everyone blames you for doing nothing."
	if option.has("self"):
		if _roll(0.6):
			_change(&"supplies", 3)
			_change(&"morale", 1)
			return "You crawl through the dust and find a crate of canned food. The others look at you differently now."
		_change(&"threat", 2)
		return "You get stuck halfway. Something above you stops scratching... and starts listening."
	var npc: WardenNPC = option.npc
	if _roll(npc.task_chance()):
		var found := 1 if npc.selfishness >= 7 else 3
		_change(&"supplies", found)
		_npc(npc, &"fear", -1)
		_npc(npc, &"trust", 1)
		if found == 1:
			return "%s comes back with a single can. There are suspicious bulges in their jacket." % npc.name
		return "%s drops down from the vent, grinning, arms full of canned food." % npc.name
	if _roll(0.45):
		_kill(npc, &"vent")
		_change(&"morale", -1)
		return "A scream echoes through the shaft. Then something heavy is dragged away. %s never comes back." % npc.name
	_npc(npc, &"fear", 3)
	_npc(npc, &"trust", -2)
	return "%s comes back empty-handed and shaking. \"You knew what was up there,\" they whisper." % npc.name


func _card_generator() -> Dictionary:
	return _card("THE GENERATOR", "♦",
		"The lamp stutters. The backup generator is at the end of a flooded maintenance tunnel. Someone has to crawl in and restart it.",
		_assign_options("Send", 0.65, {&"power": -1}), _resolve_generator)


func _resolve_generator(option: Dictionary) -> String:
	if option.has("nobody"):
		_change(&"power", -1)
		return "The generator coughs and dies. The lamp dims."
	if option.has("self"):
		if _roll(0.65):
			_change(&"power", 3)
			_change(&"morale", 1)
			return "Knee-deep in black water, you find the breaker. The lamp flares back to life."
		_change(&"power", -1)
		_change(&"threat", 1)
		return "You flip the wrong switch. Sparks, a bang, and the sound of something waking up."
	var npc: WardenNPC = option.npc
	if _roll(npc.task_chance() + 0.05):
		_change(&"power", 3)
		_npc(npc, &"trust", 1)
		return "%s restarts the generator. The hum is the most beautiful sound you've heard in days." % npc.name
	if _roll(0.3):
		_kill(npc, &"generator")
		_change(&"morale", -1)
		return "A blue flash lights up the tunnel. The smell of burnt hair drifts back. %s is gone." % npc.name
	_npc(npc, &"fear", 2)
	_change(&"power", -1)
	return "%s panics in the dark water and crawls back out. The generator stays dead." % npc.name


func _card_food_offer() -> Dictionary:
	return _card("THE TRAY", "♣",
		"A slot opens in the wall. A tray slides through: food for three. The speaker crackles: \"SHARE IT. OR DON'T.\"",
		[_opt("Share it equally", {&"supplies": 1, &"morale": 1}), _opt("Keep it for yourself", {&"supplies": 1, &"morale": -1})],
		_resolve_food_offer, {"warden": true})


func _resolve_food_offer(option: Dictionary) -> String:
	if option.label.begins_with("Share"):
		_change(&"supplies", 1)
		_change(&"morale", 2)
		for npc in alive_npcs():
			if npc.selfishness < 6:
				_npc(npc, &"trust", 1)
		return "Everyone gets a mouthful. It isn't much, but for a moment the cell feels almost human."
	_change(&"supplies", 3)
	_change(&"morale", -2)
	_all(&"trust", -1)
	return "You pull the tray toward you. Nobody says a word. Nobody has to."


func _card_confession() -> Dictionary:
	return _card("CONFESSION", "♦",
		"The screen flickers: \"CONFESS YOUR SIN AND RECEIVE LIGHT.\" Everyone in the cell will hear it.",
		[_opt("Confess", {&"power": 1}), _opt("Stay silent", {&"threat": 1})], _resolve_confession, {"warden": true})


func _resolve_confession(option: Dictionary) -> String:
	if option.label == "Confess":
		_change(&"power", 2)
		for npc in alive_npcs():
			_npc(npc, &"trust", 1 if npc.selfishness < 6 else -1)
		return "You tell them what you did. The lamp brightens. Some of them look at you with pity; others, with interest."
	_change(&"threat", 2)
	return "Silence. The screen turns red: \"NOTED.\""


func _card_riddle() -> Dictionary:
	var riddle: Dictionary = RIDDLES[rng.randi_range(0, RIDDLES.size() - 1)]
	var answers: Array = riddle.a.duplicate()
	var correct: String = answers[riddle.correct]
	_shuffle(answers)
	var options := []
	for answer: String in answers:
		options.append(_opt(answer, {}, "", {"correct": answer == correct}))
	return _card("THE WARDEN'S RIDDLE", "♦", "\"ANSWER CORRECTLY.\"\n\n" + riddle.q, options, _resolve_riddle, {"warden": true})


func _resolve_riddle(option: Dictionary) -> String:
	if option.correct:
		_change(&"power", 2)
		_change(&"threat", -2)
		return "\"CORRECT.\" The lamp burns brighter, and the red dots on the walls fade away."
	_change(&"threat", 3)
	return "\"WRONG.\" A red laser dot crawls slowly across your chest... then switches off. A warning."


func _card_stranger() -> Dictionary:
	var trap := _roll(0.5)
	var clue := "The plea repeats word for word, with the same crackle at the same moment every time." if trap \
		else "Between sobs you hear coughing, shuffling feet, fingers scraping at the door."
	return _card("A VOICE OUTSIDE", "♦",
		"Someone at the cell door: \"Please, let me in! I have food, I'll share it!\"\n\n" + clue,
		[_opt("Open the door", {}, "", {"trap": trap}), _opt("Ignore it", {}, "", {"trap": trap})], _resolve_stranger)


func _resolve_stranger(option: Dictionary) -> String:
	var trap: bool = option.trap
	if option.label.begins_with("Open"):
		if trap:
			_change(&"threat", 3)
			_all(&"fear", 2)
			return "Nobody is there. Just a speaker taped to the bars. Laughter pours from the ceiling."
		_change(&"supplies", 3)
		_change(&"morale", 1)
		return "A shaking girl pushes a bag of bread through the door, then vanishes down the corridor."
	if trap:
		_change(&"threat", -1)
		return "The voice keeps repeating itself... then cuts off mid-word. A recording."
	_change(&"morale", -2)
	return "The begging turns into screaming. Then nothing. Nobody speaks for a long time."


func _card_bait() -> Dictionary:
	var options := []
	for npc in alive_npcs():
		options.append(_opt("Offer %s" % npc.name, {&"threat": -1, &"morale": -1}, "they will die", {"npc": npc}))
	options.append(_opt("Distract it yourself", {}, "50% chance", {"self": true}))
	options.append(_opt("Offer no one", {&"threat": 1}, "", {"nobody": true}))
	return _card("THE HOUND", "♣",
		"Something prowls outside the bars on all fours, sniffing. The speaker: \"IT WILL LEAVE... IF IT IS FED A PLAYER.\"",
		options, _resolve_bait, {"warden": true, "effect": &"hound"})


func _resolve_bait(option: Dictionary) -> String:
	if option.has("self"):
		if _roll(0.5):
			_change(&"threat", -3)
			_change(&"morale", 2)
			_all(&"trust", 1)
			return "You bang on the bars and sprint the other way. It follows your noise... and loses you. You come back to stunned faces."
		_player_dead = true
		return "You bang on the bars. It is faster than you thought."
	if option.has("nobody"):
		_change(&"threat", 3)
		return "Nobody is offered. The Hound sits outside the bars and waits. It is patient."
	var npc: WardenNPC = option.npc
	var mourned := npc.selfishness < 7
	_kill(npc, &"bait")
	_change(&"threat", -4)
	_change(&"morale", -2 if mourned else -1)
	for other in alive_npcs():
		_npc(other, &"trust", -2 if other.selfishness <= 3 else -1)
	if mourned:
		return "You point at %s. They don't even scream. The others will never forget that you chose." % npc.name
	return "You point at %s. Nobody objects — nobody liked them. That frightens you more than the Hound." % npc.name


func _card_vote() -> Dictionary:
	return _card("THE VOTE", "♣",
		"\"TONIGHT THE PLAYERS VOTE. THE ONE WITH THE MOST VOTES WILL BE ELIMINATED.\" Those who distrust you will vote for you.",
		[_opt("Accept the vote", {}, "trust decides"), _opt("Refuse to vote", {&"threat": 1})], _resolve_vote, {"warden": true})


func _resolve_vote(option: Dictionary) -> String:
	if option.label.begins_with("Refuse"):
		_change(&"threat", 3)
		return "\"REFUSAL NOTED.\" The red dots on the walls multiply."
	var alive := alive_npcs()
	var against_you := 0
	for npc in alive:
		if npc.trust <= 3:
			against_you += 1
	if against_you * 2 > alive.size():
		_change(&"threat", 4)
		_change(&"morale", 1)
		return "The votes are counted. Your name, again and again. The Warden spares you — this time — but it is watching now."
	var victim := _most(&"trust", false)
	_kill(victim, &"vote")
	_change(&"morale", -1)
	return "The votes are counted. %s. They stare at you as the red light finds them." % victim.name


# --- Any-phase / character cards -----------------------------------------------

func _card_lights_out() -> Dictionary:
	return _card("LOW POWER", "♦",
		"The lamp buzzes and dims. You could switch it off and sit in total darkness to save what's left.",
		[_opt("Switch it off", {&"power": 1, &"morale": -1}), _opt("Keep it on", {&"power": -1})], _resolve_lights_out)


func _resolve_lights_out(option: Dictionary) -> String:
	if option.label.begins_with("Switch"):
		_change(&"power", 2)
		_change(&"morale", -1)
		_all(&"fear", 2)
		return "Total darkness. Breathing. Someone's teeth chattering. Hours pass like this."
	_change(&"power", -2)
	return "The light stays. The generator whines in protest."


func _card_thief() -> Dictionary:
	var npc := _most(&"selfishness")
	return _card("MISSING FOOD", "♣",
		"Part of the food is gone. %s has crumbs on their sleeve and won't meet your eyes." % npc.name,
		[_opt("Punish %s" % npc.name, {&"supplies": 1, &"morale": 1}), _opt("Let it go", {&"morale": -1})],
		_resolve_thief.bind(npc))


func _resolve_thief(option: Dictionary, npc: WardenNPC) -> String:
	if option.label.begins_with("Punish"):
		_change(&"supplies", 1)
		_change(&"morale", 1)
		_npc(npc, &"trust", -3)
		_npc(npc, &"fear", 2)
		return "You take back what's left and make %s sleep by the bars, closest to the corridor." % npc.name
	_change(&"morale", -1)
	_npc(npc, &"selfishness", 1)
	_npc(npc, &"trust", 1)
	return "You say nothing. %s relaxes. The others notice you said nothing." % npc.name


func _card_panic() -> Dictionary:
	var npc := _most(&"fear")
	return _card("PANIC", "♣",
		"%s is hyperventilating and slamming the bars, screaming to be let out. The noise carries down the corridor." % npc.name,
		[_opt("Calm them down", {&"power": -1}), _opt("Silence them by force", {&"morale": -1}), _opt("Ignore it", {&"threat": 1})],
		_resolve_panic.bind(npc))


func _resolve_panic(option: Dictionary, npc: WardenNPC) -> String:
	if option.label.begins_with("Calm"):
		_change(&"power", -1)
		_npc(npc, &"fear", -3)
		_npc(npc, &"trust", 2)
		return "You sit with %s under the lamp and talk until their breathing slows. It takes hours." % npc.name
	if option.label.begins_with("Silence"):
		_change(&"morale", -1)
		_npc(npc, &"trust", -3)
		_npc(npc, &"fear", 1)
		return "You clamp a hand over %s's mouth until they stop. The cell is quiet. Too quiet." % npc.name
	_change(&"threat", 2)
	return "The screaming goes on and on. Somewhere far away, something answers."


func _card_whisper() -> Dictionary:
	var npc: WardenNPC = null
	for candidate in alive_npcs():
		if candidate.is_traitor_risk():
			npc = candidate
			break
	return _card("A WHISPER", "♣",
		"At night you hear %s murmuring into the speaker grille: \"...I can give you one of them. Just let me out.\"" % npc.name,
		[_opt("Confront %s" % npc.name, {}, "depends on their fear"), _opt("Pretend you didn't hear")],
		_resolve_whisper.bind(npc))


func _resolve_whisper(option: Dictionary, npc: WardenNPC) -> String:
	if option.label.begins_with("Confront"):
		if _roll(npc.fear / 10.0 + 0.3):
			_npc(npc, &"selfishness", -2)
			_npc(npc, &"trust", 1)
			return "%s crumbles. \"I wasn't going to do it. I swear.\" You almost believe them." % npc.name
		_change(&"morale", -2)
		_change(&"threat", 2)
		_npc(npc, &"trust", -2)
		return "%s lunges at you. The fight is loud and ugly, and the whole block hears it." % npc.name
	_betrayer = npc
	return "You close your eyes and keep breathing slowly. %s goes quiet. Too quiet." % npc.name


func _card_bond() -> Dictionary:
	var npc := _most(&"trust")
	return _card("A PHOTO", "♣",
		"%s shows you a creased photo of their little sister. \"If I don't make it... find her. Promise me.\"" % npc.name,
		[_opt("Promise", {&"morale": 1}), _opt("\"Don't get attached.\"")], _resolve_bond.bind(npc))


func _resolve_bond(option: Dictionary, npc: WardenNPC) -> String:
	if option.label == "Promise":
		_change(&"morale", 1)
		_npc(npc, &"trust", 2)
		return "You promise. %s smiles for the first time since you woke up here." % npc.name
	_npc(npc, &"trust", -1)
	_npc(npc, &"fear", 1)
	return "%s puts the photo away without a word." % npc.name


# --- Night cards --------------------------------------------------------------

func _card_hound() -> Dictionary:
	return _card("SOMETHING IN THE CORRIDOR", "♣",
		"Wet, dragging footsteps pass outside the bars. It stops. It sniffs.",
		[_opt("Everyone hold your breath", {}, "fear decides"), _opt("Throw food to distract it", {&"supplies": -1, &"threat": -1})],
		_resolve_hound, {"effect": &"hound"})


func _resolve_hound(option: Dictionary) -> String:
	if option.label.begins_with("Throw"):
		_change(&"supplies", -2)
		_change(&"threat", -2)
		return "You toss a can down the corridor. It chases the sound. Wet chewing, then silence."
	var coward := _most(&"fear")
	if coward and coward.fear >= 8:
		_change(&"threat", 3)
		_npc(coward, &"trust", -1)
		return "%s whimpers. The dragging stops... right outside your cell. It stays there until dawn." % coward.name
	_change(&"threat", -1)
	return "Nobody breathes. After an eternity, the dragging moves on."


func _card_betrayal() -> Dictionary:
	var npc := _betrayer
	return _card("BETRAYAL", "♣",
		"You wake to the sound of the cell door clicking. %s's spot is empty. Footsteps — heading toward the Warden's office." % npc.name,
		[_opt("Chase them into the dark", {&"power": -1}, "60% chance"), _opt("Stay put")], _resolve_betrayal.bind(npc))


func _resolve_betrayal(option: Dictionary, npc: WardenNPC) -> String:
	_betrayer = null
	if option.label.begins_with("Chase"):
		_change(&"power", -1)
		if _roll(0.6):
			_npc(npc, &"fear", 3)
			_npc(npc, &"selfishness", -2)
			return "You catch %s at the end of the corridor and drag them back. They sob the whole way." % npc.name
	var victims := alive_npcs().filter(func(n: WardenNPC) -> bool: return n != npc)
	if victims.is_empty():
		_change(&"threat", 3)
		return "%s comes back at dawn, smiling. The red dots on the walls now all point at you." % npc.name
	var victim: WardenNPC = victims[rng.randi_range(0, victims.size() - 1)]
	_kill(victim, &"betrayal")
	_change(&"morale", -2)
	_npc(npc, &"trust", -2)
	return "At dawn the red light comes for %s. %s won't look at anyone." % [victim.name, npc.name]


func _card_watch() -> Dictionary:
	var npc: WardenNPC = null
	for candidate in alive_npcs():
		if candidate.fear <= 3 and candidate.trust >= 6:
			npc = candidate
			break
	return _card("NIGHT WATCH", "♣", "%s offers to keep watch all night so the rest of you can sleep." % npc.name,
		[_opt("Accept", {&"threat": -1}), _opt("Take the watch yourself", {&"power": -1, &"threat": -1})],
		_resolve_watch.bind(npc))


func _resolve_watch(option: Dictionary, npc: WardenNPC) -> String:
	if option.label == "Accept":
		_change(&"threat", -2)
		_npc(npc, &"fear", 1)
		return "%s sits by the bars all night. In the morning they look ten years older, but you are all alive." % npc.name
	_change(&"power", -1)
	_change(&"threat", -1)
	return "You keep the lamp on and your eyes open until dawn."


func _card_rations() -> Dictionary:
	return _card("RATIONS", "♣", "Night falls. The food pile is small, and everyone is watching it.",
		[_opt("Equal portions", {&"supplies": -1, &"morale": 1}), _opt("Skip your own share", {&"morale": 1, &"threat": 1})],
		_resolve_rations)


func _resolve_rations(option: Dictionary) -> String:
	if option.label.begins_with("Equal"):
		_change(&"supplies", -1)
		_change(&"morale", 1)
		return "Everyone gets the same. Nobody is full, but nobody complains."
	_change(&"morale", 1)
	_change(&"threat", 1)
	_all(&"trust", 1)
	return "You hand your share to the others. Your stomach knots. You are slower, weaker — and they noticed."


func _card_crying() -> Dictionary:
	return _card("IN THE DARK", "♣", "Someone is crying quietly in the corner.",
		[_opt("Comfort them", {&"morale": 1, &"power": -1}), _opt("Let them be", {&"morale": -1})], _resolve_crying)


func _resolve_crying(option: Dictionary) -> String:
	if option.label.begins_with("Comfort"):
		_change(&"morale", 1)
		_change(&"power", -1)
		return "You keep the lamp on a little longer and sit with them."
	_change(&"morale", -1)
	return "The crying goes on until it doesn't."


# --- Final judgment -----------------------------------------------------------

func _final_card() -> Dictionary:
	var alive := alive_npcs()
	var options := []
	var text := "The screen turns white: \"THE EXIT WILL OPEN FOR THOSE WHO OFFER ONE SOUL. CHOOSE.\""
	if alive.is_empty():
		text = "The screen turns white: \"ONE PLAYER REMAINS. THE EXIT IS YOURS.\""
		options.append(_opt("Walk to the door", {}, "", {"action": &"alone"}))
	else:
		for npc in alive:
			options.append(_opt("Offer %s" % npc.name, {}, "they will die", {"action": &"offer", "npc": npc}))
		var power := resources[&"power"]
		options.append(_opt("♦ Override the lock", {}, "needs 5 POWER (you have %d)" % power,
			{"action": &"hack", "disabled": power < 5}))
		var trust := average_trust()
		options.append(_opt("♣ Stand together", {}, "needs average TRUST 6 (you have %.1f)" % trust,
			{"action": &"together", "disabled": trust < 6.0}))
	options.append(_opt("Offer yourself", {}, "you will die", {"action": &"self"}))
	return _card("THE WARDEN'S JUDGMENT", "♦ ♣", text, options, _resolve_final, {"id": &"final", "warden": true})


func _resolve_final(option: Dictionary) -> String:
	match option.action:
		&"alone":
			_pending_win = true
			return "You walk out alone. The door closes behind you with a soft, satisfied click."
		&"offer":
			var npc: WardenNPC = option.npc
			_kill(npc, &"judgment")
			_pending_win = true
			return "The red light chooses %s. The exit grinds open. Nobody looks back." % npc.name
		&"hack":
			_change(&"power", -5)
			_pending_win = true
			return "You pour every last watt into the lock. It sparks, screams — and opens. For all of you."
		&"together":
			_pending_win = true
			return "Nobody steps forward. Arms linked, you all walk toward the door together. The Warden... allows it. \"INTERESTING.\""
	_pending_loss = &"sacrifice"
	return "You step forward before anyone can stop you."
