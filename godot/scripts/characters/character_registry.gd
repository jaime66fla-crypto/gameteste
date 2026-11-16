extends RefCounted
const DEFAULT_ID := "avatar_ch31"
const DEFAULT_PATH := "user://character_selection.cfg"
const CATALOG = preload("res://characters/catalog.tres")
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
    return id if definition(id) != null else DEFAULT_ID

static func select_character(id: String) -> Error:
    if not storage_path.begins_with("user://"):
        return ERR_INVALID_PARAMETER
    if definition(id) == null:
        return ERR_INVALID_PARAMETER
    if not is_available(id):
        return ERR_UNAVAILABLE
    var config := ConfigFile.new()
    var error := config.load(storage_path)
    # Preserve damaged files for recovery instead of silently overwriting them.
    if error != OK and error != ERR_FILE_NOT_FOUND:
        return error
    config.set_value("characters", "selected_id", id)
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
