extends SceneTree
## Exports the Ch31 Mixamo skeleton (the rig every clip is authored on) as joint
## positions for the Blender character builder (tools/blender/build_characters.py).
## Positions are model space in metres, Godot axes (Y up, model faces +Z).
## godot --headless --path godot --script res://tools/characters/export_rig_joints.gd
const SOURCE := "res://assets/personagens/downloaded/avatar.fbx"
const OUT := "res://tools/blender/ch31_rig.json"

func _initialize() -> void:
	var root := (load(SOURCE) as PackedScene).instantiate() as Node3D
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var xf := Transform3D.IDENTITY
	var node: Node = sk
	while node != root:
		xf = (node as Node3D).transform * xf
		node = node.get_parent()
	print("skeleton -> root: ", xf)
	var bones := []
	for i in sk.get_bone_count():
		var p := xf * sk.get_bone_global_rest(i).origin
		bones.append({
			"name": String(sk.get_bone_name(i)),
			"parent": String(sk.get_bone_name(sk.get_bone_parent(i))) if sk.get_bone_parent(i) >= 0 else "",
			"pos": [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)],
		})
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": SOURCE, "bones": bones}, "\t"))
	file.close()
	print("%d bones -> %s" % [bones.size(), OUT])
	root.free()
	quit(0)
