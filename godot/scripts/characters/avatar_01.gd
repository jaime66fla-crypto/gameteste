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
## O tênis é moldado no pé por tools/characters/build_01_tenis.gd (UV próprio,
## texturas de tools/characters/paint_tenis.py).

const PECAS := ["camiseta", "bermuda", "calca", "bone", "tenis"]
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")

## Itens vestidos (ids de data/store.json; o id básico de cada peça é o nome
## dela, ex. "bone"; variantes como "bone_vinho" trocam só a textura).
## Pode mudar a qualquer momento com vestir().
## Começa vestido (boné, camiseta e calça): é assim que os outros veem o 01.
@export var roupas: PackedStringArray = PackedStringArray(["bone", "camiseta", "calca"])

var _corpo: MeshInstance3D
var _corpo_mesh: ArrayMesh

func _init() -> void:
	model_path = "res://assets/personagens/01/01_modelo.scn"
	# Topo da cabeça; com isso o 01 fica com 1,8 m como os outros.
	source_height = 1.858

func _ready() -> void:
	super()
	_aplicar_roupas()

## Veste exatamente estes itens (os outros saem). Um item por peça, e calça e
## bermuda não vão juntas: o último da lista vence.
func vestir(itens: PackedStringArray) -> void:
	var lista := PackedStringArray()
	for id in itens:
		var p := _peca_do_item(id)
		if not p in PECAS or id in lista:
			continue
		for outro in lista.duplicate():
			var q := _peca_do_item(outro)
			if q == p or (p == "calca" and q == "bermuda") or (p == "bermuda" and q == "calca"):
				lista.erase(outro)
		lista.append(id)
	roupas = lista
	if is_inside_tree():
		_aplicar_roupas()

## Peça de um item da loja (ids antigos, só com o nome da peça, também valem).
func _peca_do_item(id: String) -> String:
	var p := StoreCatalog.piece(id)
	return p if not p.is_empty() else id

func _pecas_vestidas() -> PackedStringArray:
	var pecas := PackedStringArray()
	for id in roupas:
		pecas.append(_peca_do_item(id))
	return pecas

## Troca a textura (skin) de uma peça, ex.: trocar_textura("camiseta", load(...)).
## null volta para a textura original do modelo.
func trocar_textura(peca: String, textura: Texture2D) -> void:
	var no := _peca(peca)
	if no == null or no.mesh == null:
		return
	# Guarda o material original de cada superfície para voltar a ele depois.
	if not no.has_meta("material_original"):
		var originais := []
		for s in no.mesh.get_surface_count():
			originais.append(no.get_surface_override_material(s))
		no.set_meta("material_original", originais)
	var originais: Array = no.get_meta("material_original")
	var relevo := relevo_da_peca(peca)
	for s in no.mesh.get_surface_count():
		no.set_surface_override_material(s, originais[s])
		if textura == null and relevo == null:
			continue
		var mat := no.get_active_material(s) as StandardMaterial3D
		if mat == null:
			continue
		no.set_surface_override_material(s, vestir_material(mat, textura, relevo))

## Relevo do tecido da peça (roupas/<peça>_normal.png, de paint_roupas.py), ou null.
static func relevo_da_peca(peca: String) -> Texture2D:
	var caminho := "res://assets/personagens/01/roupas/%s_normal.png" % peca
	return load(caminho) as Texture2D if ResourceLoader.exists(caminho) else null

## Cópia do material da peça com a textura da skin (null = mantém) e o relevo.
static func vestir_material(mat: StandardMaterial3D, textura: Texture2D, relevo: Texture2D) -> StandardMaterial3D:
	mat = mat.duplicate() as StandardMaterial3D
	if textura != null:
		mat.albedo_texture = textura
	if relevo != null:
		mat.normal_enabled = true
		mat.normal_texture = relevo
		mat.normal_scale = 1.0
	return mat

func _peca(peca: String) -> MeshInstance3D:
	if _source_model == null:
		return null
	return _source_model.find_child("Roupa_" + peca, true, false) as MeshInstance3D

func _aplicar_roupas() -> void:
	if _source_model == null:
		return
	var vestidas := _pecas_vestidas()
	for p in PECAS:
		var no := _peca(p)
		if no != null:
			no.visible = p in vestidas
	for id in roupas:
		var caminho := StoreCatalog.texture_path(id)
		var textura: Texture2D = load(caminho) as Texture2D if not caminho.is_empty() and ResourceLoader.exists(caminho) else null
		trocar_textura(_peca_do_item(id), textura)
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
			if p in vestidas:
				mesh.surface_remove(s)
				break
	_corpo.mesh = mesh
