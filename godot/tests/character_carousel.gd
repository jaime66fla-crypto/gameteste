extends SceneTree
## Carrossel de personagens: uma carta no centro, setas trocam, seleção salva.
## Com `-- shot=<arquivo.png>` (sem --headless) salva um print da tela.
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _cards(menu: Node) -> Array[Node]:
    return menu.find_children("CharacterCard_*", "", true, false)

func _run() -> void:
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://character_carousel_%s.cfg" % OS.get_process_id()
    var menu: Control = load("res://scenes/menu.tscn").instantiate()
    root.add_child(menu)
    current_scene = menu
    # Espera o "Entrando na sua conta..." (chamada ao servidor) acabar: ele redesenha o menu.
    for i in 900:
        await process_frame
        if menu.find_child("CharactersButton", true, false) != null or menu.find_child("LoginButton", true, false) != null:
            break
    for i in 5:
        await process_frame
    # O carrossel do Cofre só mostra os personagens da conta: perfil de teste
    # (só na memória) com todos os personagens da loja comprados.
    var net := root.get_node("Net")
    if str(net.get("session_token")).is_empty():
        net.set("session_token", "0".repeat(64))
    var owned := []
    for entry in registry.all_characters():
        owned.append(entry.id)
    net.set("profile", {"name": "Teste", "brasas": 0, "owned": owned})
    menu.call("_show_characters")
    await process_frame
    var all: Array = registry.all_characters()
    _check(_cards(menu).size() == 1, "Carrossel deveria mostrar 1 carta, mostrou %d" % _cards(menu).size())
    var prev := menu.find_child("PrevCharacter", true, false) as Button
    var next := menu.find_child("NextCharacter", true, false) as Button
    _check(prev != null and next != null, "Setas do carrossel faltando")
    var first: String = _cards(menu)[0].name if not _cards(menu).is_empty() else ""
    _check(first == "CharacterCard_" + registry.load_selection(), "Carrossel não abriu no personagem salvo: " + first)
    if next != null and all.size() > 1:
        next.pressed.emit()
        await process_frame
        await process_frame
        var cards := _cards(menu)
        _check(cards.size() == 1, "Depois da seta: %d cartas" % cards.size())
        _check(not cards.is_empty() and cards[0].name != first, "Seta › não trocou o personagem")
        var id := str(cards[0].name).trim_prefix("CharacterCard_")
        var select := menu.find_child("Select_" + id, true, false) as Button
        if select != null and not select.disabled:
            select.pressed.emit()
            await process_frame
            await process_frame
            _check(registry.load_selection() == id, "Seleção não salva: " + id)
            _check(_cards(menu).size() == 1 and _cards(menu)[0].name == "CharacterCard_" + id, "Depois de selecionar o carrossel saiu do personagem")
        # Volta pelo teclado (←) e dá a volta inteira com ‹.
        var key := InputEventAction.new()
        key.action = "ui_left"
        key.pressed = true
        root.push_input(key)
        await process_frame
        await process_frame
        _check(_cards(menu)[0].name == first, "← não voltou ao personagem anterior")
        prev = menu.find_child("PrevCharacter", true, false) as Button # recriada ao selecionar
        for i in all.size():
            prev.pressed.emit()
        await process_frame
        await process_frame
        _check(_cards(menu)[0].name == first, "‹ não dá a volta no carrossel")
    _check(menu.find_child("WardrobeVault", true, false) != null, "Cofre de roupas sumiu")
    var shot := ""
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("shot="):
            shot = arg.trim_prefix("shot=")
    if not shot.is_empty():
        for i in 40:
            await process_frame
        root.get_texture().get_image().save_png(shot)
        print("SHOT ", shot)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    for failure in failures:
        printerr(failure)
    print("CHARACTER CAROUSEL: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
