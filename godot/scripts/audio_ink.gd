class_name SNDCore
extends Node

## Полный порт Core/Audio.cs — синтез звука тонами/шумом.
## Все голоса (ToneVoice/NoiseVoice) и Mixer переписаны 1:1;
## вывод — через один AudioStreamPlayer с AudioStreamGenerator (22050 Гц, моно).

const TAU := 6.283185307179586
const SAMPLE_RATE := 22050

var muted := false

var _voice_list: Array = []
var _started := false
var _ambient_on := false
var _target_master := 0.72
var _master := 0.0
var _ambient_t := 0.0
var _wind_lp := 0.0
var _seed := 1234567

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	_init_out()


func _init_out() -> void:
	if _player != null:
		return
	_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = 0.35
	_player.stream = stream
	_player.volume_db = 0.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func unlock() -> void:
	_init_out()
	if _started:
		return
	_started = true
	_ambient_on = true


func set_muted(m: bool) -> void:
	muted = m
	_target_master = 0.0 if muted else 0.72


func toggle_muted() -> void:
	set_muted(not muted)


func tone(o: Dictionary) -> void:
	if _playback == null or muted:
		return
	_voice_list.append(ToneVoice.new(o, SAMPLE_RATE))


func noise(o: Dictionary) -> void:
	if _playback == null or muted:
		return
	_voice_list.append(NoiseVoice.new(o, SAMPLE_RATE))


# ---------- эффекты (точный порт Audio.cs) ----------

func jump() -> void:
	tone({"type": "triangle", "freq": 300.0, "freq2": 540.0, "dur": 0.14, "gain": 0.10})
	noise({"freq": 1600.0, "dur": 0.09, "gain": 0.035, "type": "highpass"})


func land(force: float) -> void:
	var f: float = clampf(force, 0.0, 1.0)
	tone({"type": "sine", "freq": 110.0, "freq2": 55.0, "dur": 0.11, "gain": 0.12 * f})
	noise({"freq": 700.0, "dur": 0.08, "gain": 0.05 * f, "type": "lowpass"})


func dash() -> void:
	noise({"freq": 900.0, "freq2": 2800.0, "dur": 0.18, "gain": 0.10, "q": 0.8})
	tone({"type": "sawtooth", "freq": 160.0, "freq2": 90.0, "dur": 0.14, "gain": 0.04, "filter": 900.0})


func slash(step: int) -> void:
	var p: int = clampi(step, 1, 3)
	noise({"freq": 2400.0 - p * 260.0, "freq2": 700.0, "dur": 0.1 + p * 0.015, "gain": 0.08, "q": 1.2})
	tone({"type": "triangle", "freq": 700.0 - p * 90.0, "freq2": 220.0, "dur": 0.09, "gain": 0.05})


func hit(heavy: bool) -> void:
	var h: float = 1.25 if heavy else 1.0
	tone({"type": "square", "freq": 150.0 / h, "freq2": 60.0, "dur": 0.08, "gain": 0.10, "filter": 700.0})
	tone({"type": "sine", "freq": 90.0, "freq2": 44.0, "dur": 0.12, "gain": 0.14 * h})
	noise({"freq": 1500.0, "freq2": 500.0, "dur": 0.07, "gain": 0.08})
	tone({"type": "sine", "freq": 1250.0, "freq2": 900.0, "dur": 0.05, "gain": 0.03})


func kill() -> void:
	tone({"type": "sawtooth", "freq": 320.0, "freq2": 60.0, "dur": 0.42, "gain": 0.08, "filter": 1100.0})
	noise({"freq": 1800.0, "freq2": 300.0, "dur": 0.35, "gain": 0.09})
	tone({"type": "sine", "freq": 70.0, "freq2": 38.0, "dur": 0.35, "gain": 0.12})


func hurt() -> void:
	tone({"type": "sawtooth", "freq": 240.0, "freq2": 70.0, "dur": 0.28, "gain": 0.14, "filter": 800.0})
	tone({"type": "square", "freq": 120.0, "freq2": 50.0, "dur": 0.18, "gain": 0.07})
	noise({"freq": 900.0, "freq2": 200.0, "dur": 0.22, "gain": 0.10})


func heal() -> void:
	var notes: Array = [523.25, 659.25, 783.99]
	for i in range(notes.size()):
		tone({"type": "sine", "freq": notes[i], "dur": 0.5, "gain": 0.055,
			"delay": i * 0.1, "attack": 0.02})
	noise({"freq": 3000.0, "dur": 0.4, "gain": 0.02, "type": "highpass"})


func heal_loop() -> void:
	tone({"type": "sine", "freq": 392.0, "freq2": 523.0, "dur": 0.3, "gain": 0.02})


func death() -> void:
	tone({"type": "sawtooth", "freq": 200.0, "freq2": 30.0, "dur": 1.1, "gain": 0.13, "filter": 600.0})
	tone({"type": "sine", "freq": 90.0, "freq2": 28.0, "dur": 1.3, "gain": 0.12})
	noise({"freq": 1200.0, "freq2": 90.0, "dur": 1.0, "gain": 0.08, "type": "lowpass"})


func deflect() -> void:
	tone({"type": "triangle", "freq": 1400.0, "freq2": 2100.0, "dur": 0.09, "gain": 0.07})
	noise({"freq": 3200.0, "dur": 0.06, "gain": 0.05, "type": "highpass"})


func spawn() -> void:
	noise({"freq": 200.0, "freq2": 1400.0, "dur": 0.3, "gain": 0.05, "q": 0.7})
	tone({"type": "sine", "freq": 120.0, "freq2": 300.0, "dur": 0.3, "gain": 0.04})


func ui() -> void:
	tone({"type": "triangle", "freq": 900.0, "freq2": 700.0, "dur": 0.045, "gain": 0.04})


func ui_confirm() -> void:
	tone({"type": "triangle", "freq": 520.0, "freq2": 840.0, "dur": 0.12, "gain": 0.06})


# ---------- синтез ----------

static func _envelope(t: float, dur: float, peak: float, attack: float) -> float:
	if t < 0.0:
		return 0.0
	if t < attack:
		return peak * (t / maxf(0.0001, attack))
	var rest: float = maxf(0.001, dur - attack)
	var k := 9.21034 / rest
	return peak * exp(-k * (t - attack))


static func _fgen(seed_: int) -> int:
	# xorshift32
	var x: int = seed_ & 0xFFFFFFFF
	x = x ^ ((x << 13) & 0xFFFFFFFF)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & 0xFFFFFFFF)
	return x & 0xFFFFFFFF


class ToneVoice extends RefCounted:
	var type: String
	var f0: float
	var f1: float
	var dur: float
	var peak: float
	var attack: float
	var filter_: float
	var delay_samples := 0
	var t := 0.0
	var phase := 0.0
	var lp := 0.0

	func _init(o: Dictionary, sr: int) -> void:
		type = o.get("type", "sine")
		f0 = maxf(20.0, float(o.get("freq", 220.0)))
		f1 = maxf(20.0, float(o.get("freq2", f0)))
		dur = float(o.get("dur", 0.2))
		peak = float(o.get("gain", 0.16))
		attack = float(o.get("attack", 0.005))
		filter_ = float(o.get("filter", 0.0))
		delay_samples = int(float(o.get("delay", 0.0)) * sr)

	func finished() -> bool:
		return t >= dur

	func next(sr: int) -> float:
		if delay_samples > 0:
			delay_samples -= 1
			return 0.0
		var tt := t
		if tt >= dur:
			return 0.0
		var u := tt / dur
		var f := f0 * pow(f1 / f0, u)
		phase += f / sr
		if phase >= 1.0:
			phase -= floor(phase)
		var s: float
		match type:
			"triangle":
				s = 1.0 - 4.0 * absf(phase - 0.5)
			"sawtooth":
				s = phase * 2.0 - 1.0
			"square":
				s = 1.0 if phase < 0.5 else -1.0
			_:
				s = sin(phase * TAU)
		if filter_ > 0.0:
			var a := 1.0 - exp(-TAU * filter_ / sr)
			lp += (s - lp) * a
			s = lp
		t += 1.0 / sr
		return s * SNDCore._envelope(tt, dur, peak, attack)


class NoiseVoice extends RefCounted:
	var f0: float
	var f1: float
	var dur: float
	var peak: float
	var attack: float
	var rate: float
	var type: String
	var delay_samples := 0
	var t := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var seed_: int = 1

	func _init(o: Dictionary, sr: int) -> void:
		f0 = float(o.get("freq", 1200.0))
		f1 = float(o.get("freq2", f0))
		dur = float(o.get("dur", 0.2))
		peak = float(o.get("gain", 0.12))
		attack = float(o.get("attack", 0.004))
		rate = float(o.get("rate", 1.0))
		type = o.get("type", "bandpass")
		delay_samples = int(float(o.get("delay", 0.0)) * sr)
		seed_ = randi_range(1, 2147483647)

	func finished() -> bool:
		return t >= dur

	func next(sr: int) -> float:
		if delay_samples > 0:
			delay_samples -= 1
			return 0.0
		var tt := t
		if tt >= dur:
			return 0.0
		var u := tt / dur
		var f := f0 * pow(maxf(40.0, f1) / maxf(40.0, f0), u)
		seed_ = SNDCore._fgen(seed_)
		var n := float(seed_) / 4294967296.0 * 2.0 - 1.0
		var a := 1.0 - exp(-TAU * clampf(f, 20.0, sr * 0.45) / sr)
		lp += (n - lp) * a
		lp2 += (lp - lp2) * a
		var s: float
		match type:
			"lowpass":
				s = lp
			"highpass":
				s = n - lp
			_:
				s = lp - lp2
		t += (1.0 / sr) * maxf(0.1, rate)
		return s * SNDCore._envelope(tt, dur, peak, attack)


# ---------- mixer

func _mix_frame() -> float:
	var mix := 0.0
	for i in range(_voice_list.size() - 1, -1, -1):
		var v = _voice_list[i]
		mix += v.next(SAMPLE_RATE)
		if v.finished():
			_voice_list.remove_at(i)

	if _ambient_on:
		_ambient_t += 1.0 / SAMPLE_RATE
		var drone: float = sin(_ambient_t * TAU * 55.0) * 0.5 \
			+ sin(_ambient_t * TAU * 82.5) * 0.24 \
			+ sin(_ambient_t * TAU * 110.2) * 0.08
		var lfo: float = 0.05 + sin(_ambient_t * TAU * 0.07) * 0.02
		mix += drone * lfo * 0.55

		_seed = SNDCore._fgen(_seed)
		var n := float(_seed) / 4294967296.0 * 2.0 - 1.0
		var a := 1.0 - exp(-TAU * 420.0 / SAMPLE_RATE)
		_wind_lp += (n - _wind_lp) * a
		var wlfo: float = 0.018 + sin(_ambient_t * TAU * 0.045) * 0.008
		mix += _wind_lp * wlfo * 0.55

	_master += (_target_master - _master) * 0.002
	return tanh(mix * 1.1) * _master


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var avail := _playback.get_frames_available()
	if avail <= 0:
		return
	# не вырабатываем больше полутора секунд за раз (защита от зависаний)
	var total := mini(avail, SAMPLE_RATE * 3 / 2)
	while total > 0:
		var n := mini(total, 1024)
		for i in range(n):
			var v := _mix_frame()
			_playback.push_frame(Vector2(v, v))
		total -= n

