extends SceneTree
## Intro do naufrágio: monta sem rede, roda a linha do tempo inteira,
## confere legendas, navio afundando, ondas e o botão Pular.
## godot --headless --path godot --quit-after 3000 --script res://tests/shipwreck_intro.gd
const Intro = preload("res://scripts/survival/shipwreck_intro.gd")

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok:
		print("ok: " + what)
	else:
		failures.append(what)
		printerr("FALHOU: " + what)

func _step(intro: Node, until: float) -> void:
	while is_instance_valid(intro) and float(intro.get("t")) < until and not bool(intro.get("done")):
		intro.call("_process", 0.1)

func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Intro.SEEN_PATH))
	var fresh := {"hp": 100, "hunger": 85, "thirst": 85, "dead": false}
	check(Intro.should_play(fresh), "personagem novo vê a intro")
	check(not Intro.should_play({"hunger": 61.4, "thirst": 70.0}), "personagem que volta não vê")
	check(not Intro.should_play({"hunger": 85, "thirst": 85, "dead": true}), "morto não vê")
	# Ondas: altura do GDScript bate com o normal (derivada numérica).
	var h0 := Intro.wave_height(10, 20, 3.0)
	var hx := Intro.wave_height(10.01, 20, 3.0)
	var n := Intro.wave_normal(10, 20, 3.0)
	check(absf(-n.x / n.y - (hx - h0) / 0.01) < 0.02, "normal da onda bate com a altura")

	# Praia de verdade: perto do spawn, chão seco e o mar logo à frente.
	var Hydrology = load("res://scripts/survival/hydrology.gd")
	var spawns: Array = load("res://scripts/survival/survival_data.gd").world()["spawns"]
	var beaches_ok := 0
	for sp in spawns:
		var found: Dictionary = Intro.find_beach(Vector3(float(sp[0]), 0, float(sp[1])))
		if found.is_empty():
			continue
		var p: Vector3 = found.p
		var sea: Vector3 = p - (found.inland as Vector3) * 6.0
		if p.y > -1.0 and Hydrology.ground_height(sea.x, sea.z) < -0.75:
			beaches_ok += 1
	check(beaches_ok == spawns.size(), "praia achada para todo spawn (%d/%d)" % [beaches_ok, spawns.size()])

	var intro: CanvasLayer = Intro.new()
	var ended := [false]
	intro.connect("finished", func(): ended[0] = true)
	root.add_child(intro)
	await process_frame
	await process_frame
	check(bool(intro.get("started")), "começa sem tela de carregamento")
	check(root.get_viewport().disable_3d, "3D do jogo desligado durante a intro")
	_step(intro, 3.0)
	var caption: Label = intro.find_child("Caption", true, false)
	check(caption.text.contains("Aurora do Sul") and caption.modulate.a > 0.9, "primeira legenda: o cruzeiro")
	var bow: Node3D = intro.find_child("Proa", true, false)
	var stern: Node3D = intro.find_child("Popa", true, false)
	check(bow != null and stern != null, "navio do Blender com proa e popa")
	var bow_y := bow.global_position.y
	_step(intro, 17.0)
	var mats: Array = intro.get("_deck_mats")
	check(mats.size() == 7, "7 faixas de janelas (vigias + 6 conveses): %d" % mats.size())
	check(float(mats[0].emission_energy_multiplier) < 0.01 and float(mats[6].emission_energy_multiplier) > 0.5, "luzes apagam de baixo para cima")
	_step(intro, 26.0)
	check(bow.global_position.y < bow_y - 15.0, "proa afundou (%.1f m)" % bow.global_position.y)
	check(absf(stern.global_rotation.z) > deg_to_rad(25.0), "popa empinou depois de partir")
	check(caption.text.contains("convés"), "legenda dos destroços")
	_step(intro, 36.0)
	check(caption.text.contains("ilha") and bool(intro.get("_at_beach")), "praia ao amanhecer")
	check(intro.find_child("Castaway", true, false) != null, "náufrago deitado na areia")
	_step(intro, 40.4)
	var lid: ColorRect = intro.find_child("LidTop", true, false)
	check(lid.visible, "olhos abrindo (pálpebras)")
	_step(intro, 46.0)
	check(caption.text.contains("sobreviver") and not lid.visible, "levanta e encara a mata")
	_step(intro, 60.0)
	check(ended[0] and not root.get_viewport().disable_3d, "acabou e devolveu o 3D")
	check(not Intro.should_play(fresh), "não repete logo depois")

	# Pular.
	var second: CanvasLayer = Intro.new()
	var ended2 := [false]
	second.connect("finished", func(): ended2[0] = true)
	root.add_child(second)
	await process_frame
	_step(second, 2.0)
	second.call("skip")
	check(float(second.get("t")) >= Intro.END - 1.6, "Pular vai para o fim")
	_step(second, 60.0)
	check(ended2[0], "terminou depois de pular")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Intro.SEEN_PATH))

	if failures.is_empty():
		print("shipwreck_intro: tudo ok")
		quit(0)
	else:
		printerr("shipwreck_intro: %d falha(s)" % failures.size())
		quit(1)
