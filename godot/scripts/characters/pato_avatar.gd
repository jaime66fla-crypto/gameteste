extends "res://scripts/characters/downloaded_avatar.gd"
## Pato Tático: farda camuflada com manga dobrada, braços laranja, luvas,
## cabeça de pato com boné e headset, colete com bolsos, joelheiras e coturnos.
## Modelado no Blender (tools/blender/build_characters.py) e religado no esqueleto
## Ch31 por tools/characters/build_blender_characters.gd; usa todos os clipes,
## IK e camadas de pose do adaptador Mixamo sem retarget.

func _init() -> void:
	model_path = "res://assets/personagens/blender/pato_modelo.scn"
	# Topo do headset; com isso o pato fica com 1,8 m como os outros.
	source_height = 1.854
