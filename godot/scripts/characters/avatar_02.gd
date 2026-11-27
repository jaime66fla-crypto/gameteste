extends "res://scripts/characters/downloaded_avatar.gd"
## Personagem 02: humano realista do MakeHuman (assets CC0 do próprio MakeHuman:
## pele, olhos, sobrancelhas, cílios, cabelo curto escuro, jaqueta, jeans e bota),
## gerado por tools/blender/build_02.py e convertido para o esqueleto Mixamo do
## jogo por tools/characters/build_mannequin_model.gd -- --id=02.
## Usa todos os clipes, IK e camadas de pose do adaptador Mixamo (como o 01).

func _init() -> void:
	model_path = "res://assets/personagens/02/02_modelo.scn"
	source_height = 1.875
