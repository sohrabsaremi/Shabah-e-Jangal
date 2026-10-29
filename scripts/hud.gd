extends Control
 
const JOY_R := 90.0
const BTN_LABELS := {"attack": "ضربه", "jump": "پرش", "interact": "عمل", "eat": "خوردن"}
 
# values read by the player / main
var move_vec: Vector2 = Vector2.ZERO
var look_accum: Vector2 = Vector2.ZERO
var flag_attack: bool = false
var flag_jump: bool = false
var flag_interact: bool = false
var flag_eat: bool = false
 
# values written by main
var hp_frac: float = 1.0
var hunger_frac: float = 1.0
var thirst_frac: float = 1.0
var fatigue_frac: float = 0.0
var inv_text: String = ""
var day_text: String = ""
var time_frac: float = 0.0
var day_split: float = 0.6
var hint: String = ""
var msg_text: String = ""
var msg_time: float = 0.0
var flash: float = 0.0
var compass_on: bool = false
var compass_angle: float = 0.0
var dead_screen: bool = false
 
var joy_id: int = -1
var look_id: int = -1
var joy_center: Vector2 = Vector2.ZERO
var joy_pos: Vector2 = Vector2.ZERO
var btn_touch: Dictionary = {}
 
 
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
 
 
func show_msg(txt: String, secs: float) -> void:
	msg_text = txt
	msg_time = secs
 
 
func consume_look() -> Vector2:
	var v := look_accum
	look_accum = Vector2.ZERO
	return v
 
 
func consume_attack() -> bool:
	var v := flag_attack
	flag_attack = false
	return v
 
 
func consume_jump() -> bool:
	var v := flag_jump
	flag_jump = false
	return v
 
 
func consume_interact() -> bool:
	var v := flag_interact
	flag_interact = false
	return v
 
 
func consume_eat() -> bool:
	var v := flag_eat
	flag_eat = false
	return v
 
 
func _layout() -> Dictionary:
	var s := get_viewport_rect().size
	return {
		"attack": [Vector2(s.x - 130.0, s.y - 130.0), 78.0],
		"jump": [Vector2(s.x - 90.0, s.y - 300.0), 52.0],
		"interact": [Vector2(s.x - 300.0, s.y - 110.0), 62.0],
		"eat": [Vector2(s.x - 285.0, s.y - 250.0), 48.0],
	}
 
 
func _hit_button(pos: Vector2) -> String:
	var lay := _layout()
	for k in lay:
		var c: Vector2 = lay[k][0]
		var r: float = lay[k][1]
		if pos.distance_to(c) <= r + 14.0:
			return str(k)
	return ""
 
 
func _press(btn: String) -> void:
	match btn:
		"attack":
			flag_attack = true
		"jump":
			flag_jump = true
		"interact":
			flag_interact = true
		"eat":
			flag_eat = true
 
 
func _input(event: InputEvent) -> void:
	var w := get_viewport_rect().size.x
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		var idx: int = te.index
		if te.pressed:
			var b := _hit_button(te.position)
			if b != "":
				btn_touch[idx] = b
				_press(b)
			elif te.position.x < w * 0.45:
				if joy_id == -1:
					joy_id = idx
					joy_center = te.position
					joy_pos = te.position
					move_vec = Vector2.ZERO
			elif look_id == -1:
				look_id = idx
		else:
			if idx == joy_id:
				joy_id = -1
				move_vec = Vector2.ZERO
			elif idx == look_id:
				look_id = -1
			elif btn_touch.has(idx):
				btn_touch.erase(idx)
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		var idx2: int = de.index
		if idx2 == joy_id:
			var d: Vector2 = de.position - joy_center
			if d.length() > JOY_R:
				d = d.normalized() * JOY_R
			joy_pos = joy_center + d
			move_vec = d / JOY_R
		elif idx2 == look_id:
			look_accum += de.relative
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_SPACE:
					flag_jump = true
				KEY_F:
					flag_attack = true
				KEY_E:
					flag_interact = true
				KEY_Q:
					flag_eat = true
 
 
func _process(delta: float) -> void:
	msg_time = maxf(0.0, msg_time - delta)
	flash = maxf(0.0, flash - delta * 1.5)
	if joy_id == -1:
		# keyboard fallback for testing on a computer
		var kx := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
		var ky := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		move_vec = Vector2(kx, ky)
	queue_redraw()
 
 
func _bar(pos: Vector2, sz: Vector2, frac: float, col: Color, label: String, f: Font) -> void:
	draw_rect(Rect2(pos, sz), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(pos, Vector2(sz.x * clampf(frac, 0.0, 1.0), sz.y)), col)
	draw_rect(Rect2(pos, sz), Color(1, 1, 1, 0.5), false, 2.0)
	draw_string(f, pos + Vector2(8, sz.y - 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
 
 
func _draw() -> void:
	var s := get_viewport_rect().size
	var f: Font = ThemeDB.fallback_font
 
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.0, 0.0, flash * 0.5))
 
	# stat bars + inventory
	_bar(Vector2(24, 22), Vector2(260, 22), hp_frac, Color(0.8, 0.12, 0.12), "جان", f)
	_bar(Vector2(24, 52), Vector2(260, 18), hunger_frac, Color(0.9, 0.6, 0.1), "سیری", f)
	_bar(Vector2(24, 77), Vector2(260, 18), thirst_frac, Color(0.15, 0.55, 0.95), "آب", f)
	_bar(Vector2(24, 102), Vector2(260, 18), 1.0 - fatigue_frac, Color(0.55, 0.55, 0.75), "انرژی", f)
	draw_string(f, Vector2(24, 130), inv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
 
	# day counter + sun/moon timeline
	draw_string(f, Vector2(s.x - 264, 40), day_text, HORIZONTAL_ALIGNMENT_RIGHT, 240, 24, Color.WHITE)
	var a := Vector2(s.x - 264, 62)
	var b := Vector2(s.x - 24, 62)
	var m := a.lerp(b, day_split)
	draw_line(a, m, Color(1.0, 0.8, 0.3), 6.0)
	draw_line(m, b, Color(0.3, 0.4, 0.9), 6.0)
	draw_circle(a.lerp(b, clampf(time_frac, 0.0, 1.0)), 9.0, Color.WHITE)
 
	# compass to the cabin
	if compass_on:
		var c := Vector2(s.x * 0.5, 100)
		draw_set_transform(c, compass_angle, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -26), Vector2(16, 16), Vector2(0, 8), Vector2(-16, 16)]), Color(1.0, 0.85, 0.3, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(f, Vector2(c.x - 40, c.y + 44), "کلبه", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, Color(1.0, 0.9, 0.5))
 
	# joystick
	if joy_id != -1:
		draw_circle(joy_center, JOY_R, Color(1, 1, 1, 0.14))
		draw_arc(joy_center, JOY_R, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(joy_pos, 38.0, Color(1, 1, 1, 0.4))
	else:
		var hc := Vector2(170.0, s.y - 150.0)
		draw_arc(hc, JOY_R, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 3.0)
 
	# buttons
	var lay := _layout()
	var pressed_names: Array = btn_touch.values()
	for k in lay:
		var c2: Vector2 = lay[k][0]
		var r: float = lay[k][1]
		var is_down: bool = pressed_names.has(k)
		var active: bool = true
		if k == "interact":
			active = hint != ""
		draw_circle(c2, r, Color(0.05, 0.05, 0.05, 0.55 if not is_down else 0.8))
		var oc := Color(1, 1, 1, 0.55)
		if k == "interact" and active:
			oc = Color(1.0, 0.85, 0.3, 0.95)
		draw_arc(c2, r, 0.0, TAU, 40, oc, 3.0)
		var tc := Color(1, 1, 1, 0.95 if active else 0.4)
		draw_string(f, c2 + Vector2(-r, 8), BTN_LABELS[k], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, tc)
	if hint != "":
		var ic: Vector2 = lay["interact"][0]
		draw_string(f, Vector2(ic.x - 140, ic.y - 82), hint, HORIZONTAL_ALIGNMENT_CENTER, 280, 22, Color(1.0, 0.9, 0.4))
 
	# message
	if msg_time > 0.0:
		var al := clampf(msg_time, 0.0, 1.0)
		draw_string(f, Vector2(2, s.y * 0.22 + 2), msg_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, Color(0, 0, 0, al))
		draw_string(f, Vector2(0, s.y * 0.22), msg_text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, Color(1, 1, 1, al))
 
	if dead_screen:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(0, s.y * 0.5), "مُردی... در حال بازگشت به کلبه", HORIZONTAL_ALIGNMENT_CENTER, s.x, 36, Color(1, 0.4, 0.4))
