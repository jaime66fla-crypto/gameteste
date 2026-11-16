extends "res://scripts/main.gd"
## Full solo gameplay with SWAT, without changing the saved character choice.
func _ready() -> void:
    var registry = load("res://scripts/characters/character_registry.gd")
    var previous: String = registry.storage_path
    var fixture := "user://swat_game_test_%s.cfg" % OS.get_process_id()
    registry.storage_path = fixture
    var error: Error = registry.select_character("jaime_swat")
    if error != OK:
        push_error("SWAT solo test could not select character: %s" % error)
    super._ready()
    registry.storage_path = previous
    DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
