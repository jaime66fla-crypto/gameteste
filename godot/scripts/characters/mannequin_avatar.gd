extends "res://scripts/characters/downloaded_avatar.gd"
## Manequim: boneco de testes segmentado (cascas mostarda, juntas roxas).
## Modelado no Blender (tools/blender/build_characters.py) e religado no esqueleto
## Ch31 por tools/characters/build_blender_characters.gd; usa todos os clipes,
## IK e camadas de pose do adaptador Mixamo sem retarget.

func _init() -> void:
	model_path = "res://assets/personagens/blender/manequim_modelo.scn"
	source_height = 1.778
