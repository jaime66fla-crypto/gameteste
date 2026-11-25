extends SceneTree
const Data = preload("res://scripts/survival/survival_data.gd")
const Rules = preload("res://scripts/survival/building_rules.gd")
var failures: Array[String] = []
func check(ok: bool, what: String) -> void:
    if not ok:
        failures.append(what)
        printerr("FAIL: ", what)
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var data = Data.new()
    check(data.has_method("craft_error"), "shared craft availability exists")
    var recipe: Dictionary = {}
    for r in Data.recipes():
        if r.id == "charcoal": recipe = r
    if data.has_method("craft_error"):
        check(not str(data.call("craft_error", recipe, {"wood": 1}, [], {}, 1.0, 10.0)).is_empty(), "unlit or absent campfire blocks crafting")
        check(str(data.call("craft_error", recipe, {"wood": 1}, [], {"campfire": true}, 1.0, 10.0)).is_empty(), "near lit campfire enables crafting")
        for r in Data.recipes():
            if r.id == "nail_bat":
                check(not str(data.call("craft_error", r, {"wood": 1, "nails": 8}, [], {"workbench": true}, 9.96, 10.0)).is_empty(), "client blocks overweight craft")
        var stations: Array = [{"kind": "campfire", "p": [0, 0, 0], "on": false}, {"kind": "workbench", "p": [0, 3, 0]}]
        check((data.call("nearby_stations", stations, Vector3.ZERO) as Dictionary).is_empty(), "unlit and upstairs stations are unavailable")
        stations[0].on = true
        check((data.call("nearby_stations", stations, Vector3.ZERO) as Dictionary).has("campfire"), "lighting campfire changes availability")
        stations[0].p = [3.6, 0, 0]
        check(not (data.call("nearby_stations", stations, Vector3.ZERO) as Dictionary).has("campfire"), "station reach matches server boundary")
    var rules = Rules.new()
    check(rules.has_method("ground_error"), "preview validates map footprint")
    if rules.has_method("ground_error"):
        var map := {"half_size": 100, "ponds": [], "mountains": [], "resources": [{"kind": "tree", "p": [1.5, 0, 1.5]}]}
        var p := {"kind": "foundation", "i": 0, "j": 0, "k": 0}
        check(not str(rules.call("ground_error", p, map)).is_empty(), "tree blocks foundation before click")
        map.resources = []
        check(str(rules.call("ground_error", p, map)).is_empty(), "clear terrain remains buildable")
        map.ponds = [{"x": 1.5, "z": 1.5, "r": 2}]
        check(not str(rules.call("ground_error", p, map)).is_empty(), "pond blocks foundation")
        map.ponds = [];map.mountains = [{"x": 3.1, "z": 3.1, "r": 1}]
        check(str(rules.call("ground_error", p, map)).is_empty(), "slopes and mountains no longer block the footprint")
        map.mountains = []
        # Encosta: a fundação sobe acima do ponto mais alto (com pilar), nunca enterrada.
        rules.ground = func(x: float, z: float) -> float: return 0.5 * x
        var owns := func(_piece): return true
        check(str(rules.check({"kind": "foundation", "i": 0, "j": 0, "k": 0, "b": 0}, owns)).contains("enterrada"), "buried foundation refused on a slope")
        var lift: int = rules.foundation_lift(0, 0)
        check(lift == 6 and str(rules.check({"kind": "foundation", "i": 0, "j": 0, "k": 0, "b": lift}, owns)).is_empty(), "foundation sits on the highest ground (%d)" % lift)
        check(str(rules.check({"kind": "foundation", "i": 0, "j": 0, "k": 0, "b": 60}, owns)).contains("pilar"), "pillar has a limit")
        rules.add({"id": "F", "kind": "foundation", "i": 0, "j": 0, "k": 0, "b": lift})
        check(rules.guess_lift({"kind": "wall", "i": 0, "j": 0, "k": 0, "o": "h"}) == lift, "a wall takes the foundation step")
        check(str(rules.check({"kind": "wall", "i": 0, "j": 0, "k": 0, "o": "h", "b": lift}, owns)).is_empty(), "wall on the lifted foundation")
        check(not str(rules.check({"kind": "wall", "i": 0, "j": 0, "k": 0, "o": "h", "b": 0}, owns)).is_empty(), "wall on another step has no support")
        var fire := {"kind": "campfire", "p": [7.0, 0.0, 1.0]}
        fire.p[1] = rules.free_ground(fire).y
        check(rules.supporters(fire) == ["ground"], "campfire on the slope stands on its highest ground")
        fire.p[1] = 2.0
        check(rules.supporters(fire).is_empty(), "buried campfire refused")
        rules.erase("F")
        rules.ground = func(_x: float, _z: float) -> float: return 0.0
        check(not str(rules.call("ground_error", {"kind": "foundation", "i": 32, "j": 0, "k": 0}, map)).is_empty(), "world boundary is checked")
    for path in ["res://scripts/survival/inventory_ui.gd", "res://scripts/survival/survival_manual.gd"]:
        var ui = load(path).new()
        check(ui.has_method("craft_error"), "both crafting screens use shared availability")
        root.add_child(ui)
        ui.set("inv", {"wood": 1})
        check(not str(ui.call("craft_error", recipe)).is_empty(), "both screens reject absent station")
        ui.call("set_crafting_context", {"campfire": true}, 1.0, 20.0)
        check(str(ui.call("craft_error", recipe)).is_empty(), "both screens enable available station")
        ui.free()
    print("SURVIVAL CONSISTENCY: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
