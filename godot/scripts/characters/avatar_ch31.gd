extends "res://scripts/characters/downloaded_avatar.gd"
## Avatar CH31: suéter grafite sobre camisa clara, calça preta e sapatos escuros.
## Modelado no Blender (tools/blender/build_characters.py) e religado no esqueleto
## Ch31 por tools/characters/build_blender_characters.gd: as animações rodam sem retarget.

func _init() -> void:
	model_path = "res://assets/personagens/blender/avatar_ch31_modelo.scn"
	source_height = 1.783
