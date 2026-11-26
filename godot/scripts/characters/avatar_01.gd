extends "res://scripts/characters/downloaded_avatar.gd"
## Personagem 01: humano low-poly magro e facetado, com pele humana (pele.png,
## layout UV do MakeHuman).
## Corpo do MPFB (MakeHuman, anatomia real) com o rig "mixamo" e os pesos dele,
## reduzido e sombreado facetado por tools/blender/build_01.py; convertido para
## o esqueleto Mixamo do jogo por tools/characters/build_mannequin_model.gd -- --id=01.
## Usa todos os clipes, IK e camadas de pose do adaptador Mixamo (como o Manequim).
##
## Roupas (skins): malhas separadas "Roupa_<peça>" no mesmo esqueleto, moldadas
## no próprio corpo (tools/blender/build_01_roupas.py). A pele que fica 100%
## coberta está em superfícies "Pele01-<peças>": vestir uma peça tira essas
## superfícies do corpo, então a pele nunca atravessa o tecido em movimento.
## Cada peça usa uma textura no layout UV do MakeHuman: skin nova = outra PNG.

const PECAS := ["camiseta", "bermuda", "calca", "bone"]

## Peças vestidas (ids de PECAS). Pode mudar a qualquer momento com vestir().
@export var roupas: PackedStringArray = PackedStringArray()

var _corpo: MeshInstance3D
var _corpo_mesh: ArrayMesh

func _init() -> void:
	model_path = "res://assets/personagens/01/01_modelo.scn"
	# Topo da cabeça; com isso o 01 fica com 1,8 m como os outros.
	source_height = 1.858

func _ready() -> void:
	super()
	_aplicar_roupas()

## Veste exatamente estas peças (as outras saem). Calça e bermuda não vão juntas:
## a última da lista vence.
func vestir(pecas: PackedStringArray) -> void:
	var lista := PackedStringArray()
	for p in pecas:
		if not p in PECAS or p in lista:
			continue
		if p == "calca":
			lista.erase("bermuda")
		elif p == "bermuda":
			lista.erase("calca")
		lista.append(p)
	roupas = lista
	if is_inside_tree():
		_aplicar_roupas()

## Troca a textura (skin) de uma peça, ex.: trocar_textura("camiseta", load(...)).
func trocar_textura(peca: String, textura: Texture2D) -> void:
	var no := _peca(peca)
	if no == null or no.mesh == null:
		return
	for s in no.mesh.get_surface_count():
		var mat := no.get_active_material(s) as StandardMaterial3D
		if mat == null:
			continue
		mat = mat.duplicate() as StandardMaterial3D
		mat.albedo_texture = textura
		no.set_surface_override_material(s, mat)

func _peca(peca: String) -> MeshInstance3D:
	if _source_model == null:
		return null
	return _source_model.find_child("Roupa_" + peca, true, false) as MeshInstance3D

func _aplicar_roupas() -> void:
	if _source_model == null:
		return
	for p in PECAS:
		var no := _peca(p)
		if no != null:
			no.visible = p in roupas
	if _corpo == null:
		_corpo = _source_model.find_child("01", true, false) as MeshInstance3D
		if _corpo == null:
			return
		_corpo_mesh = _corpo.mesh as ArrayMesh
	# Corpo sem as superfícies de pele cobertas pelas peças vestidas.
	var mesh := _corpo_mesh.duplicate() as ArrayMesh
	for s in range(mesh.get_surface_count() - 1, -1, -1):
		var mat := mesh.surface_get_material(s)
		var nome := mat.resource_name if mat != null else ""
		if not nome.begins_with("Pele01-"):
			continue
		for p in nome.trim_prefix("Pele01-").split("-"):
			if p in roupas:
				mesh.surface_remove(s)
				break
	_corpo.mesh = mesh
