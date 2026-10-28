class_name INKCtl
extends Node

## Полный порт Core/Input.cs — клавиатура + геймпад + тач.
## update(dt) вызывается ОДИН раз за кадр (как в оригинале), чтобы
## все подшаги симуляции внутри кадра видели одинаковые edges.

const ACTIONS := [
	"left", "right", "up", "down",
	"jump", "attack", "dash", "heal",
	"pause", "restart", "help", "hitboxes", "mute",
	"fullscreen", "screenshot",
]

# Действия, доступные для переназначения (в порядке экрана настроек).
const BINDABLE := [
	"left", "right", "up", "down",
	"jump", "attack", "dash", "heal",
	"pause", "restart", "help", "hitboxes", "mute",
	"fullscreen", "screenshot",
]

# Значения по умолчанию. KEYBOARD — Godot-коды клавиш (как в Input.cs),
# PAD — слоты XInput (0=A, 1=B, 2=X, 3=Y, 4=LB, 5=RB, 6=LT, 7=RT,
# 8=BACK, 9=START, 10=LS, 11=RS, 12..15=D-pad).
const DEFAULT_KEYBOARD := {
	"left": [KEY_A, KEY_LEFT],
	"right": [KEY_D, KEY_RIGHT],
	"up": [KEY_W, KEY_UP],
	"down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE, KEY_Z],
	"attack": [KEY_J, KEY_X],
	"dash": [KEY_K, KEY_C, KEY_SHIFT],
	"heal": [KEY_L, KEY_V],
	"pause": [KEY_ESCAPE],
	"restart": [KEY_R],
	"help": [KEY_F1],
	"hitboxes": [KEY_F2, KEY_F],
	"mute": [KEY_M],
	"fullscreen": [KEY_F11],
	"screenshot": [KEY_F12],
}

const DEFAULT_PAD := {
	"jump": [0],
	"attack": [2, 5],
	"dash": [1, 4],
	"heal": [3],
	"pause": [9],
	"restart": [8],
}

const PAD_LABELS := [
	"A", "B", "X", "Y", "LB", "RB", "LT", "RT",
	"BACK", "START", "LS", "RS", "↑", "↓", "←", "→",
]

# XInput-индекс -> Godot JoyButton / ось триггера
const PAD_BUTTON_JOY := [0, 1, 2, 3, 9, 10, -1, -2, 4, 6, 7, 8, 11, 12, 13, 14]
# -1 = левый триггер (ось 4), -2 = правый триггер (ось 5)

const DEADZONE := 0.32

var device := "keyboard"
var disabled := false
var vibration_enabled := true
var pad_connected := false
var pad_id := ""
var pad_buttons: Array = []
var pad_axes := [0.0, 0.0]
var move_x := 0.0
var move_y := 0.0

# Текущие назначения (заполняются reset_bindings и загружаются из settings.cfg).
var keyboard := {}
var pad_map := {}

var state := {}
var prev := {}
var edge := {}
var _repeat := {}
var _prev_enter := false
var _edge_enter := false

# тач-управление (наполняется из game.gd)
var touch_down := {}
var _touch_refs := {}
var _touch_edges := {}

# плавающий тач-стик (аналоговый)
var stick_on := false
var stick_x := 0.0
var stick_y := 0.0
var _hold_t := {}


func _ready() -> void:
	for a in ACTIONS:
		state[a] = false
		prev[a] = false
		edge[a] = false
		_repeat[a] = -1.0
	pad_buttons = []
	for i in range(16):
		pad_buttons.append(false)
	reset_bindings()


## Сбрасывает назначения клавиш и кнопок к значениям по умолчанию.
func reset_bindings() -> void:
	keyboard.clear()
	pad_map.clear()
	for a in ACTIONS:
		keyboard[a] = DEFAULT_KEYBOARD.get(a, []).duplicate()
		pad_map[a] = DEFAULT_PAD.get(a, []).duplicate()


## Клавиша-компенсация для действия, у которого забрали последнюю клавишу.
## Esc не отдаём никогда (она всегда «назад»), уже занятые клавиши — тоже.
func _spare_key(target: String, old: Array, taken: int) -> Array:
	for k in old:
		var c := int(k)
		if c != KEY_ESCAPE and c != taken and not _key_used(c, target):
			return [c]
	for k in DEFAULT_KEYBOARD.get(target, []):
		var c := int(k)
		if c != KEY_ESCAPE and c != taken and not _key_used(c, target):
			return [c]
	return []


func _key_used(code: int, except: String) -> bool:
	for a in keyboard.keys():
		if a == except:
			continue
		var arr: Array = keyboard[a]
		if arr.has(code):
			return true
	return false


## Назначает клавишу действию. Код забирается у других действий, чтобы одна
## клавиша не срабатывала дважды; если у них это была единственная клавиша,
## они получают свободную клавишу (сначала старую клавишу изменяемого действия).
## Esc зарезервирована за паузой (она же «назад» в меню) и не отдаётся другим
## действиям. Возвращает false, если назначить нельзя.
func set_key(action: String, code: int) -> bool:
	if not keyboard.has(action) or code <= 0:
		return false
	if code == KEY_ESCAPE and action != "pause":
		return false
	var old: Array = keyboard[action].duplicate()
	for a in keyboard.keys():
		if a == action:
			continue
		var arr: Array = keyboard[a]
		if not arr.has(code):
			continue
		var rest := arr.filter(func(k): return int(k) != code)
		keyboard[a] = _spare_key(a, old, code) if rest.is_empty() else rest
	var next: Array = [code]
	# Esc навсегда остаётся клавишей паузы/назад, даже если паузу переназначили.
	if action == "pause" and code != KEY_ESCAPE:
		next.append(KEY_ESCAPE)
	keyboard[action] = next
	return true


## Назначает кнопку геймпада (слот XInput) действию.
func set_pad(action: String, slot: int) -> bool:
	if not pad_map.has(action) or slot < 0 or slot >= PAD_LABELS.size():
		return false
	# Движение на геймпаде всегда стик / D-pad.
	if action in ["left", "right", "up", "down"]:
		return false
	var old: Array = pad_map[action].duplicate()
	for a in pad_map.keys():
		if a == action:
			continue
		var arr: Array = pad_map[a]
		if not arr.has(slot):
			continue
		var rest := arr.filter(func(s): return int(s) != slot)
		pad_map[a] = [old[0]] if (rest.is_empty() and not old.is_empty()) else rest
	pad_map[action] = [slot]
	return true


## JoyButton -> слот XInput (или -1, если кнопка не поддерживается).
func slot_of_joy(button: int) -> int:
	return PAD_BUTTON_JOY.find(button)


func key_label(code: int) -> String:
	match code:
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_SPACE: return L10N.t("KEY_SPACE")
		KEY_ESCAPE: return "ESC"
		KEY_ENTER, KEY_KP_ENTER: return "ENTER"
		KEY_BACKSPACE: return "BACKSPACE"
		KEY_TAB: return "TAB"
		KEY_SHIFT: return "SHIFT"
		KEY_CTRL: return "CTRL"
		KEY_ALT: return "ALT"
	var s := OS.get_keycode_string(code)
	return s.to_upper() if s != "" else "?"


func pad_label(slot: int) -> String:
	if slot >= 0 and slot < PAD_LABELS.size():
		return PAD_LABELS[slot]
	return "—"


## Первая (основная) клавиша действия — для подсказок в интерфейсе.
func first_key_label(a: String) -> String:
	var arr: Array = keyboard.get(a, [])
	if arr.is_empty():
		return "—"
	return key_label(int(arr[0]))


## Подпись клавиатурного назначения действия (все клавиши через «/»).
func label_key(a: String) -> String:
	if a == "attack_up":
		a = "down"
	var arr: Array = keyboard.get(a, [])
	if arr.is_empty():
		return "—"
	var parts := PackedStringArray()
	for k in arr:
		parts.append(key_label(int(k)))
	return " / ".join(parts)


## Подпись движения: клавиши влево/вправо вперемешку, как в памятке.
func label_move() -> String:
	var l: Array = keyboard.get("left", [])
	var r: Array = keyboard.get("right", [])
	var parts := PackedStringArray()
	for i in range(maxi(l.size(), r.size())):
		if i < l.size():
			parts.append(key_label(int(l[i])))
		if i < r.size():
			parts.append(key_label(int(r[i])))
	return " / ".join(parts) if not parts.is_empty() else "—"


## Подпись геймпад-назначения действия.
func label_pad(a: String) -> String:
	if a == "attack_up":
		a = "down"
	if a in ["left", "right", "up", "down"]:
		return L10N.t("KEY_STICK")
	var arr: Array = pad_map.get(a, [])
	if arr.is_empty():
		return "—"
	var parts := PackedStringArray()
	for s in arr:
		parts.append(pad_label(int(s)))
	return " / ".join(parts)


func touch_enter(a: String) -> void:
	_touch_refs[a] = int(_touch_refs.get(a, 0)) + 1
	touch_down[a] = true


func touch_exit(a: String) -> void:
	var c := int(_touch_refs.get(a, 0)) - 1
	_touch_refs[a] = maxi(0, c)
	if c <= 0:
		touch_down[a] = false
		touch_down.erase(a)


func touch_tap(a: String) -> void:
	_touch_edges[a] = true


func stick_start() -> void:
	stick_on = true
	stick_x = 0.0
	stick_y = 0.0


func stick_move(x: float, y: float) -> void:
	stick_x = clampf(x, -1.0, 1.0)
	stick_y = clampf(y, -1.0, 1.0)


func stick_end() -> void:
	stick_on = false
	stick_x = 0.0
	stick_y = 0.0


func down(a: String) -> bool:
	return state.get(a, false)


func pressed(a: String) -> bool:
	return edge.get(a, false)


func axis_x() -> float:
	return move_x


func axis_y() -> float:
	return move_y


func confirm() -> bool:
	return pressed("jump") or pressed("attack") or _edge_enter


func rumble(strong: float, weak: float, ms: int) -> void:
	if not vibration_enabled:
		return
	var s := clampf(strong, 0.0, 1.0)
	var w := clampf(weak, 0.0, 1.0)
	var dur := float(ms) / 1000.0
	# Godot: (device, weak_magnitude, strong_magnitude, duration)
	Input.start_joy_vibration(0, w, s, dur)
	Input.vibrate_handheld(ms)


func snapshot() -> Dictionary:
	return {
		"connected": pad_connected,
		"id": pad_id,
		"buttons": pad_buttons.duplicate(),
		"axes": pad_axes.duplicate(),
	}


func label_of(a: String) -> String:
	if a == "attack_up":
		return label_of("down")
	if device == "touch":
		var touch := {
			"left": L10N.t("KEY_STICK"), "right": L10N.t("KEY_STICK"), "up": L10N.t("KEY_STICK"), "down": L10N.t("KEY_STICK"),
			"jump": "A", "attack": "X", "dash": "B", "heal": "Y",
			"pause": "Ⅱ", "restart": "—", "help": "—", "hitboxes": "—", "mute": "—",
			"fullscreen": "—", "screenshot": "—",
		}
		return touch.get(a, a)
	if device == "gamepad":
		return label_pad(a)
	return label_key(a)


func _update_pad() -> void:
	var connected := Input.get_connected_joypads().size() > 0
	if connected:
		pad_connected = true
		pad_id = L10N.t("PAD_NAME")
		var reused := []
		for i in range(16):
			reused.append(false)
		var joy := 0
		var used := false
		for i in range(16):
			var code: int = PAD_BUTTON_JOY[i]
			var v := false
			if code >= 0:
				v = Input.is_joy_button_pressed(joy, code)
			elif code == -1:
				v = Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT) > 0.4
			elif code == -2:
				v = Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4
			reused[i] = v
			if v:
				used = true
		pad_buttons = reused
		var ax_x := Input.get_joy_axis(joy, JOY_AXIS_LEFT_X)
		var ax_y := Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y)
		pad_axes = [ax_x, ax_y]
		if absf(ax_x) > 0.45 or absf(ax_y) > 0.45:
			used = true
		if used:
			device = "gamepad"
	else:
		if pad_connected:
			pad_connected = false
			pad_id = ""
		pad_buttons = []
		for i in range(16):
			pad_buttons.append(false)
		pad_axes = [0.0, 0.0]


## Нажата ли клавиша: проверяем и логический, и физический код, чтобы
## назначения работали в любой раскладке.
func _key_down(code: int) -> bool:
	return Input.is_key_pressed(code) or Input.is_physical_key_pressed(code)


func _key_axis(neg: String, pos: String) -> float:
	var v := 0.0
	for k in keyboard.get(pos, []):
		if _key_down(int(k)):
			v += 1.0
			break
	for k in keyboard.get(neg, []):
		if _key_down(int(k)):
			v -= 1.0
			break
	return v


func update(dt: float) -> void:
	_update_pad()

	var enter_down: bool = Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	_edge_enter = enter_down and not _prev_enter
	_prev_enter = enter_down

	if disabled:
		for a in ACTIONS:
			state[a] = false
			prev[a] = false
			edge[a] = false
		move_x = 0.0
		move_y = 0.0
		stick_on = false
		stick_x = 0.0
		stick_y = 0.0
		_touch_edges.clear()
		_edge_enter = false
		return

	var kx: float = _key_axis("left", "right")
	var ky: float = _key_axis("up", "down")

	var sx: float = pad_axes[0]
	var sy: float = pad_axes[1]
	sx = 0.0 if absf(sx) < DEADZONE else signf(sx) * ((absf(sx) - DEADZONE) / (1.0 - DEADZONE))
	sy = 0.0 if absf(sy) < DEADZONE else signf(sy) * ((absf(sy) - DEADZONE) / (1.0 - DEADZONE))

	var dpad_x: float = (1.0 if pad_buttons[15] else 0.0) - (1.0 if pad_buttons[14] else 0.0)
	var dpad_y: float = (1.0 if pad_buttons[13] else 0.0) - (1.0 if pad_buttons[12] else 0.0)

	# тач-зоны (двоичные) + плавающий стик (аналоговый)
	var tpx: float = (1.0 if touch_down.get("right", false) else 0.0) \
		- (1.0 if touch_down.get("left", false) else 0.0)
	var tpy: float = (1.0 if touch_down.get("down", false) else 0.0) \
		- (1.0 if touch_down.get("up", false) else 0.0)
	var stx: float = stick_x if stick_on else 0.0
	var sty: float = stick_y if stick_on else 0.0

	var mx: float = kx
	if absf(sx) > absf(mx):
		mx = sx
	if dpad_x != 0.0:
		mx = dpad_x
	if tpx != 0.0:
		mx = tpx
	elif stick_on and absf(stx) >= 0.12:
		mx = stx
	move_x = clampf(mx, -1.0, 1.0)

	if ky != 0.0:
		move_y = clampf(ky, -1.0, 1.0)
	elif dpad_y != 0.0:
		move_y = dpad_y
	elif absf(sy) > 0.55:
		move_y = signf(sy)
	elif tpy != 0.0:
		move_y = tpy
	elif stick_on and absf(sty) > 0.3:
		move_y = sty
	else:
		move_y = 0.0

	for a in ACTIONS:
		var d: bool = false
		var keys: Array = keyboard.get(a, [])
		for k in keys:
			if _key_down(int(k)):
				d = true
				break
		if not d:
			for bi in pad_map.get(a, []):
				if pad_buttons[int(bi)]:
					d = true
					break
		if not d and touch_down.get(a, false):
			d = true

		if a == "left":
			d = d or dpad_x < 0.0 or sx < -0.5 or tpx < 0.0 or (stick_on and stx < -0.35)
		elif a == "right":
			d = d or dpad_x > 0.0 or sx > 0.5 or tpx > 0.0 or (stick_on and stx > 0.35)
		elif a == "up":
			d = d or dpad_y < 0.0 or sy < -0.55 or tpy < 0.0 or (stick_on and sty < -0.6)
		elif a == "down":
			d = d or dpad_y > 0.0 or sy > 0.55 or tpy > 0.0 or (stick_on and sty > 0.6)

		prev[a] = state[a]
		state[a] = d
		edge[a] = d and not prev[a] or bool(_touch_edges.get(a, false))

	# тач: удержание X/B = серия (автоочередь атаки/рывка)
	for a in ["attack", "dash"]:
		var held_touch: bool = touch_down.get(a, false)
		var interval: float = 0.16 if a == "attack" else 0.25
		if held_touch and edge[a]:
			_hold_t[a] = 0.0
		elif held_touch and edge[a] == false and prev[a]:
			var ht: float = float(_hold_t.get(a, 0.0)) + dt
			if ht >= interval:
				ht = 0.0
				edge[a] = true
			_hold_t[a] = ht
		elif not held_touch:
			_hold_t[a] = 0.0

	for a in ["up", "down"]:
		if edge[a]:
			_repeat[a] = -0.38
		elif state[a]:
			_repeat[a] += dt
			if _repeat[a] >= 0.11:
				_repeat[a] = 0.0
				edge[a] = true
		else:
			_repeat[a] = -1.0

	_touch_edges.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		device = "keyboard"
		SND.unlock()
	elif event is InputEventJoypadButton and event.pressed:
		device = "gamepad"
		SND.unlock()
	elif event is InputEventScreenTouch and event.pressed:
		device = "touch"
		SND.unlock()
