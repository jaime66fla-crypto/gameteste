extends SceneTree
## Lista animações, esqueleto e tamanho dos modelos de animais (assets/animais).
## godot --headless --path godot --script res://tools/survival/inspect_animals.gd
func _init() -> void:
	for kind in ["rabbit", "stag", "pig", "wolf"]:
		var scene: PackedScene = load("res://assets/animais/%s.glb" % kind)
		if scene == null:
			print(kind, ": não carregou")
			continue
		var root := scene.instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		var anims: Array = []
		for p in players:
			anims.append_array((p as AnimationPlayer).get_animation_list())
		var box := AABB()
		var first := true
		for m in root.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var t := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != root:
				if n is Node3D:
					t = (n as Node3D).transform * t
				n = n.get_parent()
			var b := t * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var skel := root.find_children("*", "Skeleton3D", true, false)
		print("%s: size=%s pos=%s skel=%d anims=%s" % [kind, box.size, box.position, skel.size(), anims])
		root.free()
	quit()
