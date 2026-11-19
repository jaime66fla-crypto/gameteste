extends RefCounted
## Lotes e bases de parkour para os testes: os mesmos tipos que a Sobrevivência
## monta (data/survival_world.json "parkour" / "parkour_bases"), longe do campo
## de treino (x ≈ 400) e com chão próprio. Usado por tests/parkour_district.gd
## e tests/house_stairs.gd.
const District = preload("res://scripts/parkour_district.gd")
const X0 := 400.0
const SPACING := 16.0
const KINDS := ["sobrado", "sobrado", "pista", "sobrado", "terrea"]

## [{center: Vector2, yaw, kind, index}] — metade de frente para +Z, metade girada.
static func lots() -> Array:
	var result: Array = []
	for i in 10:
		result.append({"center": Vector2(X0 + i * SPACING, 0.0), "yaw": 0.0 if i < 5 else PI * 0.5, "kind": KINDS[i % 5], "index": i})
	return result

## [centro Vector2, rotação] das bases.
static func bases() -> Array:
	var result: Array = []
	var yaws := [0.0, PI, PI * 0.5, -PI * 0.5]
	for i in yaws.size():
		result.append([Vector2(X0 + i * SPACING, -22.0), yaws[i]])
	return result

static func build(parent: Node) -> Node3D:
	var floor_body := StaticBody3D.new()
	floor_body.name = "ParkourFixtureFloor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(220, 1, 90)
	shape.shape = box
	floor_body.position = Vector3(X0 + 72.0, -0.5, -10.0)
	floor_body.add_child(shape)
	parent.add_child(floor_body)
	var district: Node3D = District.new()
	var lot_data: Array = []
	for lot in lots():
		lot_data.append({"center": [lot["center"].x, lot["center"].y], "yaw": lot["yaw"], "kind": lot["kind"], "index": lot["index"]})
	var base_data: Array = []
	for spot in bases():
		base_data.append({"center": [spot[0].x, spot[0].y], "yaw": spot[1]})
	district.set("survival_lots", lot_data)
	district.set("survival_bases", base_data)
	parent.add_child(district)
	return district
