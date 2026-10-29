extends RefCounted
# All 3D models are built from code (no external model files).

# ---------------------------------------------------------------- helpers

static func mat(color: Color, rough: float = 0.85, metal: float = 0.0, emit_color: Color = Color.BLACK, emit_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit_energy > 0.0:
		m.emission_enabled = true
		m.emission = emit_color
		m.emission_energy_multiplier = emit_energy
	return m


static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func cyl(top: float, bottom: float, h: float, seg: int = 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sph(r: float, seg: int = 12, rings: int = 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


static func capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0 + 0.01)
	m.radial_segments = 10
	m.rings = 4
	return m


static func prism(w: float, h: float, d: float) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = Vector3(w, h, d)
	return m


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pname: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	parent.add_child(n)
	return n


static func col_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


static func solid_box(body: StaticBody3D, size: Vector3, pos: Vector3, material: Material) -> void:
	part(body, box(size), material, pos)
	col_box(body, size, pos)


static func bake(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


# ---------------------------------------------------------------- hero

static func build_hero() -> Node3D:
	var root := Node3D.new()
	root.name = "Hero"
	var leather := mat(Color(0.045, 0.045, 0.05), 0.5, 0.2)
	var leather2 := mat(Color(0.10, 0.07, 0.05), 0.7, 0.1)
	var iron := mat(Color(0.62, 0.64, 0.68), 0.3, 0.95)
	var dark_iron := mat(Color(0.18, 0.18, 0.2), 0.4, 0.9)
	var skin := mat(Color(0.72, 0.56, 0.46), 0.8)
	var olive := mat(Color(0.22, 0.27, 0.16), 0.6, 0.3)
	var tooth := mat(Color(0.92, 0.9, 0.82), 0.4)
	var lens := mat(Color(0.9, 0.5, 0.05), 0.2, 0.0, Color(1.0, 0.45, 0.05), 2.2)

	# legs
	for side in [-1, 1]:
		var leg := pivot(root, "LegL" if side < 0 else "LegR", Vector3(0.12 * side, 0.95, 0.0))
		root.set_meta("legL" if side < 0 else "legR", leg)
		part(leg, capsule(0.095, 0.9), leather, Vector3(0, -0.45, 0))
		part(leg, box(Vector3(0.2, 0.13, 0.32)), leather2, Vector3(0, -0.88, -0.05))
		part(leg, box(Vector3(0.15, 0.14, 0.05)), dark_iron, Vector3(0, -0.5, -0.09))

	# torso, belt, coat
	part(root, box(Vector3(0.5, 0.58, 0.28)), leather, Vector3(0, 1.28, 0))
	part(root, box(Vector3(0.54, 0.08, 0.32)), leather2, Vector3(0, 0.98, 0))
	part(root, box(Vector3(0.1, 0.1, 0.03)), iron, Vector3(0, 0.98, -0.17))
	part(root, box(Vector3(0.52, 0.5, 0.05)), leather, Vector3(0, 0.72, 0.12), Vector3(8, 0, 0))
	part(root, box(Vector3(0.3, 0.42, 0.04)), leather, Vector3(0, 0.76, -0.14), Vector3(-6, 0, 0))
	part(root, box(Vector3(0.06, 0.7, 0.02)), leather2, Vector3(0, 1.28, -0.145), Vector3(0, 0, 35))
	part(root, box(Vector3(0.06, 0.7, 0.02)), leather2, Vector3(0, 1.28, -0.145), Vector3(0, 0, -35))

	# shoulders with spikes
	for side in [-1, 1]:
		part(root, sph(0.13, 10, 5), leather, Vector3(0.33 * side, 1.5, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
		part(root, cyl(0.0, 0.035, 0.16, 6), iron, Vector3(0.37 * side, 1.62, 0), Vector3(0, 0, -20 * side))

	# arms
	for side in [-1, 1]:
		var arm := pivot(root, "ArmL" if side < 0 else "ArmR", Vector3(0.33 * side, 1.5, 0.0))
		root.set_meta("armL" if side < 0 else "armR", arm)
		part(arm, capsule(0.07, 0.62), leather, Vector3(0, -0.3, 0))
		part(arm, cyl(0.078, 0.078, 0.18, 8), dark_iron, Vector3(0, -0.46, 0))
		part(arm, box(Vector3(0.13, 0.13, 0.13)), leather2, Vector3(0, -0.64, 0))

	# neck + head
	part(root, cyl(0.06, 0.07, 0.1, 8), skin, Vector3(0, 1.6, 0))
	var head := pivot(root, "Head", Vector3(0, 1.74, 0))
	part(head, sph(0.125, 12, 8), skin)
	part(head, sph(0.14, 12, 8), leather, Vector3(0, 0.03, 0.05))
	part(head, cyl(0.14, 0.14, 0.03, 12), leather2, Vector3(0, 0.05, 0.0))

	# mask: faceplate, lenses, filters, sharp teeth
	part(head, sph(0.135, 12, 8), dark_iron, Vector3(0, -0.01, -0.035), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
	for side in [-1, 1]:
		part(head, cyl(0.055, 0.055, 0.02, 10), dark_iron, Vector3(0.062 * side, 0.025, -0.145), Vector3(90, 0, 0))
		part(head, sph(0.045, 10, 6), lens, Vector3(0.062 * side, 0.025, -0.15), Vector3.ZERO, Vector3(1, 1, 0.55))
		part(head, cyl(0.045, 0.045, 0.08, 10), olive, Vector3(0.1 * side, -0.075, -0.13), Vector3(90, 0, 0))
		part(head, cyl(0.05, 0.05, 0.015, 10), dark_iron, Vector3(0.1 * side, -0.075, -0.175), Vector3(90, 0, 0))
	part(head, box(Vector3(0.17, 0.035, 0.05)), dark_iron, Vector3(0, -0.125, -0.12))
	for i in 6:
		var x: float = -0.075 + i * 0.03
		part(head, cyl(0.0, 0.014, 0.05, 5), tooth, Vector3(x, -0.165, -0.145), Vector3(180, 0, 0))
	for i in 5:
		var x2: float = -0.06 + i * 0.03
		part(head, cyl(0.0, 0.012, 0.04, 5), tooth, Vector3(x2, -0.2, -0.145))
	part(head, box(Vector3(0.14, 0.03, 0.05)), dark_iron, Vector3(0, -0.225, -0.13))

	# four iron blades on the back
	part(root, box(Vector3(0.34, 0.1, 0.07)), dark_iron, Vector3(0, 1.45, 0.17))
	var angles := [-30.0, -10.0, 10.0, 30.0]
	var heights := [0.62, 0.85, 0.85, 0.62]
	for i in 4:
		var bp := pivot(root, "Blade%d" % i, Vector3(0.0, 1.45, 0.2))
		bp.rotation_degrees = Vector3(18.0, 0.0, angles[i])
		part(bp, prism(0.09, heights[i], 0.03), iron, Vector3(0, heights[i] * 0.5, 0))
	return root


# ---------------------------------------------------------------- cannibal

static func build_cannibal(tone: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Cannibal"
	var skin := mat(Color(0.56, 0.42, 0.33).lerp(Color(0.40, 0.45, 0.33), tone), 0.9)
	var cloth := mat(Color(0.22, 0.15, 0.09), 1.0)
	var hair := mat(Color(0.05, 0.04, 0.03), 1.0)
	var bone := mat(Color(0.86, 0.82, 0.72), 0.6)
	var wood := mat(Color(0.30, 0.2, 0.1), 0.9)
	var paint := mat(Color(0.88, 0.88, 0.84), 0.9)
	var eye := mat(Color(1.0, 0.1, 0.05), 0.3, 0.0, Color(1.0, 0.1, 0.0), 3.0)
	var blood := mat(Color(0.35, 0.03, 0.03), 0.8)

	for side in [-1, 1]:
		var leg := pivot(root, "LegL" if side < 0 else "LegR", Vector3(0.13 * side, 0.9, 0.0))
		root.set_meta("legL" if side < 0 else "legR", leg)
		part(leg, capsule(0.09, 0.9), skin, Vector3(0, -0.45, 0))

	var torso := pivot(root, "Torso", Vector3(0, 0.92, 0))
	torso.rotation_degrees = Vector3(-20, 0, 0)
	part(torso, box(Vector3(0.52, 0.62, 0.3)), skin, Vector3(0, 0.3, 0))
	part(torso, box(Vector3(0.54, 0.3, 0.32)), cloth, Vector3(0, 0.02, 0))
	part(torso, box(Vector3(0.3, 0.05, 0.02)), blood, Vector3(0, 0.38, -0.155))
	part(torso, box(Vector3(0.22, 0.05, 0.02)), blood, Vector3(0.05, 0.28, -0.155))
	for i in 5:
		part(torso, sph(0.03, 6, 4), bone, Vector3(-0.12 + i * 0.06, 0.55 - absf(i - 2) * 0.02, -0.16))

	var head := pivot(torso, "Head", Vector3(0, 0.78, -0.04))
	head.rotation_degrees = Vector3(20, 0, 0)
	part(head, sph(0.14, 10, 6), skin)
	part(head, sph(0.15, 10, 6), hair, Vector3(0, 0.04, 0.05), Vector3.ZERO, Vector3(1, 0.85, 1))
	part(head, box(Vector3(0.28, 0.03, 0.02)), paint, Vector3(0, 0.0, -0.135))
	for side in [-1, 1]:
		part(head, sph(0.03, 6, 4), eye, Vector3(0.055 * side, 0.03, -0.12))
	for i in 4:
		part(head, cyl(0.0, 0.012, 0.04, 5), bone, Vector3(-0.045 + i * 0.03, -0.085, -0.125), Vector3(180, 0, 0))

	for side in [-1, 1]:
		var arm := pivot(torso, "ArmL" if side < 0 else "ArmR", Vector3(0.34 * side, 0.55, 0.0))
		root.set_meta("armL" if side < 0 else "armR", arm)
		part(arm, capsule(0.065, 0.7), skin, Vector3(0, -0.33, 0))
		if side > 0:
			part(arm, cyl(0.07, 0.04, 0.8, 6), wood, Vector3(0, -0.65, -0.05), Vector3(-70, 0, 0))
			part(arm, sph(0.09, 6, 4), bone, Vector3(0, -0.52, -0.41))
	return root


# ---------------------------------------------------------------- nature meshes

static func tree_trunk_mesh() -> ArrayMesh:
	return bake([[cyl(0.2, 0.34, 3.4, 6), Transform3D(Basis(), Vector3(0, 1.7, 0))]])


static func tree_leaf_mesh() -> ArrayMesh:
	return bake([
		[cyl(0.0, 1.7, 2.0, 7), Transform3D(Basis(), Vector3(0, 3.0, 0))],
		[cyl(0.0, 1.35, 1.8, 7), Transform3D(Basis(), Vector3(0, 4.1, 0))],
		[cyl(0.0, 0.95, 1.6, 7), Transform3D(Basis(), Vector3(0, 5.1, 0))],
	])


static func rock_mesh() -> ArrayMesh:
	return bake([[sph(0.8, 6, 4), Transform3D(Basis(), Vector3(0, 0.25, 0))]])


static func bush_mesh() -> ArrayMesh:
	return bake([
		[sph(0.55, 8, 5), Transform3D(Basis(), Vector3(0, 0.45, 0))],
		[sph(0.42, 8, 5), Transform3D(Basis(), Vector3(0.4, 0.35, 0.1))],
		[sph(0.4, 8, 5), Transform3D(Basis(), Vector3(-0.35, 0.33, -0.1))],
	])


# ---------------------------------------------------------------- cabin

static func build_cabin() -> Node3D:
	var root := Node3D.new()
	root.name = "Cabin"
	var body := StaticBody3D.new()
	body.name = "CabinBody"
	root.add_child(body)

	var wood := mat(Color(0.33, 0.21, 0.11), 0.9)
	var wood_dark := mat(Color(0.22, 0.14, 0.08), 0.95)
	var floor_m := mat(Color(0.30, 0.2, 0.12), 0.95)
	var roof_m := mat(Color(0.25, 0.15, 0.09), 0.95)
	var stone := mat(Color(0.42, 0.41, 0.40), 0.95)
	var cloth := mat(Color(0.45, 0.12, 0.10), 1.0)
	var cloth2 := mat(Color(0.75, 0.72, 0.62), 1.0)
	var flame := mat(Color(1.0, 0.5, 0.1), 0.5, 0.0, Color(1.0, 0.45, 0.05), 3.0)
	var flame2 := mat(Color(1.0, 0.85, 0.3), 0.5, 0.0, Color(1.0, 0.8, 0.2), 3.5)
	var window_mat := mat(Color(1.0, 0.8, 0.4), 0.5, 0.0, Color(1.0, 0.75, 0.3), 1.0)

	# floor + walls (door gap on the +Z side)
	solid_box(body, Vector3(6.0, 0.2, 5.0), Vector3(0, -0.07, 0), floor_m)
	solid_box(body, Vector3(0.25, 3.0, 5.0), Vector3(-2.875, 1.5, 0), wood)
	solid_box(body, Vector3(0.25, 3.0, 5.0), Vector3(2.875, 1.5, 0), wood)
	solid_box(body, Vector3(6.0, 3.0, 0.25), Vector3(0, 1.5, -2.375), wood)
	solid_box(body, Vector3(2.3, 3.0, 0.25), Vector3(-1.85, 1.5, 2.375), wood)
	solid_box(body, Vector3(2.3, 3.0, 0.25), Vector3(1.85, 1.5, 2.375), wood)
	solid_box(body, Vector3(1.4, 0.7, 0.25), Vector3(0, 2.65, 2.375), wood)
	for cx in [-2.95, 2.95]:
		for cz in [-2.45, 2.45]:
			part(root, cyl(0.2, 0.2, 3.2, 8), wood_dark, Vector3(cx, 1.6, cz))

	# roof + gables + chimney
	var ang := rad_to_deg(atan2(1.4, 3.4))
	part(root, box(Vector3(3.9, 0.16, 5.8)), roof_m, Vector3(-1.7, 3.78, 0), Vector3(0, 0, ang))
	part(root, box(Vector3(3.9, 0.16, 5.8)), roof_m, Vector3(1.7, 3.78, 0), Vector3(0, 0, -ang))
	part(root, prism(6.0, 1.4, 0.2), wood, Vector3(0, 3.7, 2.38))
	part(root, prism(6.0, 1.4, 0.2), wood, Vector3(0, 3.7, -2.38))
	part(root, box(Vector3(0.9, 2.8, 0.9)), stone, Vector3(0, 4.0, -1.95))

	# open door leaf
	part(root, box(Vector3(0.08, 2.3, 0.8)), wood_dark, Vector3(-0.72, 1.15, 2.78))

	# fireplace
	solid_box(body, Vector3(1.8, 0.25, 0.9), Vector3(0, 0.155, -1.8), stone)
	solid_box(body, Vector3(1.8, 2.6, 0.35), Vector3(0, 1.3, -2.075), stone)
	solid_box(body, Vector3(0.3, 1.3, 0.9), Vector3(-0.75, 0.65, -1.8), stone)
	solid_box(body, Vector3(0.3, 1.3, 0.9), Vector3(0.75, 0.65, -1.8), stone)
	part(root, cyl(0.07, 0.07, 0.8, 6), wood_dark, Vector3(0, 0.36, -1.8), Vector3(0, 0, 90))
	part(root, cyl(0.0, 0.22, 0.55, 6), flame, Vector3(0, 0.66, -1.8))
	part(root, cyl(0.0, 0.12, 0.35, 6), flame2, Vector3(0, 0.6, -1.8))
	var fire_light := OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.position = Vector3(0, 0.9, -1.4)
	fire_light.omni_range = 8.0
	fire_light.light_energy = 1.8
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	root.add_child(fire_light)

	# crafting table
	part(root, box(Vector3(1.5, 0.1, 0.8)), wood_dark, Vector3(2.0, 0.95, -1.7))
	for dx in [-0.65, 0.65]:
		for dz in [-0.3, 0.3]:
			part(root, box(Vector3(0.1, 0.9, 0.1)), wood_dark, Vector3(2.0 + dx, 0.47, -1.7 + dz))
	col_box(body, Vector3(1.5, 0.95, 0.8), Vector3(2.0, 0.475, -1.7))
	part(root, box(Vector3(0.35, 0.05, 0.15)), dark_iron_mat(), Vector3(1.8, 1.03, -1.7), Vector3(0, 20, 0))

	# bed
	part(root, box(Vector3(1.0, 0.4, 2.0)), wood_dark, Vector3(-2.2, 0.23, -1.0))
	part(root, box(Vector3(0.9, 0.15, 1.9)), cloth2, Vector3(-2.2, 0.5, -1.0))
	part(root, box(Vector3(0.92, 0.12, 1.0)), cloth, Vector3(-2.2, 0.58, -0.6))
	part(root, box(Vector3(0.7, 0.12, 0.4)), cloth2, Vector3(-2.2, 0.62, -1.8))
	col_box(body, Vector3(1.0, 0.7, 2.0), Vector3(-2.2, 0.35, -1.0))

	# lighting
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 2.5, 0.3)
	lamp.omni_range = 7.0
	lamp.light_energy = 0.6
	lamp.light_color = Color(1.0, 0.8, 0.5)
	root.add_child(lamp)
	part(root, sph(0.1, 8, 4), flame2, Vector3(0, 2.6, 0.3))
	part(root, box(Vector3(0.06, 0.8, 1.0)), window_mat, Vector3(3.02, 1.8, 0.4))
	part(root, box(Vector3(0.06, 0.8, 1.0)), window_mat, Vector3(-3.02, 1.8, -0.4))
	root.set_meta("window_mat", window_mat)

	# door barrier: only cannibals (collision layer 3) are blocked by it
	var barrier := StaticBody3D.new()
	barrier.name = "DoorBarrier"
	barrier.collision_layer = 4
	barrier.collision_mask = 0
	var bcs := CollisionShape3D.new()
	var bbs := BoxShape3D.new()
	bbs.size = Vector3(1.4, 2.4, 0.3)
	bcs.shape = bbs
	bcs.position = Vector3(0, 1.2, 2.375)
	barrier.add_child(bcs)
	root.add_child(barrier)
	return root


static func dark_iron_mat() -> StandardMaterial3D:
	return mat(Color(0.18, 0.18, 0.2), 0.4, 0.9)
