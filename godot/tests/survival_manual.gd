extends SceneTree
## Manual de sobrevivência (L): monta o livro sem rede, passa por todas as
## seções, abre páginas e confere o botão Fabricar; monta bancada e forja.
## godot --headless --path godot --script res://tests/survival_manual.gd
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const ManualUI = preload("res://scripts/survival/survival_manual.gd")
const Model = preload("res://scripts/survival/building_model.gd")
const Rules = preload("res://scripts/survival/building_rules.gd")
const NatureModel = preload("res://scripts/survival/nature_model.gd")
const ItemIcons = preload("res://scripts/survival/item_icons.gd")

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok:
		print("ok: " + what)
	else:
		failures.append(what)
		printerr("FALHOU: " + what)

func _texts(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	for child in node.get_children():
		out += _texts(child)
	return out

func _initialize() -> void:
	var manual = ManualUI.new()
	root.add_child(manual)
	await process_frame
	manual.call("set_inventory", {"hide": 6, "rope": 2})
	manual.call("open", "workbench")
	await process_frame
	check(manual.visible, "abre na bancada")
	var text := _texts(manual)
	check(text.contains("Colete de couro"), "bancada lista o colete de couro")
	check(text.contains("Construa com B"), "bancada mostra o custo da estação")
	check(text.to_lower().contains("dá pra fazer"), "marca o que já dá para fazer")

	# Todas as seções abrem sem erro e mostram algo.
	for era in SurvivalData.catalog().get("eras", []):
		manual.set("_section", "era:%d" % int(era["id"]))
		manual.call("_refresh")
		check(_texts(manual).contains(str(era["name"])), "era %s abre" % era["name"])
	for station in ManualUI.STATIONS:
		manual.set("_section", "st:" + station)
		manual.call("_refresh")
		check(_texts(manual).contains(ManualUI.station_name(station)), "estação %s abre" % ManualUI.station_name(station))
	manual.set("_section", "materials")
	manual.call("_refresh")
	text = _texts(manual)
	check(text.contains("Minério de ferro") and text.contains("Veio de ferro"), "materiais dizem onde achar o minério")
	check(text.contains("Sucata de metal") and text.contains("Carro velho"), "sucata vem dos carros velhos")

	# Página de receita: Fabricar manda o pedido; receita em breve não tem botão.
	var asked: Array = []
	manual.connect("craft_requested", func(id): asked.append(id))
	manual.set("_selected", "r:leather_vest")
	manual.call("_refresh")
	var make: Button = null
	for b in manual.find_children("*", "Button", true, false):
		if (b as Button).text == "Fabricar":
			make = b
	check(make != null and not make.disabled, "página do colete tem Fabricar ativo")
	if make != null:
		make.pressed.emit()
	check(asked == ["leather_vest"], "Fabricar pede a receita certa")
	manual.set("_selected", "r:molotov")
	manual.call("_refresh")
	text = _texts(manual)
	check(text.contains("EM BREVE") and not text.contains("Fabricar\n"), "receita em breve não fabrica")
	manual.set("_selected", "r:pipe_shotgun")
	manual.call("_refresh")
	text = _texts(manual)
	check(text.contains("Falta a página") and not text.contains("Fabricar\n"), "sem a página a espingarda não fabrica")
	manual.call("set_inventory", {"pipe": 2, "wood": 2, "mech_parts": 2, "nails": 4}, ["pipe_shotgun"])
	manual.call("_refresh")
	text = _texts(manual)
	check(text.contains("Página lida") and text.contains("Fabricar\n"), "com a página lida, fabrica")
	manual.set("_section", "materials")
	manual.set("_selected", "i:scrap")
	manual.call("_refresh")
	text = _texts(manual)
	check(text.contains("Carro velho") and text.contains("pé de cabra"), "sucata: carro velho com pé de cabra")
	manual.set("_selected", "i:w_rifle")
	manual.call("_refresh")
	check(_texts(manual).contains("armário de armas"), "fuzil: armário de armas nas cidades")
	manual.set("_selected", "i:iron_bar")
	manual.call("_refresh")
	check(_texts(manual).to_lower().contains("usado em"),"página do item mostra onde é usado")
	manual.call("close")
	check(not manual.visible, "fecha")

	# Toda receita e material tem origem; todo item do jogo (não em breve) tem ícone próprio? (aviso)
	for id in ManualUI.materials():
		check(not ManualUI.origins(str(id)).is_empty(), "%s tem de onde vir" % id)

	# Bancada e forja montam com colisão; a forja acende.
	var rules = Rules.new()
	rules.defs = SurvivalData.catalog().get("builds", {})
	for kind in ["workbench", "forge", "workshop", "chem_table"]:
		var node: Node3D = Model.build({"id": "T_" + kind, "kind": kind, "p": [0, 0, 0], "y": 0.0, "on": true}, rules)
		root.add_child(node)
		check(not node.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s tem colisão" % kind)
		if kind == "forge":
			check(node.get_node_or_null("FireLight") != null, "forja acesa tem luz")
			Model.set_fire(node, false)
			check(node.get_node_or_null("FireLight") == null or node.get_node("FireLight").is_queued_for_deletion(), "apagar a forja tira a luz")
	for variant in ["rock_ore", "rock_salt"]:
		check(NatureModel.mesh(variant, 0).get_surface_count() > 0 and NatureModel.mesh(variant, 2).get_surface_count() > 0, "%s tem modelo perto e longe" % variant)

	await process_frame
	print("FALHAS: %d" % failures.size())
	quit(1 if not failures.is_empty() else 0)
