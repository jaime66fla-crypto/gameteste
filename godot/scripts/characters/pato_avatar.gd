extends "res://scripts/characters/downloaded_avatar.gd"
## Pato Tático: corpo do Manequim (rig Mixamo) com farda camuflada, braços
## laranja, luvas, cabeça de pato com boné e headset, colete e coturnos.
## Modelo gerado por tools/characters/build_pato_model.gd. Usa todos os
## clipes, IK e camadas de pose do adaptador Mixamo.

func _init() -> void:
	model_path = "res://assets/personagens/pato/pato_modelo.scn"
	# Topo do headset; com isso o pato fica com 1,8 m como os outros.
	source_height = 1.877
