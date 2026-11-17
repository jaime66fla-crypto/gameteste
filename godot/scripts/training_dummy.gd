extends Node3D
## Offline training dummy: the same body and hitboxes as an online opponent,
## never dies, and shows the damage of every hit (zone multiplier included),
## the running total and how many shots would kill a 100-health player.
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const ZONE_NAMES := {"head": "CABEÇA", "chest": "PEITO", "pelvis": "QUADRIL", "arm": "BRAÇO", "leg": "PERNA"}
const RESET_AFTER := 2.5 # seconds without hits before the total restarts

var title := "BONECO DE TREINO"
var sound_fx: Node # the player's, for hit / headshot feedback
var actor: CharacterBody3D
var board: Label3D
var total := 0.0
var hits := 0
var _idle := 0.0

func _ready() -> void:
	add_to_group("training_dummy")
	actor = NetActorScript.new()
	actor.call("setup", "dummy_" + str(get_instance_id()), title, false)
	actor.set("tag_subtitle", "TREINO")
	add_child(actor)
	actor.connect("damaged", _on_damaged)
	board = Label3D.new()
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.font_size = 34
	board.outline_size = 9
	board.pixel_size = 0.004
	board.modulate = Color("#ffe08a")
	board.position.y = 2.75
	add_child(board)
	_show("Atire para ver o dano de cada arma")

func _process(delta: float) -> void:
	if hits == 0:
		return
	_idle += delta
	if _idle > RESET_AFTER:
		hits = 0
		total = 0.0

func _on_damaged(_id: String, zone: String, point: Vector3, normal: Vector3, weapon: String) -> void:
	var stats: Dictionary = WeaponData.stats(weapon)
	var damage := float(stats["damage"]) * float(HitboxScript.MULTIPLIER.get(zone, 1.0))
	_register(damage, "%s  •  %s" % [stats["name"], ZONE_NAMES.get(zone, zone.to_upper())], point, normal, zone == "head")

## Grenade blast (offline): same falloff as online.
func explosion_hit(amount: float, at: Vector3) -> void:
	_register(amount, "GRANADA", actor.global_position + Vector3(0, 1.3, 0), (actor.global_position - at).normalized(), false)

func _register(damage: float, what: String, point: Vector3, normal: Vector3, headshot: bool) -> void:
	_idle = 0.0
	hits += 1
	total += damage
	var to_kill := int(ceil(100.0 / maxf(damage, 0.01)))
	_show("ÚLTIMO: %d  (%s)\nmataria com %d acerto%s assim\nSEQUÊNCIA: %d acerto%s  •  %d de dano" % [
		roundi(damage), what, to_kill, "" if to_kill == 1 else "s", hits, "" if hits == 1 else "s", roundi(total)])
	_damage_number(point + normal * 0.05, damage, headshot)
	if sound_fx != null and sound_fx.has_method("hit_confirm"):
		sound_fx.call("hit_confirm", headshot)

func _show(text: String) -> void:
	board.text = "%s\n%s" % [title, text]

func _damage_number(point: Vector3, damage: float, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = ("%d" % roundi(damage)) + ("!" if headshot else "")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 64 if headshot else 46
	label.outline_size = 12
	label.modulate = Color("#ff4d3d") if headshot else Color("#ffe08a")
	add_child(label)
	label.global_position = point + Vector3(randf_range(-0.15, 0.15), 0.2, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0, 0.7, 0), 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
