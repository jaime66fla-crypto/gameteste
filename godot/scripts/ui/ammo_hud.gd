extends PanelContainer
## Arma ativa e munição, com instruções do arco e informações da partida
## quando disponíveis (ex.: kits e granadas no mata-mata).
const WeaponData = preload("res://scripts/weapon_data.gd")

var player: Node
var extra: Callable
var _weapon: Label
var _ammo: Label
var _reserve: Label
var _bow_hint: Label
var _ammo_row: HBoxContainer
var _extra: Label

func _label(size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -284
	offset_right = -24
	offset_top = -20
	offset_bottom = -20

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#18212adf")
	panel.border_color = Color("#87939a70")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	add_theme_stylebox_override("panel", panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	_extra = _label(13, Color("#cfd8c8"))
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_extra)
	_bow_hint = _label(13, Color("#cfd8c8"))
	_bow_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bow_hint.text = "Segure para mirar · Solte para atirar"
	_bow_hint.hide()
	column.add_child(_bow_hint)
	_weapon = _label(16, Color("#e8e2c8"))
	_weapon.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_weapon)
	_ammo_row = HBoxContainer.new()
	_ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_row.alignment = BoxContainer.ALIGNMENT_END
	_ammo_row.add_theme_constant_override("separation", 6)
	column.add_child(_ammo_row)
	_ammo = _label(34, Color.WHITE)
	_ammo_row.add_child(_ammo)
	_reserve = _label(18, Color("#b8c2b8"))
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_row.add_child(_reserve)

var suppressed := false # dirigindo, morto, luneta: some

func _process(_delta: float) -> void:
	if suppressed or player == null or not is_instance_valid(player):
		visible = false
		return
	visible = true
	if player.has_method("has_bow") and bool(player.call("has_bow")):
		var bow: Node = player.get("bow_controller")
		_weapon.text = "ARCO RECURVO"
		_ammo.text = "%d%%" % roundi(float(bow.get("draw").charge) * 100.0)
		_ammo.add_theme_color_override("font_color", Color("#ffe0a0"))
		_reserve.text = "TENSÃO"
		_bow_hint.show()
		_ammo_row.show()
		_extra.text = ("%d flechas · H: guardar" % int(player.get("reserve_ammo").get("bow", 0))) if bool(player.get("loadout_limited")) else "Flechas ilimitadas no treino · H: guardar"
		_extra.visible = true
		return
	_bow_hint.hide()
	_extra.text = str(extra.call()) if extra.is_valid() else ""
	_extra.visible = not _extra.text.is_empty()
	var owned: Dictionary = player.get("owned_weapons")
	var limited := bool(player.get("loadout_limited"))
	if limited and owned.is_empty():
		_weapon.text = "DESARMADO"
		_ammo_row.hide()
		return
	_ammo_row.show()
	var current := str(player.get("current_weapon"))
	var stats: Dictionary = WeaponData.stats(current)
	var ammo := int(player.get("ammo"))
	var reserve := int((player.get("reserve_ammo") as Dictionary).get(current, 0))
	_weapon.text = str(stats["name"]) + (" · GUARDADA (H)" if bool(player.get("weapon_holstered")) else "")
	_ammo.text = str(ammo)
	_ammo.add_theme_color_override("font_color", Color("#ff7a6a") if ammo == 0 else (Color("#ffd27a") if ammo <= int(stats["mag"]) / 4 else Color.WHITE))
	_reserve.text = "/ %d" % reserve
