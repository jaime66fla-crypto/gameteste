extends SceneTree
## Tênis do personagem 01: peça "Roupa_tenis" calçada no pé do corpo.
##   godot --headless --path godot --script res://tools/characters/build_01_tenis.gd
## Rode de novo depois de build_mannequin_model.gd -- --id=01 (ele recria o
## 01_modelo.scn sem o tênis). Pode rodar quantas vezes quiser: substitui.
##
## O tênis é modelado no Blender (tools/blender/build_tenis.py -> roupas/tenis.glb:
## sola, cabedal, biqueira, língua, ilhoses, cadarço com laço). Aqui ele é
## calçado em cada pé: comprimento e largura ajustados ao pé medido, espelhado
## para o pé esquerdo, e cada vértice herda os pesos de osso do ponto mais
## próximo do pé (dobra com o pé em qualquer animação). As cores vêm de uma
## paleta 4 x 4 (UV no centro de cada célula): cada modelo da loja é só outra
## PNG (tools/characters/paint_tenis.py).
## No corpo, a pele do pé vira a superfície "Pele01-tenis": o jogo tira essa
## pele quando o tênis está calçado (avatar_01.gd), nada atravessa.
const MODEL := "res://assets/personagens/01/01_modelo.scn"
const TEXTURE := "res://assets/personagens/01/roupas/tenis.png"
const SHOE := "res://assets/personagens/01/roupas/tenis.glb"
const SHOE_LEN := 0.27 # comprimento do cabedal no Blender (L)
const SHOE_HALF_WIDTH := 0.045 # meia largura do antepé no Blender
const FOOT_TOP := 0.18 # acima disto não é pé
const GAP := 0.008 # folga do tênis sobre o pé
const SKIN_COVER := 0.085 # pele do corpo abaixo disto some com o tênis

func _initialize() -> void:
	var root: Node = (load(MODEL) as PackedScene).instantiate()
	var body := root.find_child("01", true, false) as MeshInstance3D
	if body == null:
		printerr("TENIS: corpo 01 não encontrado")
		quit(1)
		return
	var old := root.find_child("Roupa_tenis", true, false)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	var mesh := _merge_foot(body.mesh as ArrayMesh)
	var shoe := _shoe(mesh.surface_get_arrays(_surface(mesh, "Pele01")))
	shoe.surface_set_material(0, _material())
	var node := MeshInstance3D.new()
	node.name = "Roupa_tenis"
	node.mesh = shoe
	node.skin = body.skin
	node.visible = false
	body.get_parent().add_child(node)
	node.owner = root
	node.skeleton = node.get_path_to(body.get_node(body.skeleton))
	body.mesh = _split_skin(mesh)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, MODEL)
	print("TENIS: %d triângulos, salvo=%s" % [shoe.surface_get_array_len(0) / 3, error_string(err)])
	root.free()
	quit(0 if err == OK else 1)

func _surface(mesh: ArrayMesh, name: String) -> int:
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat != null and mat.resource_name == name:
			return s
	return -1

## Numa segunda rodada a pele do pé já está em "Pele01-tenis" (mesmos
## vértices da Pele01): volta para a Pele01 antes de cortar de novo.
func _merge_foot(mesh: ArrayMesh) -> ArrayMesh:
	var foot := _surface(mesh, "Pele01-tenis")
	if foot < 0:
		return mesh
	var out := ArrayMesh.new()
	var skin := _surface(mesh, "Pele01")
	for s in mesh.get_surface_count():
		if s == foot:
			continue
		var arrays := mesh.surface_get_arrays(s)
		if s == skin:
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			index.append_array(mesh.surface_get_arrays(foot)[Mesh.ARRAY_INDEX])
			arrays[Mesh.ARRAY_INDEX] = index
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out

# ------------------------------------------------------------------ forma

var _verts: PackedVector3Array
var _foot: Array[int] = []

func _shoe(a: Array) -> ArrayMesh:
	_verts = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / _verts.size()
	var src := _blender_shoe()
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var ob := PackedInt32Array()
	var ow := PackedFloat32Array()
	for side in [-1.0, 1.0]:
		_foot.clear()
		for i in _verts.size():
			if _verts[i].y < FOOT_TOP and signf(_verts[i].x) == side:
				_foot.append(i)
		var fit := _fit(side)
		var sv: PackedVector3Array = src.v
		var sn: PackedVector3Array = src.n
		var suv: PackedVector2Array = src.uv
		# Pé direito (x < 0) fica com o lado de fora para -X; o esquerdo é o
		# espelho e inverte a ordem dos triângulos.
		var mirror: bool = side > 0.0
		for t in range(0, sv.size(), 3):
			var order := [0, 2, 1] if mirror else [0, 1, 2]
			for j in order:
				var b: Vector3 = sv[t + j]
				var n: Vector3 = sn[t + j]
				var p := Vector3(fit.cx + b.x * fit.sx * (1.0 if mirror else -1.0), b.z * fit.sy, fit.z0 + b.y * fit.sz)
				ov.append(p)
				on.append(Vector3(n.x / fit.sx * (1.0 if mirror else -1.0), n.z / fit.sy, n.y / fit.sz).normalized())
				ouv.append(suv[t + j])
				var near := _nearest(p)
				for k in per:
					ob.append(bones[near * per + k])
					ow.append(weights[near * per + k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_BONES] = ob
	arrays[Mesh.ARRAY_WEIGHTS] = ow
	var shoe := ArrayMesh.new()
	shoe.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	return shoe

## Triângulos do GLB do Blender, de volta às coordenadas do Blender
## (x = lado de fora, y = frente, z = cima).
func _blender_shoe() -> Dictionary:
	var scene: Node3D = (load(SHOE) as PackedScene).instantiate()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := _xf_to(mi, scene)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var puv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(pv.size())
				for i in pv.size():
					idx[i] = i
			for i in idx:
				var p := xf * pv[i]
				var q := (xf.basis * pn[i]).normalized()
				v.append(Vector3(p.x, -p.z, p.y))
				n.append(Vector3(q.x, -q.z, q.y))
				uv.append(puv[i])
	scene.free()
	return {"v": v, "n": n, "uv": uv}

func _xf_to(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

## Escala e posição do tênis para o pé: comprimento e largura medidos no pé.
func _fit(side: float) -> Dictionary:
	var zmin := INF
	var zmax := -INF
	for i in _foot:
		zmin = minf(zmin, _verts[i].z)
		zmax = maxf(zmax, _verts[i].z)
	var x0 := INF
	var x1 := -INF
	var ball := lerpf(zmin, zmax, 0.68)
	for i in _foot:
		var p := _verts[i]
		if absf(p.z - ball) < 0.02 and p.y < 0.08:
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
	var foot_len := zmax - zmin + 2.0 * GAP
	var half := (x1 - x0) * 0.5 + GAP
	var sz := foot_len / SHOE_LEN
	return {"z0": zmin - GAP, "sz": sz, "sx": half / SHOE_HALF_WIDTH, "sy": lerpf(1.0, sz, 0.5), "cx": (x0 + x1) * 0.5}

## Vértice do pé mais próximo (de onde vêm os pesos de osso).
func _nearest(p: Vector3) -> int:
	var best := _foot[0]
	var bd := INF
	for i in _foot:
		var d := _verts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best

func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Roupa_tenis"
	mat.albedo_texture = load(TEXTURE)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # paleta: sem misturar cores
	mat.roughness = 0.82
	mat.metallic_specular = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## Superfície Pele01 do corpo dividida: a pele do pé vira "Pele01-tenis".
func _split_skin(mesh: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var mat := mesh.surface_get_material(s)
		var flags := mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var name := mat.resource_name if mat != null else ""
		if name != "Pele01":
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		var foot := PackedInt32Array()
		for t in range(0, index.size(), 3):
			var top := maxf(verts[index[t]].y, maxf(verts[index[t + 1]].y, verts[index[t + 2]].y))
			var list := foot if top < SKIN_COVER else keep
			list.append_array([index[t], index[t + 1], index[t + 2]])
		for part in [[keep, mat], [foot, _named(mat, "Pele01-tenis")]]:
			var copy := arrays.duplicate()
			copy[Mesh.ARRAY_INDEX] = part[0]
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy, [], {}, flags)
			out.surface_set_material(out.get_surface_count() - 1, part[1])
		print("TENIS: pele do pé %d triângulos" % (foot.size() / 3))
	return out

func _named(mat: Material, name: String) -> Material:
	var copy := mat.duplicate() as Material
	copy.resource_name = name
	return copy
