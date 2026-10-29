extends CharacterBody3D
 
const Models = preload("res://scripts/models.gd")
 
signal killed(pos: Vector3)
 
const GRAVITY := 24.0
 
var target
var cabin_pos: Vector3 = Vector3.ZERO
var hp: float = 50.0
var damage: float = 8.0
var speed: float = 3.4
var ring_phase: float = 0.0
 
var dead: bool = false
var attack_cd: float = 1.0
var attack_anim: float = 0.0
var stun: float = 0.0
var walk_phase: float = 0.0
var life: float = 0.0
 
var model: Node3D
var legL: Node3D
var legR: Node3D
var armL: Node3D
var armR: Node3D
 
 
func _ready() -> void:
	add_to_group("cannibals")
	collision_layer = 8
	collision_mask = 1 | 4
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
 
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	cs.shape = shape
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
 
	model = Models.build_cannibal(randf())
	var s := randf_range(0.95, 1.15)
	model.scale = Vector3(s, s, s)
	add_child(model)
	legL = model.get_meta("legL")
	legR = model.get_meta("legR")
	armL = model.get_meta("armL")
	armR = model.get_meta("armR")
	speed *= randf_range(0.9, 1.15)
 
 
func _physics_process(delta: float) -> void:
	if dead or target == null:
		return
	life += delta
	attack_cd = maxf(0.0, attack_cd - delta)
	attack_anim = maxf(0.0, attack_anim - delta)
	stun = maxf(0.0, stun - delta)
	velocity.y -= GRAVITY * delta
 
	var chasing: bool = (not target.in_cabin) and (not target.dead)
	var dest: Vector3
	if chasing:
		dest = target.global_position
	else:
		var a := ring_phase + life * 0.15
		dest = cabin_pos + Vector3(cos(a) * 7.0, 0.0, sin(a) * 7.0)
	var to := dest - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector3.ZERO
	if dist > 0.05:
		dir = to / dist
	var stop_dist := 1.35 if chasing else 0.6
 
	if stun > 0.0 or dist <= stop_dist:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	if dir.length() > 0.1 and stun <= 0.0:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 8.0, 0.0, 1.0))
	move_and_slide()
 
	if chasing and dist < 1.9 and attack_cd <= 0.0 and stun <= 0.0:
		attack_cd = 1.3
		attack_anim = 0.35
		target.take_damage(damage)
 
	var sp := Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.1)
	_animate(delta, clampf(sp, 0.0, 1.0))
 
 
func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead:
		return
	hp -= amount
	stun = 0.3
	var push := global_position - from_pos
	push.y = 0.0
	if push.length() > 0.01:
		push = push.normalized()
		velocity.x = push.x * 6.0
		velocity.z = push.z * 6.0
	if hp <= 0.0:
		_die()
 
 
func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	remove_from_group("cannibals")
	killed.emit(global_position)
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", PI / 2.0, 0.5)
	tw.tween_interval(3.0)
	tw.tween_callback(queue_free)
 
 
func _animate(delta: float, speed_frac: float) -> void:
	if speed_frac > 0.05:
		walk_phase += delta * 9.0 * speed_frac
	var amp := 0.8 * speed_frac
	var k := clampf(delta * 15.0, 0.0, 1.0)
	legL.rotation.x = lerpf(legL.rotation.x, sin(walk_phase) * amp, k)
	legR.rotation.x = lerpf(legR.rotation.x, -sin(walk_phase) * amp, k)
	armL.rotation.x = lerpf(armL.rotation.x, -sin(walk_phase) * amp * 0.6, k)
	var ar := 0.9 + sin(walk_phase) * amp * 0.3
	if attack_anim > 0.0:
		ar = 0.9 + 1.6 * sin((1.0 - attack_anim / 0.35) * PI)
	armR.rotation.x = lerpf(armR.rotation.x, ar, clampf(delta * 20.0, 0.0, 1.0))
