extends SceneTree
## Exporta as malhas "Roupa_*" do 01 (posição de repouso, normal, UV) para
## res://.godot/roupas_<peça>.json, usadas por tools/characters/paint_roupas.py.
## godot --headless --path godot --script res://tools/characters/export_roupas.gd
func _initialize() -> void:
	var root: Node = (load("res://assets/personagens/01/01_modelo.scn") as PackedScene).instantiate()
	for node in root.find_children("Roupa_*", "MeshInstance3D", true, false):
		if String(node.name) == "Roupa_tenis":
			continue # o tênis tem paleta própria (paint_tenis.py)
		var mi := node as MeshInstance3D
		var a := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var data := {"v": [], "n": [], "uv": [], "i": Array(idx)}
		for i in v.size():
			data.v.append([v[i].x, v[i].y, v[i].z])
			data.n.append([n[i].x, n[i].y, n[i].z])
			data.uv.append([uv[i].x, uv[i].y])
		var f := FileAccess.open("res://.godot/%s.json" % String(mi.name).to_lower(), FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		print("ROUPA ", mi.name, " ", v.size(), " vertices ", idx.size() / 3, " tris")
	root.free()
	quit()
