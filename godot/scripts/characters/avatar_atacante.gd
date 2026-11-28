extends "res://scripts/characters/downloaded_avatar.gd"
## Personagem civil: camisa preta, jeans e sapatos pretos, sem equipamento tático.
## Modelo exportado de personagens_civis.blend e convertido para o rig Mixamo.

func _init() -> void:
	model_path = "res://assets/personagens/atacante/atacante_modelo.scn"
	# Altura da malha em repouso: normaliza os dois personagens para 1,80 m.
	# Anda como no Linha de Fogo: passos da UAL de frente, sem as passadas direcionais.
	clean_locomotion = true
	source_height = 1.816185
