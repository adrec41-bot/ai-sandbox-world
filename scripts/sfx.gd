extends Node
## Звуки игры. Они синтезируются при запуске, файлов со звуками нет:
## щелчок пластика, когда кирпич встаёт на место, рассыпание кирпичей,
## звоночек, когда ИИ закончил постройку, и короткие звуки интерфейса.

const RATE := 22050

var volume := 0.8:
	set(v):
		volume = clampf(v, 0.0, 1.0)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_streams = {
		"click": _make(0.04, func(t: float) -> float: return sin(TAU * 1800.0 * t) * exp(-t * 120.0) * 0.5),
		"tick": _make(0.03, func(t: float) -> float: return sin(TAU * 2600.0 * t) * exp(-t * 160.0) * 0.3),
		"place": _make(0.12, _clack.bind(1.0)),
		"snap": _make(0.08, _clack.bind(1.4)),
		"break": _make(0.45, _rattle),
		"done": _make(0.6, _chime),
		"open": _make(0.12, func(t: float) -> float: return sin(TAU * lerpf(420.0, 760.0, t / 0.12) * t) * exp(-t * 26.0) * 0.35),
		"error": _make(0.22, func(t: float) -> float: return (sin(TAU * 220.0 * t) + 0.5 * sin(TAU * 233.0 * t)) * exp(-t * 14.0) * 0.3),
	}
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String, pitch := 1.0) -> void:
	if volume <= 0.0 or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.volume_db = linear_to_db(volume)
	p.play()


func _make(seconds: float, wave: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		# Короткое нарастание и затухание по краям, чтобы не было щелчков.
		var edge := minf(1.0, minf(t * 2000.0, (seconds - t) * 400.0))
		var v := clampf(wave.call(t) * edge, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


## Щелчок пластика: короткий шум и звонкий тон, два удара подряд.
func _clack(t: float, pitch: float) -> float:
	var hit := 0.0
	for start in [0.0, 0.035]:
		var u: float = t - start
		if u < 0.0:
			continue
		var noise := _rng.randf_range(-1.0, 1.0) * exp(-u * 260.0)
		var tone := sin(TAU * 1300.0 * pitch * u) * exp(-u * 70.0) + 0.4 * sin(TAU * 2900.0 * pitch * u) * exp(-u * 110.0)
		hit += (noise * 0.5 + tone * 0.45) * (1.0 if start == 0.0 else 0.55)
	return hit * 0.7


## Кирпичи сыплются: много мелких щелчков.
func _rattle(t: float) -> float:
	var v := 0.0
	for k in 7:
		var start := k * 0.055 + 0.01 * sin(k * 3.7)
		var u := t - start
		if u < 0.0:
			continue
		var f := 1100.0 + 330.0 * float(k % 3)
		v += sin(TAU * f * u) * exp(-u * 90.0) * 0.35 + _rng.randf_range(-1.0, 1.0) * exp(-u * 300.0) * 0.25
	return v * exp(-t * 2.0)


## Два звонких тона: «готово».
func _chime(t: float) -> float:
	var a := sin(TAU * 784.0 * t) * exp(-t * 6.0)
	var u := t - 0.12
	var b := sin(TAU * 1175.0 * u) * exp(-u * 5.0) if u > 0.0 else 0.0
	return (a + b) * 0.3
