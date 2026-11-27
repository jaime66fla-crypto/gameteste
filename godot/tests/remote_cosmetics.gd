extends SceneTree
## Outro jogador (NetActor) com as roupas e a skin de arma que vieram no
## estado de rede ("ws"); "rp" (roupas do 01, removido) de cliente antigo é ignorado;
## "ws" pinta a arma da mão só se for skin daquela arma.
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
	var base := {"p": [0.0, 0.0, 0.0], "y": 0.0, "w": "rifle", "h": false, "ch": "atacante"}

	# Sem ws: arma original.
	actor.call("apply_state", base)
	await _frames(3)
	_check(str(actor.get("character_id")) == "atacante", "Estado 'ch' deveria dar o atacante")
	_check(not _gun_texture(actor).contains("/skins/"), "Sem ws a arma deveria ser a original: " + _gun_texture(actor))

	# Fuzil deserto na mão (e "rp" de um cliente antigo com roupas do 01: ignorado sem quebrar).
	var dressed := base.duplicate()
	dressed["rp"] = ["bone_vinho", "bermuda"]
	dressed["ws"] = "rifle_deserto"
	actor.call("apply_state", dressed)
	await _frames(3)
	_check(actor.get("visual") != null, "Corpo do atacante deveria continuar com rp antigo no estado")
	_check(_gun_texture(actor).ends_with("rifle_deserto.png"), "Fuzil sem a skin do estado: " + _gun_texture(actor))

	# Trocou para a pistola: skin do fuzil não vale para ela.
	var pistol := dressed.duplicate()
	pistol["w"] = "pistol"
	actor.call("apply_state", pistol)
	await _frames(3)
	_check(not _gun_texture(actor).contains("/skins/"), "Skin do fuzil não deveria ir para a pistola: " + _gun_texture(actor))

	# Cliente antigo ainda com o 01 (removido): o corpo vira o atacante; o defensor também vem pela rede.
	var old := base.duplicate()
	old["ch"] = "01"
	actor.call("apply_state", old)
	await _frames(5)
	_check(str(actor.get("character_id")) == "atacante" and actor.get("visual") != null, "01 removido deveria virar o atacante: %s" % [actor.get("character_id")])
	var defender := base.duplicate()
	defender["ch"] = "defensor"
	actor.call("apply_state", defender)
	await _frames(5)
	_check(str(actor.get("character_id")) == "defensor" and actor.get("visual") != null, "Estado 'ch' deveria dar o defensor: %s" % [actor.get("character_id")])
	if failures.is_empty():
		print("REMOTE COSMETICS: PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("FALHA: " + failure)
		print("REMOTE COSMETICS: FAIL")
		quit(1)
