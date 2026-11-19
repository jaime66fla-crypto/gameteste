extends "res://scripts/characters/downloaded_avatar.gd"
## Manequim: o boneco da Universal Animation Library 2 (Quaternius, CC0),
## convertido para esqueleto Mixamo por tools/characters/build_mannequin_model.gd.
## Usa todos os clipes, IK e camadas de pose do adaptador Mixamo.

func _init() -> void:
	model_path = "res://assets/personagens/manequim/manequim_modelo.scn"
	source_height = 1.83
