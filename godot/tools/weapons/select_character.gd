extends SceneTree
## Explicit local operation: --script tools/weapons/select_character.gd -- jaime_swat
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        printerr("Supply one registered character ID after --")
        quit(1)
        return
    var registry = load("res://scripts/characters/character_registry.gd")
    var previous: String = registry.load_selection()
    var result: Error = registry.select_character(args[0])
    print("CHARACTER APPLY: ",previous," -> ",args[0]," result=",result)
    quit(0 if result==OK else 1)
