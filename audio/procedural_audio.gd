class_name ProceduralAudio
extends RefCounted
## Synthesizes the game's sound effects in code, so no audio files are needed.
## Streams are generated on first request and cached. To use recorded audio
## later, return a loaded AudioStream from get_stream() for that id instead.

const RATE := 22050
const METAL_RINGS: Array[float] = [233.0, 377.0, 587.0, 911.0, 1307.0]
const CHIME_NOTES: Array[Vector2] = [Vector2(0.0, 1046.5), Vector2(0.34, 783.99), Vector2(0.68, 659.26)]

static var _cache: Dictionary[StringName, AudioStream] = {}


static func get_stream(id: StringName) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	var stream := _generate(id)
	if stream:
		_cache[id] = stream
	return stream


## Generate ahead of time (e.g. behind a black screen) to avoid hitches.
static func preload_sounds(ids: Array[StringName]) -> void:
	for id in ids:
		get_stream(id)


static func _generate(id: StringName) -> AudioStreamWAV:
	var id_string := String(id)
	if id_string.begins_with("step_"):
		return _step(id_string.trim_prefix("step_").to_int())
	if id_string.begins_with("splash_"):
		return _splash(id_string.trim_prefix("splash_").to_int())
	match id:
		&"drone": return _drone()
		&"hum": return _hum()
		&"static": return _static_noise()
		&"heartbeat": return _heartbeat()
		&"bang": return _bang()
		&"slam": return _slam()
		&"creak": return _creak()
		&"rattle": return _rattle()
		&"buzz": return _buzz()
		&"chime": return _chime()
		&"beep": return _beep()
		&"pop": return _pop()
		&"alarm": return _alarm()
		&"shutter": return _shutter()
		&"gasp": return _gasp()
		&"click": return _click()
		&"glass": return _glass()
		&"ring": return _ring()
		&"growl": return _growl()
		&"screech": return _screech()
		&"crunch": return _crunch()
		&"flatline": return _flatline()
		&"thud": return _thud()
		&"collar": return _collar()
		&"keycard": return _keycard()
		&"clang": return _clang()
		&"whisper": return _whisper()
		&"stone": return _stone()
		&"shift": return _shift()
		&"laser": return _laser()
		&"acid": return _acid()
		&"siren_low": return _siren_low()
	push_error("ProceduralAudio: unknown sound '%s'" % id)
	return null


# =========================================================================
# Helpers
# =========================================================================

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _samples(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


## Peak-normalizes to `gain` and encodes as 16-bit mono.
static func _to_wav(s: PackedFloat32Array, loop: bool = false, gain: float = 0.9) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var scale := gain / peak
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * scale, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = s.size()
	return wav


## Makes a seamless loop of `length` samples by crossfading the extra tail into the head.
static func _loop(s: PackedFloat32Array, length: int, fade: int) -> PackedFloat32Array:
	var out := s.slice(0, length)
	for i in fade:
		var k := float(i) / fade
		out[i] = s[i] * k + s[length + i] * (1.0 - k)
	return out


## Two-pole resonator (gives noise/impulses a pitched "body").
static func _resonate(input: PackedFloat32Array, freq: float, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(input.size())
	var c := 2.0 * r * cos(TAU * freq / RATE)
	var r2 := r * r
	var y1 := 0.0
	var y2 := 0.0
	for i in input.size():
		var y := input[i] + c * y1 - r2 * y2
		out[i] = y
		y2 = y1
		y1 = y
	return out


static func _thump(t: float, start: float, amp: float) -> float:
	if t < start:
		return 0.0
	var dt := t - start
	var phase := TAU * (32.0 * dt + 30.0 * (1.0 - exp(-dt * 7.0)) / 7.0) # pitch drops 62 -> 32 Hz
	return amp * sin(phase) * exp(-dt * 16.0) * (1.0 - exp(-dt * 300.0))


# =========================================================================
# Loops
# =========================================================================

## Low, uneasy room tone: brown-noise rumble + detuned sub tones that swell.
static func _drone() -> AudioStreamWAV:
	var length := 8.0
	var n := int(length * RATE)
	var s := _samples(length + 1.0)
	var rng := _rng(11)
	var brown := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		brown = (brown + rng.randf_range(-1.0, 1.0) * 0.04) * 0.996
		lp += (brown - lp) * 0.04
		var swell := 0.65 + 0.35 * sin(TAU * t / length)
		var tone := sin(TAU * 41.0 * t) * 0.5 + sin(TAU * 61.5 * t) * 0.22 \
			+ sin(TAU * 82.0 * t + 2.0 * sin(TAU * 0.25 * t)) * 0.1
		s[i] = lp * 2.5 + tone * 0.3 * swell
	return _to_wav(_loop(s, n, RATE), true, 0.8)


## Fluorescent tube: 120 Hz mains buzz with harmonics.
static func _hum() -> AudioStreamWAV:
	var n := 2 * RATE
	var s := _samples(2.1)
	var rng := _rng(3)
	for i in s.size():
		var t := float(i) / RATE
		var base := sin(TAU * 120.0 * t)
		s[i] = base * 0.5 + sin(TAU * 240.0 * t) * 0.3 + sin(TAU * 360.0 * t) * 0.12 \
			+ signf(base) * 0.06 + rng.randf_range(-1.0, 1.0) * 0.04
	return _to_wav(_loop(s, n, int(0.1 * RATE)), true, 0.6)


static func _static_noise() -> AudioStreamWAV:
	var n := int(1.5 * RATE)
	var s := _samples(1.6)
	var rng := _rng(21)
	for i in s.size():
		var crackle := 1.0 if rng.randf() < 0.003 else 0.35
		s[i] = rng.randf_range(-1.0, 1.0) * crackle
	return _to_wav(_loop(s, n, int(0.1 * RATE)), true, 0.5)


## Two-tone warning siren.
static func _alarm() -> AudioStreamWAV:
	var s := _samples(1.0)
	for i in s.size():
		var t := float(i) / RATE
		var f := 740.0 if t < 0.5 else 588.0 # whole cycles per half -> seamless
		s[i] = tanh(3.0 * sin(TAU * f * t))
	return _to_wav(s, true, 0.5)


# =========================================================================
# One-shots
# =========================================================================

## Lub-dub.
static func _heartbeat() -> AudioStreamWAV:
	var s := _samples(0.75)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = _thump(t, 0.0, 1.0) + _thump(t, 0.22, 0.65)
	return _to_wav(s, false, 0.95)


## Heavy metallic impact (something hitting a door / pipe).
static func _bang() -> AudioStreamWAV:
	var s := _samples(2.2)
	var rng := _rng(5)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var v := lp * exp(-t * 22.0) * 1.2 + sin(TAU * 52.0 * t) * exp(-t * 3.5) * 0.9
		for k in METAL_RINGS.size():
			v += sin(TAU * METAL_RINGS[k] * t) * exp(-t * (2.5 + k)) * 0.12
		s[i] = v * (1.0 - exp(-t * 800.0))
	return _to_wav(s, false, 0.95)


## Door slammed shut.
static func _slam() -> AudioStreamWAV:
	var s := _samples(1.2)
	var rng := _rng(7)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.18
		var v := lp * exp(-t * 28.0) * 1.5 + sin(TAU * 68.0 * t) * exp(-t * 10.0)
		if t > 0.09: # latch clack
			v += sin(TAU * 95.0 * (t - 0.09)) * exp(-(t - 0.09) * 30.0) * 0.3
		s[i] = v * (1.0 - exp(-t * 900.0))
	return _to_wav(s, false, 0.95)


## Hinge creak: stick-slip friction impulses through wood resonances.
static func _creak() -> AudioStreamWAV:
	var length := 1.6
	var impulses := _samples(length)
	var rng := _rng(9)
	var i := 0
	while i < impulses.size():
		var t := float(i) / RATE
		var env := sin(PI * t / length)
		impulses[i] = env * rng.randf_range(0.6, 1.0)
		i += maxi(1, int(RATE / (14.0 + 40.0 * env + rng.randf_range(-4.0, 4.0))))
	var a := _resonate(impulses, 620.0, 0.992)
	var b := _resonate(impulses, 1030.0, 0.99)
	var c := _resonate(impulses, 1780.0, 0.985)
	var s := _samples(length)
	for j in s.size():
		s[j] = a[j] + b[j] * 0.7 + c[j] * 0.4
	return _to_wav(s, false, 0.7)


## Someone violently shaking a locked door handle.
static func _rattle() -> AudioStreamWAV:
	var s := _samples(1.4)
	var rng := _rng(13)
	var start := 0.0
	var amp := 1.0
	while start < 1.2:
		var lp := 0.0
		var first := int(start * RATE)
		for j in range(first, mini(first + int(0.14 * RATE), s.size())):
			var dt := float(j - first) / RATE
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
			s[j] += amp * (lp * exp(-dt * 45.0) + sin(TAU * 110.0 * dt) * exp(-dt * 40.0) * 0.8
				+ sin(TAU * 1450.0 * dt) * exp(-dt * 30.0) * 0.15)
		start += rng.randf_range(0.07, 0.16)
		amp *= 0.9
	return _to_wav(s, false, 0.95)


## Phone vibrating on a wooden desk: three rattly pulses.
static func _buzz() -> AudioStreamWAV:
	var s := _samples(1.4)
	for i in s.size():
		var t := float(i) / RATE
		var pulse := fmod(t, 0.45)
		var env := smoothstep(0.0, 0.02, pulse) * (1.0 - smoothstep(0.28, 0.30, pulse)) if t < 1.3 else 0.0
		var tone := sin(TAU * 155.0 * t) * 0.7 + signf(sin(TAU * 155.0 * t)) * 0.3
		s[i] = tone * (0.7 + 0.3 * sin(TAU * 31.0 * t)) * env
	return _to_wav(s, false, 0.6)


## Descending three-note PA chime before an announcement.
static func _chime() -> AudioStreamWAV:
	var s := _samples(2.6)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for note in CHIME_NOTES:
			if t < note.x:
				continue
			var dt := t - note.x
			var f := note.y
			v += (sin(TAU * f * dt) + 0.35 * sin(TAU * 2.0 * f * dt) * exp(-dt * 4.0)
				+ 0.1 * sin(TAU * 3.01 * f * dt)) * exp(-dt * 2.2) * (1.0 - exp(-dt * 200.0))
		s[i] = v
	return _to_wav(s, false, 0.7)


static func _beep() -> AudioStreamWAV:
	var s := _samples(0.22)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 1000.0 * t) * smoothstep(0.0, 0.01, t) * (1.0 - smoothstep(0.18, 0.22, t))
	return _to_wav(s, false, 0.5)


static func _click() -> AudioStreamWAV:
	var s := _samples(0.12)
	var rng := _rng(17)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 200.0) + sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.4
	return _to_wav(s, false, 0.7)


## Light bulb / tube dying: pop + electrical sizzle.
static func _pop() -> AudioStreamWAV:
	var s := _samples(0.6)
	var rng := _rng(19)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.2
		var sizzle := (noise - lp) * exp(-t * 9.0) * (0.35 if rng.randf() < 0.3 else 0.08)
		s[i] = noise * exp(-t * 250.0) + sizzle + sin(TAU * 2600.0 * t) * exp(-t * 50.0) * 0.2
	return _to_wav(s, false, 0.8)


## Heavy shutter gate rolling open: motor hum, rumble and chain clacks.
static func _shutter() -> AudioStreamWAV:
	var length := 2.6
	var s := _samples(length)
	var rng := _rng(23)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.06
		var env := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(length - 0.3, length, t))
		var clack := exp(-fmod(t, 0.11) * 90.0) * rng.randf_range(-1.0, 1.0) * 0.5
		s[i] = (lp * 3.0 + sin(TAU * 90.0 * t) * 0.3 + clack) * env
	return _to_wav(s, false, 0.8)


## Sharp inhale after holding breath too long.
static func _gasp() -> AudioStreamWAV:
	var s := _samples(0.9)
	var rng := _rng(29)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp1 += (noise - lp1) * 0.3
		lp2 += (noise - lp2) * 0.05
		var env := smoothstep(0.0, 0.06, t) * exp(-t * 3.5)
		s[i] = ((lp1 - lp2) + sin(TAU * 220.0 * t) * 0.05) * env
	return _to_wav(s, false, 0.6)


## Footstep; different seeds give natural variation.
static func _step(variant: int) -> AudioStreamWAV:
	var s := _samples(0.22)
	var rng := _rng(100 + variant)
	var coeff := rng.randf_range(0.15, 0.35)
	var body := rng.randf_range(80.0, 120.0)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * coeff
		s[i] = lp * exp(-t * 30.0) + rng.randf_range(-1.0, 1.0) * exp(-t * 160.0) * 0.35 \
			+ sin(TAU * body * t) * exp(-t * 45.0) * 0.5
	return _to_wav(s, false, 0.8)


# =========================================================================
# Level 2: The Blind Stalker
# =========================================================================

## Bottle shattering: sharp transient + many short high "tinkles".
static func _glass() -> AudioStreamWAV:
	var s := _samples(1.2)
	var rng := _rng(41)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 60.0)
	for k in 40:
		var start := rng.randf_range(0.0, 0.7)
		var f := rng.randf_range(2500.0, 7000.0)
		var amp := rng.randf_range(0.1, 0.4) * exp(-start * 3.0)
		var first := int(start * RATE)
		for j in range(first, mini(first + int(0.08 * RATE), s.size())):
			var dt := float(j - first) / RATE
			s[j] += sin(TAU * f * dt) * exp(-dt * 60.0) * amp
	return _to_wav(s, false, 0.9)


## Mechanical alarm clock bell (loop): hammer hitting a bell ~22 times/s.
static func _ring() -> AudioStreamWAV:
	var s := _samples(1.0)
	for i in s.size():
		var t := float(i) / RATE
		var hit := fmod(t, 1.0 / 22.0)
		var bell := sin(TAU * 2350.0 * t) + 0.6 * sin(TAU * 3120.0 * t) + 0.3 * sin(TAU * 4700.0 * t)
		s[i] = bell * (0.35 + 0.65 * exp(-hit * 90.0))
	return _to_wav(s, true, 0.6)


## Footstep in shallow water.
static func _splash(variant: int) -> AudioStreamWAV:
	var s := _samples(0.45)
	var rng := _rng(200 + variant)
	var lp := 0.0
	var hp_prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.4
		var bubbles := sin(TAU * rng.randf_range(600.0, 1400.0) * t) * 0.15 if rng.randf() < 0.02 else 0.0
		s[i] = (lp - hp_prev * 0.5) * exp(-t * 9.0) * smoothstep(0.0, 0.01, t) + bubbles * exp(-t * 6.0)
		hp_prev = lp
	return _to_wav(s, false, 0.8)


## Wet, rattling breathing of the Stalker (loop).
static func _growl() -> AudioStreamWAV:
	var length := 4.0
	var n := int(length * RATE)
	var s := _samples(length + 0.5)
	var rng := _rng(43)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var breath := pow(0.5 - 0.5 * cos(TAU * t / 2.0), 2.0) # in/out every 2 s
		var rattle := 0.6 + 0.4 * sin(TAU * 38.0 * t)
		s[i] = (lp * 2.0 * rattle + sin(TAU * 70.0 * t) * 0.25) * breath
	return _to_wav(_loop(s, n, int(0.5 * RATE)), true, 0.8)


## Hunting screech: harsh rising-then-falling cry.
static func _screech() -> AudioStreamWAV:
	var length := 1.6
	var s := _samples(length)
	var rng := _rng(47)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 520.0 + 700.0 * sin(PI * t / length) + rng.randf_range(-60.0, 60.0)
		phase += TAU * f / RATE
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(length - 0.5, length, t))
		s[i] = (tanh(4.0 * sin(phase)) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3) * env
	return _to_wav(s, false, 0.95)


## The kill itself: a heavy wet impact with bone cracking inside it.
static func _crunch() -> AudioStreamWAV:
	var cracks: PackedFloat32Array = [0.00, 0.09, 0.17, 0.31, 0.46, 0.63]
	var s := _samples(1.3)
	var rng := _rng(83)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.07
		var impact := sin(TAU * (85.0 - 45.0 * t) * t) * exp(-t * 6.0)
		var wet := lp * 1.6 * exp(-t * 3.0)
		var snap := 0.0
		for crack in cracks:
			if t >= crack:
				snap += rng.randf_range(-1.0, 1.0) * exp(-(t - crack) * 85.0)
		s[i] = tanh((impact + wet + snap * 0.8) * 1.4)
	return _to_wav(s, false, 1.0)


## Heart monitor flatline: the tone that keeps going after the beats stop.
static func _flatline() -> AudioStreamWAV:
	var length := 2.0
	var n := int(length * RATE)
	var s := _samples(length + 0.25)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * 988.0 * t) + sin(TAU * 1976.0 * t) * 0.15) * (0.92 + 0.08 * sin(TAU * 5.0 * t))
	return _to_wav(_loop(s, n, int(0.25 * RATE)), true, 0.4)


## Heavy bare footfall of the Stalker.
static func _thud() -> AudioStreamWAV:
	var s := _samples(0.35)
	var rng := _rng(53)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.1
		s[i] = sin(TAU * 55.0 * t) * exp(-t * 18.0) + lp * exp(-t * 25.0) * 1.5
	return _to_wav(s, false, 0.9)


## Player's collar: shrill electronic double beep.
static func _collar() -> AudioStreamWAV:
	var s := _samples(0.4)
	for i in s.size():
		var t := float(i) / RATE
		var on := 1.0 if t < 0.12 or (t > 0.2 and t < 0.32) else 0.0
		s[i] = signf(sin(TAU * 2600.0 * t)) * on
	return _to_wav(s, false, 0.5)


## Keycard accepted: rising chirp.
static func _keycard() -> AudioStreamWAV:
	var s := _samples(0.35)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (900.0 + 1400.0 * t / 0.35) / RATE
		s[i] = sin(phase) * smoothstep(0.0, 0.01, t) * (1.0 - smoothstep(0.3, 0.35, t))
	return _to_wav(s, false, 0.5)


## Big steel cage door slamming open.
static func _clang() -> AudioStreamWAV:
	var s := _samples(2.5)
	var rng := _rng(59)
	for i in s.size():
		var t := float(i) / RATE
		var v := rng.randf_range(-1.0, 1.0) * exp(-t * 40.0)
		for k in METAL_RINGS.size():
			v += sin(TAU * METAL_RINGS[k] * 0.7 * t) * exp(-t * (1.2 + k * 0.6)) * 0.25
		s[i] = v
	return _to_wav(s, false, 0.95)


# =========================================================================
# Level 1: The Maze of Whispers
# =========================================================================

## Voices just below the threshold of words (loop): noise pushed through
## vowel formants, swelling in and out.
static func _whisper() -> AudioStreamWAV:
	var length := 6.0
	var n := int(length * RATE)
	var source := _samples(length + 0.5)
	var rng := _rng(71)
	for i in source.size():
		var t := float(i) / RATE
		var breath := pow(0.5 - 0.5 * cos(TAU * t / 1.5), 1.5) # ~1.5 s per "word"
		source[i] = rng.randf_range(-1.0, 1.0) * breath
	var a1 := _resonate(source, 520.0, 0.985)  # formants of a whispered vowel
	var a2 := _resonate(source, 1180.0, 0.98)
	var a3 := _resonate(source, 2650.0, 0.975)
	var s := _samples(length + 0.5)
	for i in s.size():
		s[i] = a1[i] * 0.6 + a2[i] * 0.3 + a3[i] * 0.15
	return _to_wav(_loop(s, n, int(0.5 * RATE)), true, 0.75)


## Touching a whisper stone: a clean bell that rings out.
static func _stone() -> AudioStreamWAV:
	var s := _samples(2.4)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * 659.3 * t) + 0.5 * sin(TAU * 987.8 * t) + 0.25 * sin(TAU * 1318.5 * t)) 			* exp(-t * 1.6) * (1.0 - exp(-t * 400.0))
	return _to_wav(s, false, 0.7)


## The maze reconfiguring: stone grinding on stone with a deep rumble.
static func _shift() -> AudioStreamWAV:
	var length := 3.0
	var s := _samples(length)
	var rng := _rng(73)
	var lp := 0.0
	var grind := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.05
		grind += (rng.randf_range(-1.0, 1.0) - grind) * 0.4
		var env := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(length - 0.8, length, t))
		s[i] = (lp * 3.0 + grind * 0.35 * (0.6 + 0.4 * sin(TAU * 7.0 * t)) + sin(TAU * 38.0 * t) * 0.4) * env
	return _to_wav(s, false, 0.9)


## Security laser (loop): thin electric hum.
static func _laser() -> AudioStreamWAV:
	var s := _samples(1.0)
	var rng := _rng(79)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 1240.0 * t) * 0.5 + sin(TAU * 2480.0 * t) * 0.2 + rng.randf_range(-1.0, 1.0) * 0.05
	return _to_wav(s, true, 0.35)


# =========================================================================
# Level 3: Vertical Abyss
# =========================================================================

## The acid below (loop): a wet, hissing boil.
static func _acid() -> AudioStreamWAV:
	var length := 5.0
	var n := int(length * RATE)
	var s := _samples(length + 0.5)
	var rng := _rng(83)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.25
		var hiss := (noise - lp) * 0.5
		var bubble := 0.0
		if rng.randf() < 0.0012: # a large bubble surfacing
			bubble = 1.0
		s[i] = hiss * (0.6 + 0.4 * sin(TAU * 0.7 * t)) + lp * 0.8 + bubble
	# Give the bubbles a body.
	var body := _resonate(s, 180.0, 0.99)
	for i in s.size():
		s[i] = s[i] * 0.7 + body[i] * 0.15
	return _to_wav(_loop(s, n, int(0.5 * RATE)), true, 0.7)


## Deep industrial warning horn (structure failing).
static func _siren_low() -> AudioStreamWAV:
	var length := 2.6
	var s := _samples(length)
	for i in s.size():
		var t := float(i) / RATE
		var f := 110.0 + 25.0 * sin(TAU * 0.6 * t)
		var env := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(length - 0.7, length, t))
		s[i] = (tanh(2.5 * sin(TAU * f * t)) + 0.4 * sin(TAU * f * 2.0 * t)) * env
	return _to_wav(s, false, 0.85)
