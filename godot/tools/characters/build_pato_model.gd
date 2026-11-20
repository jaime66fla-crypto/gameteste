extends SceneTree
## Builds "Pato Tático": the UAL2 mannequin body (already on the Mixamo rig, see
## build_mannequin_model.gd) repainted as camo uniform + orange arms + black
## gloves, plus rigid gear on BoneAttachment3D nodes: duck head and bill, cap,
## headset, neck gaiter, plate carrier with pouches and duck patches, belt,
## thigh holsters, cargo pockets, knee pads and desert boots.
## Every part shares one ShaderMaterial (pato.gdshader); one mesh per bone.
## Output: assets/personagens/pato/pato_modelo.scn
## godot --headless --path godot --script res://tools/characters/build_pato_model.gd
const SOURCE := "res://assets/personagens/manequim/manequim_modelo.scn"
const SHADER := "res://assets/personagens/pato/pato.gdshader"
const OUT_SCENE := "res://assets/personagens/pato/pato_modelo.scn"
const PREFIX := "mixamorig_"
# Paint kinds (COLOR.a), see pato.gdshader.
const SHIRT := 0.0
const PANTS := 1.0 / 3.0
const GEAR := 2.0 / 3.0
const SOLID := 1.0
const WHITE := Color("#e8e5de")
const BILL := Color("#f6bd45")
const SKIN := Color("#d99858")
const EYE := Color("#0d0d0e")
const CAP := Color("#141415")
const HEADSET := Color("#1c1d1f")
const HEADSET_RIM := Color("#2e3033")
const GLOVE := Color("#19191a")
const CUFF := Color("#3e3e35")
const BELT := Color("#161617")
const BUCKLE := Color("#9a7d52")
const BOOT := Color("#b09668")
const SOLE := Color("#4a3b2a")
const LACE := Color("#6e5a3c")
const PATCH := Color("#1d1d1e")
const DUCK := Color("#e6b21f")

var skeleton: Skeleton3D
var parts := {} # bone suffix -> {v, n, c, uv, uv2, i}
var top := 0.0

func _initialize() -> void:
	quit(0 if _build() else 1)

func _t(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var euler := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	return Transform3D(Basis.from_euler(euler) * Basis.from_scale(scale), pos)

func _sphere(rings: int = 12, segments: int = 24, hemisphere: bool = false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 1.0 if hemisphere else 2.0
	m.is_hemisphere = hemisphere
	m.rings = rings
	m.radial_segments = segments
	return m

func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _cyl(top_r: float, bottom_r: float, height: float, segments: int = 20) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m

## Adds a primitive placed in skeleton rest space (model faces +Z, metres) to
## the mesh that follows `bone`.
func _add(bone: String, prim: PrimitiveMesh, xf: Transform3D, color: Color, kind: float = SOLID, rough: float = 0.85) -> void:
	var b := skeleton.find_bone(PREFIX + bone)
	assert(b >= 0, bone)
	var to_bone := skeleton.get_bone_global_rest(b).affine_inverse()
	if not parts.has(bone):
		parts[bone] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "i": PackedInt32Array()}
	var p: Dictionary = parts[bone]
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var normal_basis := xf.basis.inverse().transposed()
	var base := (p["v"] as PackedVector3Array).size()
	var c := Color(color.r, color.g, color.b, kind)
	for k in verts.size():
		var rest := xf * verts[k]
		top = maxf(top, rest.y)
		p["v"].append(to_bone * rest)
		p["n"].append((to_bone.basis * (normal_basis * normals[k])).normalized())
		p["c"].append(c)
		p["uv"].append(Vector2(rough, 0.0))
		p["uv2"].append(Vector2(rest.x + rest.z * 0.7, rest.y))
	for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		p["i"].append(base + index)

## Orthonormal frame on a surface: x = right, y = up (in-plane), z = normal.
func _frame(normal: Vector3) -> Basis:
	var n := normal.normalized()
	var right := Vector3.UP.cross(n)
	right = Vector3.RIGHT if right.length() < 0.01 else right.normalized()
	return Basis(right, n.cross(right), n)

## Square patch with a yellow duck, flat on a surface facing `normal`.
func _duck_patch(bone: String, center: Vector3, normal: Vector3, half: float) -> void:
	var f := _frame(normal)
	var n := f.z
	_add(bone, _box(Vector3(half * 2.0, half * 2.0, 0.006)), Transform3D(f, center + n * 0.003), PATCH, SOLID, 0.95)
	var disk := func(offset: Vector2, radii: Vector2, color: Color, lift: float) -> void:
		var basis := Basis(f.x * radii.x, n * 0.003, -f.y * radii.y) # right-handed
		_add(bone, _cyl(1.0, 1.0, 1.0, 16), Transform3D(basis, center + f.x * offset.x + f.y * offset.y + n * lift), color, SOLID, 0.6)
	disk.call(Vector2(-0.05, -0.28) * half, Vector2(0.55, 0.36) * half, DUCK, 0.0075)
	disk.call(Vector2(-0.55, -0.12) * half, Vector2(0.17, 0.12) * half, DUCK, 0.0075)
	disk.call(Vector2(0.27, 0.3) * half, Vector2(0.27, 0.27) * half, DUCK, 0.0078)
	disk.call(Vector2(0.58, 0.24) * half, Vector2(0.16, 0.08) * half, BILL, 0.0082)
	disk.call(Vector2(0.33, 0.38) * half, Vector2(0.05, 0.05) * half, EYE, 0.0085)

## Thin rod between two points.
func _rod(bone: String, a: Vector3, b: Vector3, radius: float, color: Color, rough: float = 0.5) -> void:
	var dir := b - a
	var basis := Basis(Quaternion(Vector3.UP, dir.normalized())) * Basis.from_scale(Vector3(1.0, dir.length(), 1.0))
	_add(bone, _cyl(radius, radius, 1.0, 8), Transform3D(basis, (a + b) * 0.5), color, SOLID, rough)

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 6
	return m

func _head() -> void:
	var c := Vector3(0, 1.682, 0.014)
	_add("Head", _sphere(16, 32), _t(c, Vector3.ZERO, Vector3(0.132, 0.155, 0.142)), WHITE, SOLID, 0.7)
	# Full cheeks around the bill.
	for side in [-1.0, 1.0]:
		_add("Head", _sphere(10, 18), _t(Vector3(side * 0.052, 1.622, 0.07), Vector3.ZERO, Vector3(0.078, 0.07, 0.08)), WHITE, SOLID, 0.7)
	# Bill: wide and flat, upper half over a slightly darker lower half.
	_add("Head", _sphere(12, 24), _t(Vector3(0, 1.62, 0.168), Vector3(-5, 0, 0), Vector3(0.1, 0.031, 0.128)), BILL, SOLID, 0.42)
	_add("Head", _sphere(10, 20), _t(Vector3(0, 1.595, 0.152), Vector3(3, 0, 0), Vector3(0.086, 0.023, 0.104)), BILL.darkened(0.14), SOLID, 0.5)
	for side in [-1.0, 1.0]:
		_add("Head", _sphere(6, 8), _t(Vector3(side * 0.02, 1.647, 0.24), Vector3.ZERO, Vector3(0.008, 0.003, 0.005)), BILL.darkened(0.5), SOLID, 0.5)
	# Angry eyes: dark eye, catchlight, slanted lid and brow (inner end low).
	for side in [-1.0, 1.0]:
		var x: float = side * 0.052
		var yaw: float = side * 22.0
		_add("Head", _sphere(10, 16), _t(Vector3(x, 1.668, 0.141), Vector3(0, yaw, 0), Vector3(0.027, 0.025, 0.012)), EYE, SOLID, 0.12)
		_add("Head", _sphere(6, 8), _t(Vector3(x - side * 0.007, 1.674, 0.152), Vector3.ZERO, Vector3.ONE * 0.005), WHITE, SOLID, 0.1)
		_add("Head", _box(Vector3(0.062, 0.028, 0.026)), _t(Vector3(x + side * 0.004, 1.686, 0.141), Vector3(0, yaw, side * 24.0)), Color("#d9d5cd"), SOLID, 0.7)
		_add("Head", _box(Vector3(0.064, 0.012, 0.03)), _t(Vector3(x + side * 0.004, 1.7, 0.139), Vector3(0, yaw, side * 24.0)), Color("#2a2a2c"), SOLID, 0.7)
	# Cap: crown pulled low, curved rounded brim, button and grey logo.
	_add("Head", _sphere(12, 32, true), _t(Vector3(0, 1.73, 0.0), Vector3(7, 0, 0), Vector3(0.145, 0.132, 0.156)), CAP, SOLID, 0.9)
	_add("Head", _sphere(8, 28), _t(Vector3(0, 1.713, 0.2), Vector3(10, 0, 0), Vector3(0.12, 0.012, 0.105)), CAP, SOLID, 0.9)
	_add("Head", _sphere(6, 10), _t(Vector3(0, 1.86, -0.008), Vector3.ZERO, Vector3.ONE * 0.012), CAP, SOLID, 0.9)
	var logo_n := Vector3(0, 0.42, 0.91).normalized()
	_add("Head", _cyl(1.0, 1.0, 1.0, 16), Transform3D(Basis(Quaternion(Vector3.UP, logo_n)) * Basis.from_scale(Vector3(0.026, 0.003, 0.026)), Vector3(0, 1.79, 0.133)), Color("#5f6062"), SOLID, 0.7)
	# Headset: chunky ear cups, padded band over the cap, mic boom on the left.
	for side in [-1.0, 1.0]:
		_add("Head", _cyl(0.064, 0.064, 0.05), _t(Vector3(side * 0.14, 1.67, 0.0), Vector3(0, 0, 90)), HEADSET, SOLID, 0.45)
		_add("Head", _cyl(0.05, 0.05, 0.066), _t(Vector3(side * 0.143, 1.67, 0.0), Vector3(0, 0, 90)), HEADSET_RIM, SOLID, 0.35)
		_add("Head", _box(Vector3(0.02, 0.07, 0.03)), _t(Vector3(side * 0.152, 1.72, 0.0)), HEADSET, SOLID, 0.45)
	var center := Vector3(0, 1.672, 0.0)
	var steps := 11
	for k in steps:
		var a0 := deg_to_rad(14.0 + 152.0 * k / steps)
		var a1 := deg_to_rad(14.0 + 152.0 * (k + 1) / steps)
		var p0 := center + Vector3(cos(a0) * 0.162, sin(a0) * 0.2, 0)
		var p1 := center + Vector3(cos(a1) * 0.162, sin(a1) * 0.2, 0)
		var along := (p1 - p0)
		var basis := Basis(along.normalized(), Vector3(0, 0, 1).cross(along.normalized()), Vector3(0, 0, 1))
		_add("Head", _box(Vector3(along.length() + 0.004, 0.016, 0.038)), Transform3D(basis, (p0 + p1) * 0.5), HEADSET, SOLID, 0.5)
	_rod("Head", Vector3(0.155, 1.64, 0.035), Vector3(0.11, 1.6, 0.14), 0.006, HEADSET)
	_add("Head", _sphere(6, 10), _t(Vector3(0.108, 1.598, 0.145), Vector3.ZERO, Vector3.ONE * 0.013), HEADSET, SOLID, 0.6)

func _torso() -> void:
	# Bunched camo neck gaiter.
	_add("Neck", _cyl(0.11, 0.14, 0.12), _t(Vector3(0, 1.53, -0.01), Vector3.ZERO, Vector3(1, 1, 0.92)), Color.WHITE, GEAR, 0.95)
	_add("Neck", _sphere(8, 20), _t(Vector3(0, 1.48, -0.012), Vector3.ZERO, Vector3(0.165, 0.045, 0.15)), Color.WHITE, GEAR, 0.95)
	# Plate carrier: plates, shoulder straps, MOLLE rows, duck patches.
	_add("Spine2", _box(Vector3(0.35, 0.29, 0.055)), _t(Vector3(0, 1.31, 0.168)), Color.WHITE, SHIRT, 0.9)
	_add("Spine2", _box(Vector3(0.35, 0.32, 0.055)), _t(Vector3(0, 1.31, -0.198)), Color.WHITE, SHIRT, 0.9)
	for side in [-1.0, 1.0]:
		_add("Spine2", _box(Vector3(0.085, 0.03, 0.36)), _t(Vector3(side * 0.11, 1.5, -0.015)), Color.WHITE, SHIRT, 0.9)
	for k in 4:
		var y := 1.215 + k * 0.05
		_add("Spine2", _box(Vector3(0.33, 0.012, 0.006)), _t(Vector3(0, y, 0.197)), Color("#2b2b27"), SOLID, 0.9)
		_add("Spine2", _box(Vector3(0.33, 0.012, 0.006)), _t(Vector3(0, y + 0.02, -0.227)), Color("#2b2b27"), SOLID, 0.9)
	_duck_patch("Spine2", Vector3(0.0, 1.4, 0.196), Vector3(0, 0, 1), 0.036)
	_duck_patch("Spine2", Vector3(0.0, 1.385, -0.226), Vector3(0, 0, -1), 0.065)
	# Cummerbund around the waist, with a row of four pouches in front.
	_add("Spine1", _cyl(0.205, 0.2, 0.15, 28), _t(Vector3(0, 1.165, -0.012), Vector3.ZERO, Vector3(1, 1, 0.84)), Color.WHITE, SHIRT, 0.9)
	for k in 4:
		var x := -0.123 + k * 0.082
		_add("Spine1", _box(Vector3(0.076, 0.12, 0.066)), _t(Vector3(x, 1.135, 0.183)), Color.WHITE, GEAR, 0.9)
		_add("Spine1", _box(Vector3(0.08, 0.034, 0.072)), _t(Vector3(x, 1.19, 0.184)), Color.WHITE, SHIRT, 0.9)
		_add("Spine1", _box(Vector3(0.016, 0.02, 0.004)), _t(Vector3(x, 1.18, 0.221)), Color("#2b2b27"), SOLID, 0.6)
	for side in [-1.0, 1.0]:
		_add("Spine1", _box(Vector3(0.055, 0.12, 0.1)), _t(Vector3(side * 0.205, 1.15, 0.0)), Color.WHITE, SHIRT, 0.9)
	# Belt with tan keepers and buckle.
	_add("Hips", _cyl(0.186, 0.186, 0.052, 28), _t(Vector3(0, 0.975, -0.003), Vector3.ZERO, Vector3(1, 1, 0.75)), BELT, SOLID, 0.7)
	_add("Hips", _box(Vector3(0.058, 0.04, 0.014)), _t(Vector3(0, 0.975, 0.14)), BUCKLE, SOLID, 0.5)
	for side in [-1.0, 1.0]:
		_add("Hips", _box(Vector3(0.024, 0.07, 0.014)), _t(Vector3(side * 0.1, 0.97, 0.122), Vector3(0, side * 30.0, 0)), BUCKLE, SOLID, 0.8)

func _arms() -> void:
	for side in [-1.0, 1.0]:
		var arm := "LeftArm" if side > 0 else "RightArm"
		var hand := "LeftHand" if side > 0 else "RightHand"
		# Rolled olive sleeve cuff and shoulder duck patch (faces out once the arm hangs).
		_add(arm, _cyl(0.081, 0.081, 0.06), _t(Vector3(side * 0.325, 1.437, -0.066), Vector3(0, 0, 90)), CUFF, SOLID, 0.95)
		_add(arm, _cyl(0.084, 0.084, 0.018), _t(Vector3(side * 0.348, 1.437, -0.066), Vector3(0, 0, 90)), CUFF.darkened(0.2), SOLID, 0.95)
		var patch_n := Vector3(0, 0.86, 0.5).normalized()
		_duck_patch(arm, Vector3(side * 0.245, 1.437, -0.066) + patch_n * 0.077, patch_n, 0.03)
		# Glove cuff and knuckle guard.
		_add(hand, _cyl(0.062, 0.058, 0.055), _t(Vector3(side * 0.738, 1.435, -0.068), Vector3(0, 0, 90)), GLOVE, SOLID, 0.6)
		_add(hand, _box(Vector3(0.06, 0.016, 0.078)), _t(Vector3(side * 0.805, 1.476, -0.066)), Color("#2b2c2e"), SOLID, 0.45)

func _legs() -> void:
	for side in [-1.0, 1.0]:
		var pre := "Left" if side > 0 else "Right"
		var x: float = side * 0.089
		# Holster (right) / magazine pouch (left) on two leg straps.
		var holster := Vector3(side * 0.212, 0.8, 0.005)
		_add(pre + "UpLeg", _box(Vector3(0.05, 0.18 if side < 0 else 0.14, 0.1)), _t(holster), BELT, SOLID, 0.6)
		if side < 0:
			_add(pre + "UpLeg", _box(Vector3(0.04, 0.065, 0.048)), _t(holster + Vector3(0, 0.105, -0.015), Vector3(-15, 0, 0)), Color("#222325"), SOLID, 0.4)
		for y in [0.765, 0.69]:
			_add(pre + "UpLeg", _cyl(0.118, 0.118, 0.024), _t(Vector3(x + side * 0.004, y, 0.0)), BELT, SOLID, 0.7)
		_rod(pre + "UpLeg", Vector3(side * 0.19, 0.96, 0.0), holster + Vector3(0, 0.085, 0), 0.011, BELT)
		# Cargo pocket with flap.
		_add(pre + "UpLeg", _box(Vector3(0.03, 0.14, 0.12)), _t(Vector3(side * 0.178, 0.585, 0.01)), Color.WHITE, PANTS, 0.95)
		_add(pre + "UpLeg", _box(Vector3(0.034, 0.035, 0.125)), _t(Vector3(side * 0.18, 0.655, 0.01)), Color.WHITE, GEAR, 0.95)
		# Knee pad with strap.
		_add(pre + "Leg", _sphere(10, 18), _t(Vector3(x, 0.515, 0.074), Vector3.ZERO, Vector3(0.068, 0.084, 0.04)), Color("#1a1b1c"), SOLID, 0.32)
		_add(pre + "Leg", _cyl(0.088, 0.088, 0.022), _t(Vector3(x, 0.47, 0.0)), BELT, SOLID, 0.7)
		# Trousers bloused over the boot.
		_add(pre + "Leg", _sphere(8, 18), _t(Vector3(x, 0.315, -0.025), Vector3.ZERO, Vector3(0.09, 0.04, 0.095)), Color.WHITE, PANTS, 0.95)
		# Desert boots: padded shaft on the shin, rounded body and sole on the foot.
		_add(pre + "Leg", _cyl(0.08, 0.074, 0.25), _t(Vector3(x, 0.17, -0.028)), BOOT, SOLID, 0.95)
		_add(pre + "Leg", _cyl(0.083, 0.083, 0.03), _t(Vector3(x, 0.29, -0.028)), BOOT.darkened(0.12), SOLID, 0.95)
		for k in 5:
			var lace_y := 0.1 + k * 0.038
			for tilt in [-25.0, 25.0]:
				_add(pre + "Leg", _box(Vector3(0.05, 0.006, 0.006)), _t(Vector3(x, lace_y, 0.05), Vector3(0, 0, tilt)), LACE, SOLID, 0.9)
		_add(pre + "Foot", _capsule(0.064, 0.31), _t(Vector3(x, 0.058, 0.055), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.78)), BOOT, SOLID, 0.95)
		_add(pre + "Foot", _capsule(0.066, 0.32), _t(Vector3(x, 0.016, 0.056), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.22)), SOLE, SOLID, 0.95)

## Paint for a body-mesh vertex at rest: [color, kind, roughness].
func _body_paint(v: Vector3) -> Array:
	var ax := absf(v.x)
	if v.y > 1.3 and ax > 0.29:
		if ax > 0.7:
			return [GLOVE, SOLID, 0.6]
		if ax > 0.345:
			return [SKIN, SOLID, 0.75]
		return [Color.WHITE, SHIRT, 0.95]
	if v.y > 1.6:
		return [WHITE, SOLID, 0.7]
	if v.y > 1.45:
		return [Color.WHITE, GEAR, 0.95] # neck, under the gaiter
	if v.y > 0.97:
		return [Color.WHITE, SHIRT, 0.95]
	if v.y > 0.3:
		return [Color.WHITE, PANTS, 0.95]
	return [BOOT, SOLID, 0.95]

## How far (m) a body vertex is pushed along its normal: thick arms and big
## gloves, a bulkier chest and baggy cargo trousers, like the reference.
## Continuous in position so the mesh never cracks between regions.
func _inflate(v: Vector3) -> float:
	var ax := absf(v.x)
	if v.y > 1.3 and ax > 0.25:
		return lerpf(0.017, 0.011, smoothstep(0.68, 0.72, ax))
	if v.y > 1.55:
		return 0.0
	if v.y > 0.97:
		return 0.017
	var pants := lerpf(0.017, 0.03, 1.0 - smoothstep(0.88, 0.97, v.y))
	return lerpf(0.016, pants, smoothstep(0.3, 0.42, v.y))

func _build() -> bool:
	var model := (load(SOURCE) as PackedScene).instantiate() as Node3D
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var body := model.find_child("Manequim", true, false) as MeshInstance3D
	if skeleton == null or body == null:
		printerr("PATO: manequim não carregou")
		return false
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	model.name = "PatoModelo"
	body.name = "Pato"
	# Repaint the body mesh.
	var mesh := ArrayMesh.new()
	for s in body.mesh.get_surface_count():
		var arrays := body.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for k in verts.size():
			var v := verts[k]
			verts[k] = v + normals[k] * _inflate(v)
			var paint := _body_paint(v)
			var col: Color = paint[0]
			colors.append(Color(col.r, col.g, col.b, paint[1]))
			uv.append(Vector2(paint[2], 0.0))
			uv2.append(Vector2(v.x + v.z * 0.7, v.y))
			top = maxf(top, v.y)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var flags: int = body.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(s, material)
	body.mesh = mesh
	# Gear.
	_head()
	_torso()
	_arms()
	_legs()
	var bones := parts.keys()
	bones.sort()
	for bone in bones:
		var p: Dictionary = parts[bone]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = p["v"]
		arrays[Mesh.ARRAY_NORMAL] = p["n"]
		arrays[Mesh.ARRAY_COLOR] = p["c"]
		arrays[Mesh.ARRAY_TEX_UV] = p["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = p["uv2"]
		arrays[Mesh.ARRAY_INDEX] = p["i"]
		var gear := ArrayMesh.new()
		gear.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		gear.surface_set_material(0, material)
		var attach := BoneAttachment3D.new()
		attach.name = "Equip_" + bone
		attach.bone_name = PREFIX + bone
		skeleton.add_child(attach)
		attach.owner = model
		var mi := MeshInstance3D.new()
		mi.name = "Malha"
		mi.mesh = gear
		attach.add_child(mi)
		mi.owner = model
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_SCENE.get_base_dir()))
	var scene := PackedScene.new()
	var err := scene.pack(model)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_SCENE, ResourceSaver.FLAG_COMPRESS)
	print("PATO: topo %.3f m  peças em %d ossos  cena %s" % [top, bones.size(), error_string(err)])
	model.free()
	return err == OK
