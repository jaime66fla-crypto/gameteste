extends SceneTree
## Loja e Cofre: grupos do catálogo, soldado atacante como padrão e personagens pagos
## travados, Comprar conforme saldo/posse, Cofre só com o que a conta tem,
## skin de arma equipada (as roupas do 01 saíram junto com ele).
## godot --headless --path godot --quit-after 3000 --script res://tests/wardrobe_store.gd
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
const StoreScreen = preload("res://scripts/loja/store_screen.gd")
const Registry = preload("res://scripts/characters/character_registry.gd")
const Vault = preload("res://scripts/characters/wardrobe_vault.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)

func _texture_of(root: Node, mesh_name: String) -> String:
	var mesh := (root.find_child(mesh_name, true, false) if not mesh_name.is_empty() else root.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D
	if mesh == null:
		return "<sem malha>"
	var mat := mesh.get_active_material(0) as BaseMaterial3D
	return mat.albedo_texture.resource_path if mat != null and mat.albedo_texture != null else ""

func _ids(list: Array) -> Array:
	return list.map(func(entry): return entry.id)

func _run() -> void:
	Registry.storage_path = "user://wardrobe_store_%s.cfg" % OS.get_process_id()
	var net := root.get_node_or_null("Net")
	_check(net != null, "Autoload Net faltando")
	_check(_ids(StoreCatalog.groups()) == ["personagens", "skins_armas"], "Grupos da loja errados")
	_check(Registry.DEFAULT_ID == "atacante", "O atacante deveria ser o padrão")

	# Sem conta: os dois soldados (de todo mundo); personagem pago salvo volta para o atacante.
	_check(_ids(Registry.owned_characters()) == ["atacante", "defensor"], "Sem login os dois soldados: %s" % [_ids(Registry.owned_characters())])
	_check(Registry.select_character("remy") == ERR_INVALID_PARAMETER, "Personagem removido não deveria ser selecionável")
	Registry._save_values({"selected_id": "remy"})
	_check(Registry.load_selection() == "atacante", "Personagem removido salvo deveria voltar ao atacante")
	var store := StoreScreen.new()
	root.add_child(store)
	await process_frame
	var buy := _find(store, "Buy_rifle_deserto") as Button
	_check(buy != null and buy.text == "Comprar" and buy.disabled, "Sem login, Comprar deveria estar desativado")
	_check(_find(store, "Grupo_personagens") == null, "Sem personagens à venda, o grupo não deveria aparecer")
	_check(_find(store, "Grupo_skins_personagens") == null, "Roupas do 01 não deveriam mais estar na loja")
	for group in ["skins_armas"]:
		_check(_find(store, "Grupo_" + group) != null, "Grupo faltando na loja: " + group)
	store.queue_free()

	# Conta com 300 Brasas que comprou o Remy (removido), o fuzil deserto e o boné vinho (roupa do 01, removida).
	net.set("session_token", "0".repeat(64))
	net.set("profile", {"name": "Teste", "brasas": 300, "owned": ["remy", "rifle_deserto", "bone_vinho"]})
	_check(_ids(Registry.owned_characters()) == ["atacante", "defensor"], "Personagem removido não deveria aparecer no Cofre")
	_check(Registry.load_selection() == "atacante", "Quem tinha o Remy volta para o atacante")
	store = StoreScreen.new()
	root.add_child(store)
	await process_frame
	_check((_find(store, "Buy_rifle_deserto") as Button).text == "Comprado", "Item da conta deveria aparecer como Comprado")
	_check(not (_find(store, "Buy_sniper_floresta") as Button).disabled, "Com saldo (300), Sniper floresta deveria estar à venda")
	_check((_find(store, "StoreBalance") as Label).text == "300 Brasas", "Saldo errado na loja")
	store.queue_free()

	# Cofre: só o que é da conta; skin de arma equipa e tira.
	var vault := Vault.new()
	root.add_child(vault)
	await process_frame
	_check(_find(vault, "Vitrine_rifle_deserto") != null, "Skin comprada deveria estar no Cofre")
	_check(_find(vault, "Vitrine_pistol_oliva") == null, "Skin não comprada não deveria estar no Cofre")
	_check(_find(vault, "Vitrine_bone_vinho") == null, "Roupa do 01 (removida) não deveria aparecer no Cofre")
	var equip := _find(vault, "Vestir_rifle_deserto") as Button
	_check(equip.text == "Equipar", "Skin de arma deveria ter Equipar")
	equip.pressed.emit()
	_check(Registry.weapon_skin("rifle") == "rifle_deserto", "Skin do fuzil não foi equipada")
	_check(equip.text == "Tirar", "Depois de equipar, o botão deveria ser Tirar")
	vault.queue_free()

	# A arma criada pelo jogo usa a skin equipada.
	var rifle := WeaponProportions.create_model("rifle", StoreCatalog.texture_path(Registry.weapon_skin("rifle")))
	_check(WeaponProportions.skin_path(rifle).ends_with("rifle_deserto.png"), "Fuzil sem a skin: " + WeaponProportions.skin_path(rifle))
	var finish := (rifle.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0)
	_check(finish is ShaderMaterial, "A skin do fuzil deveria usar o acabamento próprio (weapon_skin.gdshader)")
	rifle.free()
	Registry.set_weapon_skin("rifle", "")
	_check(Registry.weapon_skin("rifle") == "", "Tirar a skin não funcionou")

	# Roupas do 01 saíram da loja: nada salvo antes continua vestido.
	Registry.save_outfit(PackedStringArray(["bone", "camiseta_oliva", "calca"]))
	_check(Registry.load_outfit().is_empty(), "Roupas do 01 removido não deveriam voltar: %s" % [Registry.load_outfit()])
	var soldier := Registry.create_visual("atacante")
	_check(soldier != null and not soldier.has_method("vestir"), "Atacante deveria carregar (sem roupas trocáveis)")
	if soldier != null:
		soldier.free()

	# Loja de Brasas (botão + do saldo): pacotes vendidos no site por PIX.
	_check(StoreCatalog.format_amount(1250) == "1.250" and StoreCatalog.format_amount(6500) == "6.500" and StoreCatalog.format_amount(90) == "90", "Separador de milhar errado")
	_check(StoreCatalog.format_brl(1990) == "R$ 19,90" and StoreCatalog.format_brl(490) == "R$ 4,90", "Preço em reais errado")
	var shop = load("res://scripts/loja/brasas_shop.gd").new()
	root.add_child(shop)
	await process_frame
	_check(StoreCatalog.packs().size() >= 3, "Pacotes de Brasas faltando")
	for pack in StoreCatalog.packs():
		var pack_button := _find(shop, "BuyPack_" + str(pack["id"])) as Button
		_check(pack_button != null and not pack_button.disabled and pack_button.text == "Comprar no site (PIX)", "Pacote deveria abrir a loja do site: " + str(pack["id"]))
	var shop_balance := (_find(shop, "BrasasShopBalance") as Label).text
	_check(shop_balance.to_upper() == "SEU SALDO: 300 BRASAS", "Saldo errado na Loja de Brasas: " + shop_balance)
	shop.queue_free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Registry.storage_path))
	net.set("session_token", "")
	net.set("profile", {})
	if failures.is_empty():
		print("wardrobe_store: OK")
		quit(0)
	else:
		for failure in failures:
			printerr("FALHA: " + failure)
		quit(1)
