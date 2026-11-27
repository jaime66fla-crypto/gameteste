extends RefCounted
## Personagem padrão (de todo mundo): o soldado atacante do Linha de Fogo. O defensor
## também é de todo mundo; personagens pagos viriam da loja (data/store.json).
const DEFAULT_ID := "atacante"
## Roupas trocáveis: nenhum personagem atual tem (eram as peças do 01, removido).
const DEFAULT_OUTFIT := []
const DEFAULT_PATH := "user://character_selection.cfg"
const CATALOG = preload("res://characters/catalog.tres")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
# Tests may use a separate user:// file; production uses DEFAULT_PATH.
static var storage_path: String = OS.get_environment("CAMPO_CHARACTER_TEST_PATH") if OS.get_environment("CAMPO_CHARACTER_TEST_PATH").begins_with("user://") else DEFAULT_PATH

static func all_characters() -> Array[Resource]:
    var result: Array[Resource] = []
    var seen := {}
    for entry in CATALOG.entries:
        if entry == null or entry.id.is_empty() or seen.has(entry.id):
            continue
        seen[entry.id] = true
        result.append(entry)
    return result

static func definition(id: String) -> Resource:
    for entry in all_characters():
        if entry.id == id:
            return entry
    return null

static func is_available(id: String) -> bool:
    var entry := definition(id)
    if entry == null or not ResourceLoader.exists(entry.visual_scene):
        return false
    for path in entry.required_resources:
        if not ResourceLoader.exists(path):
            return false
    return true

static func load_selection() -> String:
    var config := ConfigFile.new()
    if config.load(storage_path) != OK:
        return DEFAULT_ID
    var id := str(config.get_value("characters", "selected_id", DEFAULT_ID))
    # Personagem da loja que a conta não tem (ou sem login) volta para o padrão.
    return id if definition(id) != null and StoreCatalog.owns_character(id) else DEFAULT_ID

## Personagens que esta conta pode usar: o padrão e os comprados na loja.
static func owned_characters() -> Array[Resource]:
    var result: Array[Resource] = []
    for entry in all_characters():
        if StoreCatalog.owns_character(entry.id):
            result.append(entry)
    return result

static func select_character(id: String) -> Error:
    if definition(id) == null:
        return ERR_INVALID_PARAMETER
    if not StoreCatalog.owns_character(id):
        return ERR_UNAUTHORIZED
    if not is_available(id):
        return ERR_UNAVAILABLE
    return _save_values({"selected_id": id})

## Roupas vestidas (ids de item de data/store.json; hoje nenhum personagem as usa), salvas
## junto com a seleção. Só a vitrine do menu muda; o jogador local veste ao
## entrar. Itens pagos que a conta não tem (ou sem login) ficam de fora.
static func load_outfit() -> PackedStringArray:
    var config := ConfigFile.new()
    var saved = PackedStringArray(DEFAULT_OUTFIT)
    if config.load(storage_path) == OK:
        saved = config.get_value("characters", "roupas", saved)
    var result := PackedStringArray()
    if saved is PackedStringArray or saved is Array:
        for item in saved:
            if StoreCatalog.is_owned(str(item)) and not str(item) in result:
                result.append(str(item))
    return result

static func save_outfit(pieces: PackedStringArray) -> Error:
    var clean := PackedStringArray()
    for item in pieces:
        if not StoreCatalog.item(item).is_empty() and not item in clean:
            clean.append(item)
    return _save_values({"roupas": clean})

## Skin equipada numa arma ("rifle" -> "rifle_deserto"), só se a conta comprou.
static func weapon_skin(weapon: String) -> String:
    var config := ConfigFile.new()
    if config.load(storage_path) != OK:
        return ""
    var skins = config.get_value("characters", "armas", {})
    var id := str(skins.get(weapon, "")) if skins is Dictionary else ""
    return id if StoreCatalog.weapon(id) == weapon and StoreCatalog.is_owned(id) else ""

## Equipa (ou tira, com skin_id vazio) a skin de uma arma.
static func set_weapon_skin(weapon: String, skin_id: String) -> Error:
    if not skin_id.is_empty() and StoreCatalog.weapon(skin_id) != weapon:
        return ERR_INVALID_PARAMETER
    var config := ConfigFile.new()
    var skins := {}
    if config.load(storage_path) == OK:
        var saved = config.get_value("characters", "armas", {})
        if saved is Dictionary:
            skins = saved
    if skin_id.is_empty():
        skins.erase(weapon)
    else:
        skins[weapon] = skin_id
    return _save_values({"armas": skins})

static func _save_values(values: Dictionary) -> Error:
    if not storage_path.begins_with("user://"):
        return ERR_INVALID_PARAMETER
    var config := ConfigFile.new()
    var error := config.load(storage_path)
    # Preserve damaged files for recovery instead of silently overwriting them.
    if error != OK and error != ERR_FILE_NOT_FOUND:
        return error
    for key in values:
        config.set_value("characters", key, values[key])
    config.set_value("characters", "version", 1)
    var pending := storage_path + ".pending_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
    if FileAccess.file_exists(pending):
        return ERR_ALREADY_EXISTS
    error = config.save(pending)
    if error == OK:
        error = DirAccess.rename_absolute(ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(storage_path))
    if FileAccess.file_exists(pending):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(pending))
    return error

static func create_visual(id: String) -> Node3D:
    if not is_available(id):
        return null
    var packed := load(definition(id).visual_scene) as PackedScene
    if packed == null:
        return null
    var node := packed.instantiate()
    if not node is Node3D or not node.has_method("animate") or not node.has_method("configure_weapon"):
        node.free()
        return null
    # Authored AnimationPlayer clips get the default before adapter _ready().
    # Adapters that replace their library in _ready() should call this helper
    # again after the replacement and before enabling their AnimationTree.
    configure_locomotion_loops(node)
    return node as Node3D

static func configure_locomotion_loops(root: Node) -> void:
    # Character adapters may replace imported clips in _ready(), so callers
    # should run this after adding the character to the scene tree as well.
    if root == null:
        return
    _configure_animation_player_loops(root)

static func _configure_animation_player_loops(node: Node) -> void:
    if node is AnimationPlayer:
        var player := node as AnimationPlayer
        for library_name in player.get_animation_library_list():
            var source := player.get_animation_library(library_name)
            var library := source.duplicate() as AnimationLibrary
            for animation_name in library.get_animation_list():
                var clip_name := String(animation_name).to_lower().get_slice("/", String(animation_name).get_slice_count("/") - 1)
                if not _is_locomotion_clip(clip_name):
                    continue
                var clip := library.get_animation(animation_name).duplicate() as Animation
                clip.loop_mode = Animation.LOOP_LINEAR
                library.remove_animation(animation_name)
                library.add_animation(animation_name, clip)
            player.remove_animation_library(library_name)
            player.add_animation_library(library_name, library)
    for child in node.get_children():
        _configure_animation_player_loops(child)

static func _is_locomotion_clip(clip_name: String) -> bool:
    for keyword in ["idle", "walk", "run", "sprint", "jog", "strafe", "locomotion"]:
        if keyword in clip_name:
            return true
    return false
