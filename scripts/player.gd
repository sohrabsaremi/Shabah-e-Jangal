extends CharacterBody3D
 
const Models = preload("res://scripts/models.gd")
 
signal died
 
const SPEED := 5.2
const GRAVITY := 24.0
const JUMP_V := 7.5
 
var hud
var cabin_pos: Vector3 = Vector3.ZERO
 
var max_hp: float = 100.0
var hp: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var fatigue: float = 0.0
var in_cabin: bool = false
var dead: bool = false
var weapon_damage: float = 10.0
var inv: Dictionary = {"wood": 0, "stone": 0, "fruit": 0, "meat": 0}
 
var yaw: float = 0.0
var pitch: float = -0.35
var model: Node3D
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var legL: Node3D
var legR: Node3D
var armL: Node3D
var armR: Node3D
var attack_cd: float = 0.0
var attack_anim: float = 0.0
var walk_phase: float = 0.0
var regen_delay: float = 0.0
 
 
func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 8
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
 
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
 
	model = Models.build_hero()
	add_child(model)
	legL = model.get_meta("legL")
	legR = model.get_meta("legR")
	armL = model.get_meta("armL")
	armR = model.get_meta("armR")
 
	pivot = Node3D.new()
	pivot.top_level = true
	add_child(pivot)
	pivot.global_position = global_position + Vector3(0, 1.6, 0)
 
	arm = SpringArm3D.new()
	arm.spring_length = 5.2
	arm.margin = 0.3
	var ball := SphereShape3D.new()
	ball.radius = 0.3
	arm.shape = ball
	arm.collision_mask = 1
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
 
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 260.0
	arm.add_child(cam)
	cam.current = true
 
 
func _process(delta: float) -> void:
	if pivot == null:
		return
	pivot.global_position = pivot.global_position.lerp(global_position + Vector3(0, 1.6, 0), clampf(delta * 14.0, 0.0, 1.0))
	pivot.rotation = Vector3(pitch, yaw, 0.0)
 
 
func _physics_process(delta: float) -> void:
	if hud == null:
		return
	attack_cd = maxf(0.0, attack_cd - delta)
	attack_anim = maxf(0.0, attack_anim - delta)
 
	var look: Vector2 = hud.consume_look()
	var want_attack: bool = hud.consume_attack()
	var want_jump: bool = hud.consume_jump()
 
	if dead:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
 
	yaw -= look.x * 0.006
	pitch = clampf(pitch - look.y * 0.005, -1.2, 0.2)
 
	var mv: Vector2 = hud.move_vec
	if mv.length() > 1.0:
		mv = mv.normalized()
	var dir := Basis(Vector3.UP, yaw) * Vector3(mv.x, 0.0, mv.y)
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump:
		velocity.y = JUMP_V
	if mv.length() > 0.1:
		var target_ang := atan2(-dir.x, -dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_ang, clampf(delta * 12.0, 0.0, 1.0))
	move_and_slide()
 
	if want_attack and attack_cd <= 0.0:
		_attack()
 
	var rel := global_position - cabin_pos
	in_cabin = absf(rel.x) < 2.75 and absf(rel.z) < 2.3 and rel.y < 3.0
 
	_survival(delta)
	var sp := Vector2(velocity.x, velocity.z).length() / SPEED
	_animate(delta, clampf(sp, 0.0, 1.0))
 
 
func _survival(delta: float) -> void:
	hunger = maxf(0.0, hunger - 0.22 * delta)
	thirst = maxf(0.0, thirst - 0.34 * delta)
	fatigue = minf(100.0, fatigue + (0.12 if velocity.length() > 0.5 else 0.045) * delta)
	if in_cabin and not dead:
		fatigue = maxf(0.0, fatigue - 1.2 * delta)
	regen_delay = maxf(0.0, regen_delay - delta)
	if hunger <= 0.0 or thirst <= 0.0:
		hp -= (1.5 if hunger <= 0.0 else 2.2) * delta
		if hp <= 0.0:
			_die()
	elif fatigue >= 100.0:
		hp -= 0.45 * delta
		if hp <= 0.0:
			_die()
	elif hunger > 40.0 and regen_delay <= 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + 1.0 * delta)
 
 
func _attack() -> void:
	attack_cd = 0.55
	attack_anim = 0.3
	var fwd := -model.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for e in get_tree().get_nodes_in_group("cannibals"):
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < 2.4 and d > 0.001 and fwd.dot(to / d) > 0.25:
			e.take_damage(weapon_damage, global_position)
 
 
func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	regen_delay = 6.0
	hud.flash = 0.5
	if hp <= 0.0:
		_die()
 
 
func _die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", PI / 2.0, 0.5)
	died.emit()
 
 
func respawn(pos: Vector3) -> void:
	dead = false
	hp = 60.0
	hunger = maxf(hunger, 50.0)
	thirst = maxf(thirst, 45.0)
	fatigue = minf(fatigue, 55.0)
	global_position = pos
	velocity = Vector3.ZERO
	model.rotation = Vector3.ZERO
 
 
func drink_water() -> void:
	thirst = minf(100.0, thirst + 55.0)
	fatigue = maxf(0.0, fatigue - 5.0)
 
func eat() -> bool:
	if inv["fruit"] > 0:
		inv["fruit"] -= 1
		hunger = minf(100.0, hunger + 20.0)
		hp = minf(max_hp, hp + 4.0)
		return true
	return false
 
 
func _animate(delta: float, speed_frac: float) -> void:
	if speed_frac > 0.05:
		walk_phase += delta * 11.0 * speed_frac
	var amp := 0.85 * speed_frac
	var k := clampf(delta * 15.0, 0.0, 1.0)
	legL.rotation.x = lerpf(legL.rotation.x, sin(walk_phase) * amp, k)
	legR.rotation.x = lerpf(legR.rotation.x, -sin(walk_phase) * amp, k)
	armL.rotation.x = lerpf(armL.rotation.x, -sin(walk_phase) * amp * 0.7, k)
	var ar := sin(walk_phase) * amp * 0.7
	if attack_anim > 0.0:
		ar = 2.3 * sin((1.0 - attack_anim / 0.3) * PI)
	armR.rotation.x = lerpf(armR.rotation.x, ar, clampf(delta * 25.0, 0.0, 1.0))
