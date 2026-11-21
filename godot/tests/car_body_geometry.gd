extends SceneTree
const Car = preload("res://scripts/survival/car_model.gd")
var failures := 0
func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",what)
func _initialize() -> void:
	for kind in Car.KINDS:
		var builder := Car.Builder.new()
		var profile := Car._lower_profile(Car.KINDS[kind])
		var inner := builder._inset(profile,0.06)
		check(Geometry2D.triangulate_polygon(profile).size() == (profile.size()-2)*3, kind+": lower body contour is a simple triangulatable polygon")
		check(Geometry2D.triangulate_polygon(inner).size() == (inner.size()-2)*3, kind+": beveled side contour remains complete")
		for wreck in [false,true]:
			var model := Car.build(kind,"#c4d6bf",wreck,3)
			var body: MeshInstance3D = model.get_node("Body")
			var arrays: Array = body.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var half_width := float(Car.KINDS[kind].w)*0.5
			var side_area := 0.0
			for i in range(0,vertices.size(),3):
				if absf(vertices[i].x-half_width)<0.0001 and absf(vertices[i+1].x-half_width)<0.0001 and absf(vertices[i+2].x-half_width)<0.0001 and normals[i].x>0.99:
					side_area += (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()*0.5
			var expected := absf(builder._signed_area(inner))
			print(kind," wreck=",wreck," side area=",side_area," expected=",expected)
			check(side_area>=expected*0.99,kind+": painted side panel exists, including wreck variant "+str(wreck))
			model.free()
	print("CAR BODY GEOMETRY failures: ",failures)
	quit(1 if failures else 0)
