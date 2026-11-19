extends "res://scripts/characters/downloaded_avatar.gd"
## Remy: sobrevivente civil (Mixamo, camiseta, bermuda cargo e tênis).
## Usa todos os clipes, IK e camadas de pose do adaptador Mixamo; o modelo
## vem de tools/characters/build_remy_model.gd já em metros (1,8 m de altura).

func _init() -> void:
	model_path = "res://assets/personagens/remy/remy_modelo.scn"
	source_height = 1.8
