extends "res://scripts/characters/downloaded_avatar.gd"
## Soldado "defensor" do Linha de Fogo: humano realista do MakeHuman (pele, olhos, cabelo,
## roupa do time) com colete de placas e capacete, gerado por fps-tatico/tools/build_soldiers.py
## e convertido para o esqueleto Mixamo do jogo por
## tools/characters/build_mannequin_model.gd -- --id=defensor.
## Usa todos os clipes, IK e camadas de pose do adaptador Mixamo.

func _init() -> void:
	model_path = "res://assets/personagens/defensor/defensor_modelo.scn"
	# Topo da cabeça (com o capacete): normaliza para 1,8 m como os outros.
	# Anda como no Linha de Fogo: passos da UAL de frente, sem as passadas direcionais.
	clean_locomotion = true
	source_height = 1.967
