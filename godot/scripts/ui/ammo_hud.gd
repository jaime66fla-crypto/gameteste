extends Control
## Munição no canto inferior direito: arma na mão, pente / reserva e as teclas
## das armas que você tem. `extra` (Callable -> String) acrescenta uma linha
## curta (ex.: kits e granadas no mata-mata).
const WeaponData = preload("res://scripts/weapon_data.gd")

var player: Node
var extra: Callable
var _weapon: Label
var _ammo: Label
var _reserve: Label
var _slots: Label
var _extra: Label

func _label(size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _ready() -> void:
	name = "AmmoHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -320
	offset_top = -150
	offset_right = -24
	offset_bottom = -20
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", -4)
	add_child(column)
	_extra = _label(14, Color("#cfd8c8"))
	column.add_child(_extra)
	_slots = _label(13, Color("#9fae9f"))
	column.add_child(_slots)
	_weapon = _label(16, Color("#e8e2c8"))
	column.add_child(_weapon)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	_ammo = _label(40, Color.WHITE)
	row.add_child(_ammo)
	_reserve = _label(22, Color("#b8c2b8"))
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_reserve)

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		visible = false
		return
	visible = true
	_extra.text = str(extra.call()) if extra.is_valid() else ""
	_extra.visible = not _extra.text.is_empty()
	var owned: Dictionary = player.get("owned_weapons")
	var limited := bool(player.get("loadout_limited"))
	if limited and owned.is_empty():
		_weapon.text = "DESARMADO"
		_ammo.text = ""
		_reserve.text = ""
		_slots.text = ""
		return
	var current := str(player.get("current_weapon"))
	var stats: Dictionary = WeaponData.stats(current)
	var ammo := int(player.get("ammo"))
	var reserve := int((player.get("reserve_ammo") as Dictionary).get(current, 0))
	_weapon.text = str(stats["name"]) + ("  (GUARDADA — H)" if bool(player.get("weapon_holstered")) else "")
	_ammo.text = str(ammo)
	_ammo.add_theme_color_override("font_color", Color("#ff7a6a") if ammo == 0 else (Color("#ffd27a") if ammo <= int(stats["mag"]) / 4 else Color.WHITE))
	_reserve.text = "/ %d" % reserve
	var parts: Array[String] = []
	var order: Array = player.get("slot_order") if limited else WeaponData.ORDER
	for i in order.size():
		var name_text := str(WeaponData.stats(order[i])["name"])
		parts.append(("[%d %s]" if order[i] == current else "%d %s") % [i + 1, name_text])
	_slots.text = "  ".join(parts)
