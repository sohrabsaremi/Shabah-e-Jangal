
extends Node3D
## سیستم‌های تکمیلی بقا و جهان بازی شبح جنگل

const SAVE_PATH := "user://shabah_save.json"

var game
var animals: Array[Node3D] = []
var notes: Array[Node3D] = []

var context: String = ""
var context_index: int = -1

var weather_timer: float = 0.0
var weather_kind: String = "clear"

var event_timer: float = 0.0
var event_active: String = ""
var event_warning: bool = false
var event_pending: String = "tornado"

var meteor: Node3D
var tornado: Node3D
var meteor_target := Vector3.ZERO
var tornado_origin := Vector3.ZERO

var lightning_timer: float = 4.0

var torch_fuel: float = 0.0
var torch_node: Node3D
var torch_light: OmniLight3D
var torch_fire: MeshInstance3D

var cabin_level: int = 1
var cabin_hp: float = 100.0

var rain_particles: GPUParticles3D
var storm_light: OmniLight3D
var volcano: Node3D
var volcano_glow: OmniLight3D

var time_accum: float = 0.0
var autosave_timer: float = 120.0

var rng := RandomNumberGenerator.new()


func setup(main_node: Node3D) -> void:
	game = main_node
	rng.randomize()

	_build_volcano()
	_build_weather()
	_build_torch()
	_build_notes()
	_spawn_animals()
	_load_game(false)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return

	time_accum += delta
	autosave_timer -= delta

	if autosave_timer <= 0.0:
		autosave_timer = 120.0
		save_game(false)

	weather_timer -= delta
	if weather_timer <= 0.0:
		_change_weather()

	_update_weather(delta)
	_update_animals(delta)
	_update_torch(delta)
	_update_disasters(delta)


# ---------------------------------------------------------
# تعاملات و راهنمای بازیکن

func find_context(pos: Vector3) -> String:
	context = ""
	context_index = -1
	var best := 3.0

	if (
		is_instance_valid(torch_node)
		and torch_fuel <= 0.0
		and game.player.inv.get("wood", 0) >= 1
		and _dist(pos, torch_node.global_position) < best
	):
		context = "torch_fuel"
		best = _dist(pos, torch_node.global_position)

	if _dist(pos, game.cabin_pos) < 3.0 and not game.player.in_cabin:
		var wood_need := 8 + cabin_level * 4
		var stone_need := 4 + cabin_level * 2

		if (
			cabin_level < 3
			and game.player.inv.get("wood", 0) >= wood_need
			and game.player.inv.get("stone", 0) >= stone_need
		):
			context = "upgrade_cabin"
			best = 2.8

		elif (
			game.player.inv.get("wood", 0) >= 2
			and game.player.inv.get("stone", 0) >= 1
			and _dist(pos, game.cabin_pos + Vector3(2.8, 0, 0)) < best
		):
			context = "craft_torch"
			best = _dist(pos, game.cabin_pos + Vector3(2.8, 0, 0))

		elif _dist(pos, game.cabin_pos + Vector3(0, 0, 3.2)) < best:
			context = "save_game"
			best = _dist(pos, game.cabin_pos + Vector3(0, 0, 3.2))

	for i in notes.size():
		if not is_instance_valid(notes[i]):
			continue

		var note_distance := _dist(pos, notes[i].global_position)
		if note_distance < best:
			context = "note"
			context_index = i
			best = note_distance

	for i in animals.size():
		if not is_instance_valid(animals[i]):
			continue

		var animal_distance := _dist(pos, animals[i].global_position)
		if animal_distance < best:
			context = "animal"
			context_index = i
			best = animal_distance

	return context


func hint_for(kind: String) -> String:
	match kind:
		"torch_fuel":
			return "سوخت‌گیری مشعل (۱ چوب)"
		"upgrade_cabin":
			return "ارتقای کلبه (چوب و سنگ)"
		"craft_torch":
			return "ساخت مشعل دفاعی (۲ چوب + ۱ سنگ)"
		"save_game":
			return "ذخیره بازی"
		"note":
			return "خواندن یادداشت پیدا شده"
		"animal":
			return "شکار حیوان (عمل)"

	return ""


func interact(kind: String) -> bool:
	if game == null or game.player.dead:
		return false

	match kind:
		"torch_fuel":
			if game.player.inv.get("wood", 0) < 1:
				game.hud.show_msg("برای روشن کردن مشعل ۱ چوب لازم داری.", 2.0)
				return true

			game.player.inv["wood"] -= 1
			torch_fuel = 150.0
			torch_node.visible = true
			torch_fire.visible = true
			torch_light.visible = true

			game.hud.show_msg(
				"مشعل روشن شد؛ آدم‌خوارها از آتش دوری می‌کنند.",
				3.0
			)
			return true

		"save_game":
			save_game(true)
			return true

		"craft_torch":
			if (
				game.player.inv.get("wood", 0) >= 2
				and game.player.inv.get("stone", 0) >= 1
			):
				game.player.inv["wood"] -= 2
				game.player.inv["stone"] -= 1
				torch_fuel = 150.0
				torch_node.visible = true
				torch_light.visible = true
				torch_fire.visible = true

				game.hud.show_msg("مشعل دفاعی ساخته شد.", 2.0)
			else:
				game.hud.show_msg("نیاز داری: ۲ چوب و ۱ سنگ.", 2.0)

			return true

		"upgrade_cabin":
			var wood_need := 8 + cabin_level * 4
			var stone_need := 4 + cabin_level * 2

			if cabin_level >= 3:
				game.hud.show_msg("کلبه در بالاترین سطح است.", 2.0)

			elif (
				game.player.inv.get("wood", 0) >= wood_need
				and game.player.inv.get("stone", 0) >= stone_need
			):
				game.player.inv["wood"] -= wood_need
				game.player.inv["stone"] -= stone_need

				cabin_level += 1
				cabin_hp = minf(200.0, cabin_hp + 50.0)
				game.cabin.scale = Vector3.ONE * (
					1.0 + 0.08 * float(cabin_level - 1)
				)

				game.hud.show_msg(
					"کلبه ارتقا یافت! سطح %d" % cabin_level,
					3.0
				)
			else:
				game.hud.show_msg(
					"نیاز داری: %d چوب و %d سنگ." % [
						wood_need,
						stone_need
					],
					2.5
				)

			return true

		"note":
			if context_index >= 0 and context_index < notes.size():
				var note: Node3D = notes[context_index]

				if is_instance_valid(note):
					game.hud.show_msg(
						str(note.get_meta("story", "یادداشتی محو شده است.")),
						6.0
					)
					note.queue_free()
					notes[context_index] = null

			return true

		"animal":
			if context_index >= 0 and context_index < animals.size():
				var animal: Node3D = animals[context_index]

				if (
					is_instance_valid(animal)
					and _dist(
						game.player.global_position,
						animal.global_position
					) < 2.8
				):
					var kind_name := str(
						animal.get_meta("animal_type", "deer")
					)

					if kind_name == "wolf":
						game.player.take_damage(7.0)
						game.hud.show_msg(
							"گرگ حمله کرد! از خودت دفاع کن.",
							2.5
						)
					else:
						game.player.inv["meat"] = (
							int(game.player.inv.get("meat", 0)) + 1
						)
						game.hud.show_msg("۱ گوشت به دست آوردی.", 2.0)

					animal.queue_free()
					animals[context_index] = null

			return true

	return false


# ---------------------------------------------------------
# ذخیره و بارگذاری بازی

func save_game(show_message: bool = true) -> void:
	if game == null or game.player == null:
		return

	var data := {
		"version": 1,
		"day": game.day_count,
		"time": game.t,
		"position": [
			game.player.global_position.x,
			game.player.global_position.y,
			game.player.global_position.z
		],
		"hp": game.player.hp,
		"hunger": game.player.hunger,
		"thirst": game.player.thirst,
		"fatigue": game.player.fatigue,
		"inventory": game.player.inv,
		"cabin_level": cabin_level,
		"cabin_hp": cabin_hp,
		"torch_fuel": torch_fuel
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		if show_message:
			game.hud.show_msg("ذخیره بازی ناموفق بود.", 2.0)
		return

	file.store_string(JSON.stringify(data))

	if show_message:
		game.hud.show_msg("بازی ذخیره شد.", 2.0)


func _load_game(show_message: bool = true) -> void:
	if not FileAccess.file_exists(SAVE_PATH) or game == null:
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parsed

	game.day_count = maxi(1, int(data.get("day", 1)))
	game.t = clampf(float(data.get("time", 0.05)), 0.0, 0.99)

	var saved_position: Array = data.get("position", [0.0, 1.0, 4.6])
	if saved_position.size() >= 3:
		game.player.global_position = Vector3(
			float(saved_position[0]),
			float(saved_position[1]),
			float(saved_position[2])
		)

	game.player.hp = clampf(
		float(data.get("hp", 100.0)),
		1.0,
		game.player.max_hp
	)
	game.player.hunger = clampf(
		float(data.get("hunger", 100.0)), 0.0, 100.0
	)
	game.player.thirst = clampf(
		float(data.get("thirst", 100.0)), 0.0, 100.0
	)
	game.player.fatigue = clampf(
		float(data.get("fatigue", 0.0)), 0.0, 100.0
	)

	var inventory = data.get("inventory", {})
	if typeof(inventory) == TYPE_DICTIONARY:
		for key in ["wood", "stone", "fruit", "meat"]:
			game.player.inv[key] = maxi(
				0,
				int(inventory.get(key, game.player.inv.get(key, 0)))
			)

	cabin_level = clampi(int(data.get("cabin_level", 1)), 1, 3)
	cabin_hp = clampf(float(data.get("cabin_hp", 100.0)), 0.0, 200.0)
	torch_fuel = maxf(0.0, float(data.get("torch_fuel", 0.0)))

	if is_instance_valid(torch_node):
		var torch_on := torch_fuel > 0.0
		torch_node.visible = torch_on
		torch_light.visible = torch_on
		torch_fire.visible = torch_on

	if show_message:
		game.hud.show_msg("ذخیره بارگذاری شد.", 2.0)


# ---------------------------------------------------------
# آتشفشان

func _build_volcano() -> void:
	volcano = Node3D.new()
	volcano.name = "DistantVolcano"
	volcano.position = Vector3(
		-103.0,
		game.height_at(-103.0, -100.0),
		-100.0
	)
	add_child(volcano)

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 1.0
	cone_mesh.bottom_radius = 22.0
	cone_mesh.height = 34.0
	cone_mesh.radial_segments = 9

	var cone := MeshInstance3D.new()
	cone.mesh = cone_mesh
	cone.position.y = 17.0
	cone.material_override = _mat(Color(0.18, 0.16, 0.15))
	volcano.add_child(cone)

	var crater := MeshInstance3D.new()
	var crater_mesh := CylinderMesh.new()
	crater_mesh.top_radius = 4.4
	crater_mesh.bottom_radius = 6.0
	crater_mesh.height = 1.2
	crater_mesh.radial_segments = 12
	crater.mesh = crater_mesh
	crater.position.y = 33.0

	var lava := _mat(Color(0.9, 0.13, 0.015), true)
	lava.emission_energy_multiplier = 2.2
	crater.material_override = lava
	volcano.add_child(crater)

	volcano_glow = OmniLight3D.new()
	volcano_glow.light_color = Color(1.0, 0.18, 0.04)
	volcano_glow.light_energy = 1.6
	volcano_glow.omni_range = 25.0
	volcano_glow.position.y = 30.0
	volcano.add_child(volcano_glow)


# ---------------------------------------------------------
# باران، مه و رعدوبرق

func _build_weather() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "RainParticles"
	rain_particles.amount = 420
	rain_particles.lifetime = 1.4
	rain_particles.emitting = false
	rain_particles.position = Vector3(0, 10, 0)
	rain_particles.visibility_aabb = AABB(
		Vector3(-28, -12, -28),
		Vector3(56, 28, 56)
	)

	var particle_material := ParticleProcessMaterial.new()
	particle_material.direction = Vector3(0.0, -1.0, 0.0)
	particle_material.initial_velocity_min = 18.0
	particle_material.initial_velocity_max = 25.0
	particle_material.gravity = Vector3(0.0, -3.0, 0.0)
	particle_material.scale_min = 0.025
	particle_material.scale_max = 0.05
	rain_particles.process_material = particle_material

	var rain_mesh := BoxMesh.new()
	rain_mesh.size = Vector3(0.025, 0.55, 0.025)

	var rain_material := StandardMaterial3D.new()
	rain_material.albedo_color = Color(0.55, 0.72, 0.9, 0.5)
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mesh.material = rain_material
	rain_particles.draw_pass_1 = rain_mesh
	add_child(rain_particles)

	storm_light = OmniLight3D.new()
	storm_light.light_color = Color(0.72, 0.82, 1.0)
	storm_light.light_energy = 0.0
	storm_light.omni_range = 45.0
	storm_light.position = Vector3(0, 16, 0)
	add_child(storm_light)


func _change_weather() -> void:
	weather_timer = rng.randf_range(75.0, 145.0)

	var roll := rng.randf()
	if roll < 0.52:
		weather_kind = "clear"
	elif roll < 0.75:
		weather_kind = "fog"
	else:
		weather_kind = "rain"

	if game and game.hud:
		match weather_kind:
			"fog":
				game.hud.show_msg("مه غلیظی جنگل را پوشانده است...", 3.0)
			"rain":
				game.hud.show_msg("باران شروع شد؛ دید کمتر می‌شود.", 3.0)
			_:
				game.hud.show_msg("هوا آرام‌تر شده است.", 2.0)


func _update_weather(delta: float) -> void:
	if game == null:
		return

	var player_position: Vector3 = game.player.global_position
	lightning_timer -= delta

	if weather_kind == "rain" and lightning_timer <= 0.0:
		lightning_timer = rng.randf_range(5.0, 13.0)
		storm_light.light_energy = rng.randf_range(2.0, 5.0)

		if rng.randf() < 0.35:
			game.hud.show_msg("رعد در دوردست می‌پیچد...", 1.5)

	rain_particles.global_position = player_position + Vector3(0, 8, 0)
	rain_particles.emitting = weather_kind == "rain"

	if weather_kind == "fog":
		game.env.fog_enabled = true
		game.env.fog_density = lerpf(
			game.env.fog_density, 0.038, 0.02
		)

	elif weather_kind == "rain":
		game.env.fog_enabled = true
		game.env.fog_density = lerpf(
			game.env.fog_density, 0.026, 0.02
		)

	else:
		game.env.fog_density = lerpf(
			game.env.fog_density, 0.012, 0.02
		)

	storm_light.light_energy = maxf(
		0.0,
		storm_light.light_energy - 3.0 * delta
	)


# ---------------------------------------------------------
# بلایای طبیعی: گردباد و شهاب‌سنگ

func _update_disasters(delta: float) -> void:
	if game == null or game.player == null:
		return

	if event_active == "warning":
		event_timer -= delta
		if event_timer <= 0.0:
			if event_pending == "meteor":
				_start_meteor()
			else:
				_start_tornado()
		return

	if event_active == "tornado":
		event_timer -= delta

		var tornado_pos := event_node_position()

		if (
			_dist(game.player.global_position, tornado_pos) < 8.0
			and not game.player.in_cabin
			and not game.player.dead
		):
			game.player.take_damage(4.0 * delta)

		if event_timer <= 0.0:
			if is_instance_valid(tornado):
				tornado.queue_free()

			event_active = ""
			event_warning = false
			game.hud.show_msg("توفان تمام شد؛ می‌توانی بیرون بروی.", 3.0)

		return

	if event_active == "meteor":
		event_timer -= delta

		if is_instance_valid(meteor):
			meteor.position = meteor.position.lerp(
				meteor_target,
				clampf(delta * 0.8, 0.0, 1.0)
			)
			meteor.position.y = maxf(
				1.0,
				meteor.position.y - 14.0 * delta
			)

		if event_timer <= 0.0:
			var impact := meteor_target

			if is_instance_valid(meteor):
				impact = meteor.global_position
				meteor.queue_free()

			var crater := MeshInstance3D.new()
			var crater_mesh := CylinderMesh.new()
			crater_mesh.top_radius = 2.6
			crater_mesh.bottom_radius = 2.1
			crater_mesh.height = 0.18
			crater.mesh = crater_mesh
			crater.material_override = _mat(Color(0.12, 0.10, 0.09))
			crater.position = Vector3(
				impact.x,
				game.height_at(impact.x, impact.z) + 0.1,
				impact.z
			)
			add_child(crater)

			if (
				_dist(game.player.global_position, impact) < 7.0
				and not game.player.in_cabin
			):
				game.player.take_damage(28.0)

			game.hud.show_msg(
				"شهاب به زمین برخورد کرد! از محل برخورد فاصله بگیر.",
				3.0
			)

			event_active = ""
			event_warning = false

		return

	# احتمال شروع یک رویداد در شب
	if game.t > 0.68 and rng.randf() < 0.003 * delta:
		event_warning = true
		event_active = "warning"
		event_timer = 8.0
		event_pending = "meteor" if rng.randf() < 0.38 else "tornado"

		if event_pending == "meteor":
			game.hud.show_msg(
				"هشدار: نور آتشینی در آسمان دیده می‌شود؛ از محل باز دور شو!",
				5.0
			)
		else:
			game.hud.show_msg(
				"هشدار: باد غیرعادی می‌وزد! به کلبه پناه ببر.",
				5.0
			)


func _start_tornado() -> void:
	event_active = "tornado"
	event_timer = 18.0
	tornado_origin = game.player.global_position

	tornado = Node3D.new()
	tornado.name = "Tornado"
	tornado.position = tornado_origin
	add_child(tornado)

	for i in 5:
		var funnel := MeshInstance3D.new()
		var funnel_mesh := CylinderMesh.new()
		funnel_mesh.top_radius = 0.35 + float(i) * 0.20
		funnel_mesh.bottom_radius = 1.0 + float(i) * 0.32
		funnel_mesh.height = 2.2
		funnel_mesh.radial_segments = 10
		funnel.mesh = funnel_mesh

		var funnel_material := _mat(Color(0.42, 0.43, 0.44))
		funnel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		funnel_material.albedo_color.a = 0.72
		funnel.material_override = funnel_material

		funnel.position.y = float(i) * 1.8
		tornado.add_child(funnel)

	game.hud.show_msg(
		"گردباد شروع شد! از آن فاصله بگیر یا به کلبه پناه ببر.",
		4.0
	)


func event_node_position() -> Vector3:
	if is_instance_valid(tornado):
		return tornado.global_position
	return tornado_origin


func _start_meteor() -> void:
	event_active = "meteor"
	event_timer = 4.0

	meteor_target = game.player.global_position + Vector3(
		rng.randf_range(-12.0, 12.0),
		0.0,
		rng.randf_range(-12.0, 12.0)
	)

	meteor = Node3D.new()
	meteor.name = "Meteor"
	meteor.position = meteor_target + Vector3(
		rng.randf_range(-18.0, 18.0),
		42.0,
		rng.randf_range(-18.0, 18.0)
	)

	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	core.mesh = sphere
	core.material_override = _mat(Color(1.0, 0.22, 0.025), true)
	meteor.add_child(core)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.06)
	light.light_energy = 5.0
	light.omni_range = 18.0
	meteor.add_child(light)

	add_child(meteor)

	game.hud.show_msg(
		"شهاب در حال سقوط است! چند ثانیه فرصت داری دور شوی.",
		3.0
	)


# ---------------------------------------------------------
# مشعل دفاعی

func _build_torch() -> void:
	torch_node = Node3D.new()
	torch_node.name = "DefensiveTorch"
	torch_node.position = game.cabin_pos + Vector3(3.0, 0.0, 0.0)
	add_child(torch_node)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.11
	pole_mesh.height = 1.6
	pole.mesh = pole_mesh
	pole.position.y = 0.8
	pole.material_override = _mat(Color(0.24, 0.14, 0.07))
	torch_node.add_child(pole)

	torch_fire = MeshInstance3D.new()
	var fire_mesh := SphereMesh.new()
	fire_mesh.radius = 0.24
	fire_mesh.height = 0.55
	torch_fire.mesh = fire_mesh
	torch_fire.position.y = 1.7
	torch_fire.material_override = _mat(
		Color(1.0, 0.28, 0.025), true
	)
	torch_node.add_child(torch_fire)

	torch_light = OmniLight3D.new()
	torch_light.position.y = 1.8
	torch_light.light_color = Color(1.0, 0.39, 0.12)
	torch_light.light_energy = 2.4
	torch_light.omni_range = 11.0
	torch_node.add_child(torch_light)

	torch_node.visible = false
	torch_light.visible = false
	torch_fire.visible = false


func _update_torch(delta: float) -> void:
	if torch_fuel > 0.0:
		torch_fuel = maxf(0.0, torch_fuel - delta)

		if torch_fuel <= 0.0:
			torch_node.visible = false
			torch_light.visible = false
			torch_fire.visible = false
			game.hud.show_msg("سوخت مشعل تمام شد.", 2.0)

	if torch_fuel > 0.0:
		torch_light.light_energy = (
			2.0 + sin(time_accum * 13.0) * 0.25
		)


# ---------------------------------------------------------
# یادداشت‌های داستانی

func _build_notes() -> void:
	var stories := [
		"یادداشت اول — این جنگل در نقشه‌های قدیمی ثبت نشده. صدای زنگی از کوه می‌آید، حتی وقتی باد نمی‌وزد.",
		"یادداشت دوم — آن‌ها از ابتدا آدم‌خوار نبودند. آزمایشگاه نزدیک آتشفشان را تخلیه کردند، اما کسی نگفت چه چیزی بیدار شده بود.",
		"یادداشت سوم — مردی که در کلبه زندگی می‌کرد نگهبان ایستگاه بود. اگر این نوشته را پیدا کردی، بعد از غروب به سمت کوه نرو.",
		"یادداشت چهارم — آتش آن‌ها را دور نگه می‌دارد، اما فقط تا وقتی که شعله روشن باشد. روزها را برای آماده شدن استفاده کن."
	]

	for i in stories.size():
		var note := Node3D.new()
		note.name = "ForestNote%d" % i

		var angle := float(i) * 1.57 + 0.8
		var radius := 18.0 + float(i) * 13.0
		var x := cos(angle) * radius
		var z := sin(angle) * radius

		note.position = Vector3(
			x,
			game.height_at(x, z) + 0.7,
			z
		)

		var paper := MeshInstance3D.new()
		var paper_mesh := BoxMesh.new()
		paper_mesh.size = Vector3(0.34, 0.025, 0.24)
		paper.mesh = paper_mesh
		paper.material_override = _mat(Color(0.72, 0.63, 0.42))
		note.add_child(paper)

		var glow := OmniLight3D.new()
		glow.light_color = Color(0.7, 0.62, 0.3)
		glow.light_energy = 0.35
		glow.omni_range = 2.0
		glow.position.y = 0.4
		note.add_child(glow)

		note.set_meta("story", stories[i])
		add_child(note)
		notes.append(note)


# ---------------------------------------------------------
# حیوانات جنگل

func _spawn_animals() -> void:
	for i in 9:
		var kind := "wolf" if i >= 7 else (
			"deer" if i % 2 == 0 else "boar"
		)

		var animal := Node3D.new()
		animal.name = "%s_%d" % [kind, i]

		var angle := rng.randf() * TAU
		var radius := rng.randf_range(28.0, 70.0)
		var x := cos(angle) * radius
		var z := sin(angle) * radius

		animal.position = Vector3(
			x,
			game.height_at(x, z) + 0.55,
			z
		)

		animal.set_meta("animal_type", kind)
		animal.set_meta("home", animal.position)

		var body := MeshInstance3D.new()
		var body_mesh := SphereMesh.new()
		body_mesh.radius = 0.48 if kind != "wolf" else 0.42
		body_mesh.height = 0.85 if kind != "wolf" else 0.65
		body.mesh = body_mesh

		body.position.y = 0.45
		body.scale = (
			Vector3(1.35, 0.8, 1.8)
			if kind == "deer"
			else Vector3(1.2, 0.85, 1.4)
		)

		var animal_color := Color(0.38, 0.25, 0.13)
		if kind == "wolf":
			animal_color = Color(0.23, 0.23, 0.25)
		elif kind == "boar":
			animal_color = Color(0.27, 0.18, 0.12)

		body.material_override = _mat(animal_color)
		animal.add_child(body)

		add_child(animal)
		animals.append(animal)


func _update_animals(delta: float) -> void:
	for animal in animals:
		if not is_instance_valid(animal):
			continue

		var home: Vector3 = animal.get_meta(
			"home",
			animal.global_position
		)
		var kind := str(animal.get_meta("animal_type", "deer"))
		var target := home

		var distance := _dist(
			animal.global_position,
			game.player.global_position
		)

		if kind == "wolf" and distance < 13.0 and not game.player.dead:
			target = game.player.global_position

		elif distance < 7.0 and kind != "wolf":
			var away := animal.global_position - game.player.global_position
			away.y = 0.0

			if away.length() > 0.01:
				target = animal.global_position + away.normalized() * 12.0

		elif _dist(animal.global_position, home) < 3.0:
			var phase := float(animal.get_instance_id())
			target = home + Vector3(
				sin(time_accum * 0.3 + phase) * 3.0,
				0.0,
				cos(time_accum * 0.27 + phase) * 3.0
			)

		var direction := target - animal.global_position
		direction.y = 0.0

		if direction.length() > 0.5:
			var animal_speed := 2.6 if kind == "wolf" else 1.5
			animal.position += direction.normalized() * animal_speed * delta

			animal.position.y = game.height_at(
				animal.position.x,
				animal.position.z
			) + 0.55

			animal.rotation.y = atan2(-direction.x, -direction.z)

		if kind == "wolf" and distance < 1.7 and not game.player.dead:
			game.player.take_damage(5.0 * delta)


# ---------------------------------------------------------
# ابزارهای کمکی

func _mat(col: Color, emission: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = col
	material.roughness = 0.85

	if emission:
		material.emission_enabled = true
		material.emission = col
		material.emission_energy_multiplier = 1.8

	return material


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
