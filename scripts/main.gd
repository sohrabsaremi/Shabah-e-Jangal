extends Node3D

const Models = preload("res://scripts/models.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CannibalScript = preload("res://scripts/cannibal.gd")
const HudScript = preload("res://scripts/hud.gd")
const WorldSystemsScript = preload("res://scripts/world_systems.gd")

const DAY_SECONDS := 300.0
const DAY_FRAC := 0.6
const SPAWN_T := 0.66
const TREE_COUNT := 260
const ROCK_COUNT := 70
const BUSH_COUNT := 55
const BED_OFFSET := Vector3(-2.2, 0.0, -1.0)

var noise := FastNoiseLite.new()
var t: float = 0.05
var day_count: int = 1
var game_time: float = 0.0
var night_amt: float = 0.0

var player
var hud
var world_systems
var cabin: Node3D
var cabin_pos := Vector3.ZERO
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var window_mat: StandardMaterial3D
var lamp: OmniLight3D
var fire_light: OmniLight3D

var night_spawned: bool = false
var dusk_warned: bool = false
var spawn_left: int = 0
var spawn_timer: float = 0.0
var respawn_timer: float = -1.0
var scan_timer: float = 0.0
var ctx: String = ""
var ctx_index: int = -1

var tree_pos: Array[Vector3] = []
var tree_ready: Array[float] = []
var rock_pos: Array[Vector3] = []
var rock_ready: Array[float] = []
var bush_pos: Array[Vector3] = []
var bush_ready: Array[float] = []
var bush_hidden: Array[bool] = []
var berry_mm: MultiMesh
var berry_xf: Array[Transform3D] = []


func _ready() -> void:
	randomize()

	noise.seed = 1337
	noise.frequency = 0.012
	noise.fractal_octaves = 3

	_setup_environment()
	_build_terrain()
	_build_river()
	_build_forest()
	_build_cabin()
	_build_hud()
	_spawn_player()

	world_systems = Node3D.new()
	world_systems.name = "WorldSystems"
	world_systems.set_script(WorldSystemsScript)
	add_child(world_systems)
	world_systems.setup(self)

	hud.show_msg("به جنگل خوش آمدی! پیش از غروب منابع جمع کن.", 6.0)
	_update_daynight()


# ---------------------------------------------------------
# جهان و زمین

func height_at(x: float, z: float) -> float:
	# دره‌ی رودخانه
	if absf(x - 26.0) < 3.2 and absf(z) < 72.0:
		return -0.45

	var d := Vector2(x, z).length()
	var h := noise.get_noise_2d(x, z) * 9.0
	h *= smoothstep(12.0, 35.0, d)
	h += smoothstep(82.0, 116.0, d) * 40.0

	return h


func _dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _build_river() -> void:
	var water := MeshInstance3D.new()
	water.name = "RiverWater"

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(5.8, 144.0)
	water.mesh = mesh
	water.position = Vector3(26.0, -0.20, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.34, 0.48, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.12
	mat.roughness = 0.22
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	water.material_override = mat
	add_child(water)


func _setup_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()

	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	env.glow_enabled = true
	env.glow_intensity = 0.35

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	env.fog_enabled = true
	env.fog_density = 0.010

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.0
	moon.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
	add_child(moon)


func _ground_color(avg: float, pos: Vector3) -> Color:
	var n := noise.get_noise_2d(pos.x * 3.1, pos.z * 3.1) * 0.5 + 0.5

	var c := Color(0.20, 0.38, 0.14).lerp(
		Color(0.30, 0.46, 0.16),
		n
	)

	var d := Vector2(pos.x, pos.z).length()

	if d < 9.0:
		c = Color(0.36, 0.28, 0.18).lerp(
			c,
			smoothstep(5.0, 9.0, d)
		)

	if avg > 7.0:
		c = c.lerp(
			Color(0.42, 0.41, 0.40),
			clampf((avg - 7.0) / 6.0, 0.0, 1.0)
		)

	if avg > 28.0:
		c = c.lerp(
			Color(0.92, 0.94, 0.97),
			clampf((avg - 28.0) / 6.0, 0.0, 1.0)
		)

	return c


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var col := _ground_color(
		(a.y + b.y + c.y) / 3.0,
		(a + b + c) / 3.0
	)

	st.set_color(col)
	st.add_vertex(a)

	st.set_color(col)
	st.add_vertex(b)

	st.set_color(col)
	st.add_vertex(c)


func _build_terrain() -> void:
	var cells := 110
	var world_size := 240.0
	var step := world_size / cells

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in cells:
		for j in cells:
			var x0 := -world_size * 0.5 + i * step
			var z0 := -world_size * 0.5 + j * step

			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(
				x0 + step,
				height_at(x0 + step, z0),
				z0
			)
			var p01 := Vector3(
				x0,
				height_at(x0, z0 + step),
				z0 + step
			)
			var p11 := Vector3(
				x0 + step,
				height_at(x0 + step, z0 + step),
				z0 + step
			)

			_tri(st, p00, p10, p01)
			_tri(st, p10, p11, p01)

	st.generate_normals()
	var mesh := st.commit()

	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	add_child(mi)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape

	body.add_child(cs)
	add_child(body)


func _make_multimesh(
	mesh: Mesh,
	material: Material,
	xforms: Array,
	colors: Array,
	cast_shadow: bool = true
) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()

	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

		if colors.size() > 0:
			mm.set_instance_color(i, colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material

	if not cast_shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mmi)
	return mmi


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029

	var solid := StaticBody3D.new()
	add_child(solid)

	# درخت‌ها
	var trunk_x: Array[Transform3D] = []
	var leaf_x: Array[Transform3D] = []
	var leaf_c: Array[Color] = []

	var tries := 0

	while tree_pos.size() < TREE_COUNT and tries < 6000:
		tries += 1

		var a := rng.randf() * TAU
		var r := 15.0 + sqrt(rng.randf()) * 85.0
		var x := cos(a) * r
		var z := sin(a) * r
		var y := height_at(x, z)

		if y > 8.5:
			continue

		var ok := true

		for q in tree_pos:
			if absf(q.x - x) < 3.4 and absf(q.z - z) < 3.4:
				ok = false
				break

		if not ok:
			continue

		var s := rng.randf_range(0.8, 1.5)

		var bs := Basis(
			Vector3.UP,
			rng.randf() * TAU
		).scaled(
			Vector3(
				s,
				s * rng.randf_range(0.9, 1.25),
				s
			)
		)

		var xf := Transform3D(
			bs,
			Vector3(x, y - 0.15, z)
		)

		trunk_x.append(xf)
		leaf_x.append(xf)

		leaf_c.append(
			Color(0.10, 0.32, 0.12).lerp(
				Color(0.22, 0.45, 0.16),
				rng.randf()
			)
		)

		tree_pos.append(Vector3(x, y, z))
		tree_ready.append(0.0)

		var cs := CollisionShape3D.new()
		var shp := CylinderShape3D.new()
		shp.radius = 0.4 * s
		shp.height = 4.0
		cs.shape = shp
		cs.position = Vector3(x, y + 2.0, z)
		solid.add_child(cs)

	_make_multimesh(
		Models.tree_trunk_mesh(),
		Models.mat(Color(0.30, 0.19, 0.10), 0.95),
		trunk_x,
		[]
	)

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 0.95

	_make_multimesh(
		Models.tree_leaf_mesh(),
		leaf_mat,
		leaf_x,
		leaf_c
	)

	# سنگ‌ها
	var rock_x: Array[Transform3D] = []
	var rock_c: Array[Color] = []
	var rock_tries := 0

	while rock_pos.size() < ROCK_COUNT and rock_tries < 2000:
		rock_tries += 1

		var a2 := rng.randf() * TAU
		var r2 := 10.0 + sqrt(rng.randf()) * 95.0
		var x2 := cos(a2) * r2
		var z2 := sin(a2) * r2
		var y2 := height_at(x2, z2)

		if y2 > 12.0:
			continue

		var sc := Vector3(
			rng.randf_range(0.8, 1.9),
			rng.randf_range(0.6, 1.3),
			rng.randf_range(0.8, 1.9)
		)

		var bs2 := Basis(
			Vector3.UP,
			rng.randf() * TAU
		).scaled(sc)

		rock_x.append(
			Transform3D(bs2, Vector3(x2, y2 - 0.1, z2))
		)

		rock_c.append(
			Color(0.38, 0.38, 0.40).lerp(
				Color(0.55, 0.53, 0.50),
				rng.randf()
			)
		)

		rock_pos.append(Vector3(x2, y2, z2))
		rock_ready.append(0.0)

		var rcs := CollisionShape3D.new()
		var rsh := SphereShape3D.new()
		rsh.radius = 0.7 * minf(sc.x, sc.z)
		rcs.shape = rsh
		rcs.position = Vector3(x2, y2 + 0.3, z2)
		solid.add_child(rcs)

	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.roughness = 1.0

	_make_multimesh(
		Models.rock_mesh(),
		rock_mat,
		rock_x,
		rock_c
	)

	# بوته‌های میوه
	var bush_x: Array[Transform3D] = []
	var bush_c: Array[Color] = []
	var bush_tries := 0

	while bush_pos.size() < BUSH_COUNT and bush_tries < 2000:
		bush_tries += 1

		var a3 := rng.randf() * TAU
		var r3 := 8.0 + sqrt(rng.randf()) * 88.0
		var x3 := cos(a3) * r3
		var z3 := sin(a3) * r3
		var y3 := height_at(x3, z3)

		if y3 > 8.0:
			continue

		bush_x.append(
			Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU),
				Vector3(x3, y3 - 0.05, z3)
			)
		)

		bush_c.append(
			Color(0.14, 0.36, 0.12).lerp(
				Color(0.25, 0.50, 0.16),
				rng.randf()
			)
		)

		bush_pos.append(Vector3(x3, y3, z3))
		bush_ready.append(0.0)
		bush_hidden.append(false)

		for k in 4:
			var off := Vector3(
				rng.randf_range(-0.55, 0.55),
				rng.randf_range(0.45, 0.85),
				rng.randf_range(-0.55, 0.55)
			)

			berry_xf.append(
				Transform3D(
					Basis(),
					Vector3(x3, y3, z3) + off
				)
			)

	var bush_mat := StandardMaterial3D.new()
	bush_mat.vertex_color_use_as_albedo = true
	bush_mat.roughness = 1.0

	_make_multimesh(
		Models.bush_mesh(),
		bush_mat,
		bush_x,
		bush_c
	)

	var berries := _make_multimesh(
		Models.sph(0.075, 6, 3),
		Models.mat(Color(0.8, 0.05, 0.1), 0.4),
		berry_xf,
		[],
		false
	)

	berry_mm = berries.multimesh


func _set_berries_visible(i: int, vis: bool) -> void:
	for k in 4:
		var idx := i * 4 + k

		if vis:
			berry_mm.set_instance_transform(idx, berry_xf[idx])
		else:
			berry_mm.set_instance_transform(
				idx,
				Transform3D(
					Basis().scaled(Vector3(0.001, 0.001, 0.001)),
					berry_xf[idx].origin
				)
			)


func _build_cabin() -> void:
	cabin = Models.build_cabin()
	cabin.position = cabin_pos
	add_child(cabin)

	lamp = cabin.get_node("Lamp")
	fire_light = cabin.get_node("FireLight")
	window_mat = cabin.get_meta("window_mat")


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = Control.new()
	hud.set_script(HudScript)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	layer.add_child(hud)


func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)

	player.hud = hud
	player.cabin_pos = cabin_pos
	player.position = cabin_pos + Vector3(0.0, 0.6, 4.6)
	player.died.connect(_on_player_died)

	add_child(player)


# ---------------------------------------------------------
# شب و روز

func _sun_height() -> float:
	if t < DAY_FRAC:
		return sin(PI * t / DAY_FRAC)

	return -sin(PI * (t - DAY_FRAC) / (1.0 - DAY_FRAC))


func _update_daynight() -> void:
	var h: float = _sun_height()
	var day_f: float = clampf(h * 3.0, 0.0, 1.0)
	var night_f: float = clampf(-h * 4.0, 0.0, 1.0)

	night_amt = night_f

	sun.rotation_degrees = Vector3(
		-(8.0 + maxf(h, 0.0) * 62.0),
		-35.0,
		0.0
	)

	sun.light_energy = day_f * 1.25
	sun.light_color = Color(1.0, 0.55, 0.3).lerp(
		Color(1.0, 0.96, 0.88),
		day_f
	)
	sun.visible = h > -0.05

	moon.light_energy = night_f * 0.35
	moon.visible = night_f > 0.02

	var dusk_top := Color(0.30, 0.22, 0.42)
	var dusk_hor := Color(0.95, 0.50, 0.28)
	var day_top := Color(0.22, 0.46, 0.85)
	var day_hor := Color(0.66, 0.78, 0.92)
	var night_top := Color(0.01, 0.02, 0.06)
	var night_hor := Color(0.04, 0.06, 0.12)

	var top: Color
	var hor: Color

	if h >= 0.0:
		top = dusk_top.lerp(day_top, day_f)
		hor = dusk_hor.lerp(day_hor, day_f)
	else:
		top = dusk_top.lerp(night_top, night_f)
		hor = dusk_hor.lerp(night_hor, night_f)

	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.5)

	env.ambient_light_color = Color(0.09, 0.11, 0.19).lerp(
		Color(0.55, 0.60, 0.70),
		clampf((h + 0.1) * 2.5, 0.0, 1.0)
	)

	env.fog_light_color = hor
	env.fog_density = lerpf(0.010, 0.024, night_f)


func _begin_day() -> void:
	day_count += 1
	night_spawned = false
	dusk_warned = false
	spawn_left = 0

	for e in get_tree().get_nodes_in_group("cannibals"):
		e.queue_free()

	hud.show_msg("صبح شد — روز %d" % day_count, 4.0)


func _sleep() -> void:
	t = 0.0

	player.hp = minf(player.max_hp, player.hp + 40.0)
	player.hunger = maxf(10.0, player.hunger - 12.0)
	player.thirst = maxf(35.0, player.thirst - 8.0)
	player.fatigue = 0.0

	_begin_day()


# ---------------------------------------------------------
# آدم‌خوارها

func _spawn_cannibal() -> void:
	var c = CharacterBody3D.new()
	c.set_script(CannibalScript)

	var a := randf() * TAU
	var r := randf_range(40.0, 58.0)

	var x := cabin_pos.x + cos(a) * r
	var z := cabin_pos.z + sin(a) * r

	c.position = Vector3(x, height_at(x, z) + 0.6, z)
	c.target = player
	c.cabin_pos = cabin_pos
	c.ring_phase = randf() * TAU

	c.hp = 45.0 + day_count * 6.0
	c.damage = minf(8.0 + day_count * 1.0, 20.0)
	c.speed = minf(3.2 + day_count * 0.1, 4.6)

	c.killed.connect(_on_cannibal_killed)
	add_child(c)


func _on_cannibal_killed(_pos: Vector3) -> void:
	player.inv["meat"] += 1
	hud.show_msg("+1 گوشت", 1.2)


func _on_player_died() -> void:
	hud.dead_screen = true
	respawn_timer = 4.0


func _respawn_player() -> void:
	hud.dead_screen = false

	for k in ["wood", "stone", "fruit", "meat"]:
		player.inv[k] = int(float(player.inv[k]) * 0.5)

	player.respawn(cabin_pos + Vector3(0.0, 0.5, 0.0))

	t = 0.0
	_begin_day()

	hud.show_msg(
		"در کلبه بیدار شدی... نیمی از منابعت از دست رفت.",
		5.0
	)


# ---------------------------------------------------------
# حلقه‌ی اصلی بازی

func _process(delta: float) -> void:
	game_time += delta
	t += delta / DAY_SECONDS

	if t >= 1.0:
		t -= 1.0
		_begin_day()

	_update_daynight()
	_update_events(delta)

	if hud.consume_interact():
		_do_interact()

	if hud.consume_eat():
		_do_eat()

	_update_scan(delta)
	_update_hud()
	_flicker()

	if player.global_position.y < -15.0:
		player.global_position = cabin_pos + Vector3(0.0, 1.0, 4.6)


func _update_events(delta: float) -> void:
	if not dusk_warned and t >= 0.5 and t < SPAWN_T:
		dusk_warned = true
		hud.show_msg("غروب نزدیک است! به کلبه برگرد.", 5.0)

	if not night_spawned and t >= SPAWN_T:
		night_spawned = true
		spawn_left = clampi(3 + day_count * 2, 3, 16)
		spawn_timer = 1.0

		hud.show_msg(
			"شب شد! آدم‌خوارها از تاریکی می‌آیند...",
			5.0
		)

	if spawn_left > 0:
		spawn_timer -= delta

		if spawn_timer <= 0.0:
			spawn_timer = 4.0
			spawn_left -= 1
			_spawn_cannibal()

	if respawn_timer > 0.0:
		respawn_timer -= delta

		if respawn_timer <= 0.0:
			_respawn_player()


func _update_scan(delta: float) -> void:
	scan_timer -= delta

	if scan_timer > 0.0:
		return

	scan_timer = 0.15

	for i in bush_pos.size():
		if bush_hidden[i] and bush_ready[i] <= game_time:
			bush_hidden[i] = false
			_set_berries_visible(i, true)

	ctx = ""
	ctx_index = -1

	if player.dead:
		return

	var p: Vector3 = player.global_position

	if player.in_cabin:
		if t >= DAY_FRAC and _dist2(p, cabin_pos + BED_OFFSET) < 3.4:
			ctx = "sleep"
		return

	if absf(p.x - 26.0) < 4.2 and absf(p.z) < 70.0:
		ctx = "water"
		return

	var best := 2.4

	for i in bush_pos.size():
		if not bush_hidden[i]:
			var d := _dist2(p, bush_pos[i])

			if d < best:
				best = d
				ctx = "berry"
				ctx_index = i

	for i in tree_pos.size():
		if tree_ready[i] <= game_time:
			var d2 := _dist2(p, tree_pos[i])

			if d2 < best:
				best = d2
				ctx = "wood"
				ctx_index = i

	for i in rock_pos.size():
		if rock_ready[i] <= game_time:
			var d3 := _dist2(p, rock_pos[i])

			if d3 < best:
				best = d3
				ctx = "rock"
				ctx_index = i

	if ctx == "" and world_systems:
		ctx = world_systems.find_context(p)
		ctx_index = world_systems.context_index


func _hint_for(c: String) -> String:
	match c:
		"sleep":
			return "خواب تا صبح"
		"water":
			return "نوشیدن آب رودخانه"
		"berry":
			return "برداشت میوه"
		"wood":
			return "جمع‌آوری چوب"
		"rock":
			return "جمع‌آوری سنگ"

	return world_systems.hint_for(c) if world_systems else ""


func _do_interact() -> void:
	if player.dead or ctx == "":
		return

	match ctx:
		"sleep":
			_sleep()

		"water":
			player.drink_water()
			hud.show_msg("آب نوشیدی؛ تشنگی کمتر شد.", 1.8)

		"berry":
			bush_ready[ctx_index] = game_time + 90.0
			bush_hidden[ctx_index] = true
			_set_berries_visible(ctx_index, false)
			player.inv["fruit"] += 2
			hud.show_msg("+2 میوه", 1.2)

		"wood":
			tree_ready[ctx_index] = game_time + 20.0
			player.inv["wood"] += 2
			hud.show_msg("+2 چوب", 1.2)

		"rock":
			rock_ready[ctx_index] = game_time + 25.0
			player.inv["stone"] += 1
			hud.show_msg("+1 سنگ", 1.2)

		_:
			if world_systems:
				world_systems.interact(ctx)

	ctx = ""
	ctx_index = -1


func _do_eat() -> void:
	if player.dead:
		return

	if player.eat():
		hud.show_msg("میوه خوردی: سیری و جان بیشتر شد", 1.5)
	else:
		hud.show_msg("میوه‌ای نداری", 1.5)


func _update_hud() -> void:
	var inv: Dictionary = player.inv

	hud.hp_frac = player.hp / player.max_hp
	hud.hunger_frac = player.hunger / 100.0
	hud.thirst_frac = player.thirst / 100.0
	hud.fatigue_frac = player.fatigue / 100.0

	hud.inv_text = "چوب: %d   سنگ: %d   میوه: %d   گوشت: %d" % [
		inv["wood"],
		inv["stone"],
		inv["fruit"],
		inv["meat"]
	]

	hud.day_text = "روز %d" % day_count
	hud.time_frac = t
	hud.day_split = DAY_FRAC
	hud.hint = _hint_for(ctx)

	var ppos: Vector3 = player.global_position

	hud.compass_on = (
		not player.in_cabin
		and not player.dead
		and t > 0.35
	)

	var to_cabin := cabin_pos - ppos
	var tv := Vector2(to_cabin.x, to_cabin.z)

	if tv.length() > 0.1:
		var yaw: float = player.yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		hud.compass_angle = fwd.angle_to(tv.normalized())


func _flicker() -> void:
	fire_light.light_energy = (
		1.7
		+ sin(game_time * 13.0) * 0.25
		+ sin(game_time * 7.3) * 0.2
	)

	lamp.light_energy = lerpf(0.5, 1.1, night_amt)

	window_mat.emission_energy_multiplier = lerpf(
		0.0,
		2.5,
		clampf(night_amt * 2.0, 0.0, 1.0)
	)
