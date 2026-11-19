extends SceneTree
## Lists the textures each selectable character's model really uses, with size
## and format, to spot oversized or uncompressed maps.
## godot --headless --path godot --script res://tools/characters/texture_audit.gd

const MODELS := [
	"res://assets/personagens/downloaded/avatar.fbx",
	"res://assets/personagens/remy/remy_modelo.scn",
	"res://assets/personagens/manequim/manequim_modelo.scn",
	"res://assets/personagens/zumbi/zumbi_modelo.scn",
]

func _init() -> void:
	for path in MODELS:
		var packed := load(path) as PackedScene
		if packed == null:
			print("MISSING ", path)
			continue
		var root := packed.instantiate()
		var seen := {}
		_walk(root, seen)
		print("== ", path)
		for tex_path in seen:
			print("   ", seen[tex_path], "  ", tex_path)
		root.free()
	quit()

func _walk(node: Node, seen: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var mat = node.get_surface_override_material(i)
			if mat == null:
				mat = node.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				for prop in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
					var tex: Texture2D = mat.get(prop)
					if tex != null and not seen.has(tex.resource_path):
						var img := tex.get_image()
						seen[tex.resource_path] = "%s %dx%d fmt=%d" % [prop, tex.get_width(), tex.get_height(), img.get_format() if img else -1]
	for child in node.get_children():
		_walk(child, seen)
