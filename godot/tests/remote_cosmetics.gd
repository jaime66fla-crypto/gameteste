extends SceneTree
## Outro jogador (NetActor) com as roupas e a skin de arma que vieram no
## estado de rede ("rp"/"ws"): sem "rp" fica a roupa padrão do 01; com "rp"
## veste o que veio; "ws" pinta a arma da mão só se for skin daquela arma.
## godot --headless --path godot --quit-after 3000 --script res://tests/remote_cosmetics.gd
const NetActorScript = preload("res://scripts/net/net_actor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _gun_texture(actor: Node) -> String:
	var model := actor.get("weapon_model") as Node3D
	if model == null:
		return "<sem arma>"
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return "<sem malha>"
	return preload("res://scripts/weapons/WeaponProportions.gd").skin_path(model)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", "probe", "Alvo", false)
	world.add_child(actor)
	await _frames(3)
	var base := {"p": [0.0, 0.0, 0.0], "y": 0.0, "w": "rifle", "h": false, "ch": "01"}

	# Cliente antigo (sem rp/ws): roupa padrão e arma original.
	actor.call("apply_state", base)
	await _frames(3)
	var visual := actor.get("visual") as Node
	_check(Array(visual.get("roupas")) == ["bone", "camiseta", "calca"], "Sem rp deveria ficar a roupa padrão: %s" % [visual.get("roupas")])
	_check(not _gun_texture(actor).contains("/skins/"), "Sem ws a arma deveria ser a original: " + _gun_texture(actor))

	# Jogador com boné vinho + bermuda e o fuzil deserto na mão.
	var dressed := base.duplicate()
	dressed["rp"] = ["bone_vinho", "bermuda"]
	dressed["ws"] = "rifle_deserto"
	actor.call("apply_state", dressed)
	await _frames(3)
	visual = actor.get("visual") as Node
	_check(Array(visual.get("roupas")) == ["bone_vinho", "bermuda"], "Roupas do estado não vestidas: %s" % [visual.get("roupas")])
	_check(_gun_texture(actor).ends_with("rifle_deserto.png"), "Fuzil sem a skin do estado: " + _gun_texture(actor))

	# Trocou para a pistola: skin do fuzil não vale para ela.
	var pistol := dressed.duplicate()
	pistol["w"] = "pistol"
	actor.call("apply_state", pistol)
	await _frames(3)
	_check(not _gun_texture(actor).contains("/skins/"), "Skin do fuzil não deveria ir para a pistola: " + _gun_texture(actor))

	# Personagem que nao existe mais (cliente antigo) e voltar ao 01 mantém as roupas que ele mandou.
	var remy := dressed.duplicate()
	remy["ch"] = "personagem_removido"
	actor.call("apply_state", remy)
	await _frames(5)
	actor.call("apply_state", dressed)
	await _frames(5)
	visual = actor.get("visual") as Node
	_check(str(actor.get("character_id")) == "01" and Array(visual.get("roupas")) == ["bone_vinho", "bermuda"], "Voltando ao 01 deveria manter as roupas: %s" % [visual.get("roupas")])

	if failures.is_empty():
		print("REMOTE COSMETICS: PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("FALHA: " + failure)
		print("REMOTE COSMETICS: FAIL")
		quit(1)
