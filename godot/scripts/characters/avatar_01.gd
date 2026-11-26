extends "res://scripts/characters/downloaded_avatar.gd"
## Personagem 01: humano low-poly magro e facetado, com pele humana (pele.png,
## layout UV do MakeHuman: base para roupas/skins pintadas na textura).
## Corpo do MPFB (MakeHuman, anatomia real) com o rig "mixamo" e os pesos dele,
## reduzido e sombreado facetado por tools/blender/build_01.py; convertido para
## o esqueleto Mixamo do jogo por tools/characters/build_mannequin_model.gd -- --id=01.
## Usa todos os clipes, IK e camadas de pose do adaptador Mixamo (como o Manequim).

func _init() -> void:
	model_path = "res://assets/personagens/01/01_modelo.scn"
	# Topo da cabeça; com isso o 01 fica com 1,8 m como os outros.
	source_height = 1.858
