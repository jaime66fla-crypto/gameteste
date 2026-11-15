extends Control
const Settings = preload("res://scripts/game_settings.gd")
var settings: Dictionary
var content: VBoxContainer
var status: Label

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    settings = Settings.load_settings()
    Settings.apply(settings,get_viewport())
    var gradient := Gradient.new()
    gradient.colors = PackedColorArray([Color("#101b20"),Color("#29413e")])
    var texture := GradientTexture2D.new()
    texture.gradient = gradient
    texture.fill_from = Vector2.ZERO
    texture.fill_to = Vector2.ONE
    var background := TextureRect.new()
    background.texture = texture
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var margin := MarginContainer.new()
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_"+edge,24)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)
    var center := CenterContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(center)
    var card := PanelContainer.new()
    card.custom_minimum_size.x = minf(430.0,get_viewport_rect().size.x - 48)
    resized.connect(func(): card.custom_minimum_size.x = minf(430.0,get_viewport_rect().size.x - 48))
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("#142328")
    panel.border_color = Color("#49615b")
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(14)
    panel.content_margin_left = 28
    panel.content_margin_right = 28
    panel.content_margin_top = 30
    panel.content_margin_bottom = 28
    card.add_theme_stylebox_override("panel",panel)
    center.add_child(card)
    content = VBoxContainer.new()
    content.add_theme_constant_override("separation",14)
    card.add_child(content)
    _show_main()

func _clear() -> void:
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()

func _label(text: String, font_size: int = 16, color: Color = Color("#d6dfd9")) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(label)
    return label

func _button(text: String, node_name: String, action: Callable, primary: bool = false) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text
    button.custom_minimum_size.y = 50
    button.add_theme_font_size_override("font_size",18)
    for state in ["normal","hover","pressed","focus"]:
        var box := StyleBoxFlat.new()
        box.bg_color = Color("#b8ca91") if primary else Color("#23383c")
        if state == "hover" or state == "focus":
            box.bg_color = box.bg_color.lightened(0.12)
        elif state == "pressed":
            box.bg_color = box.bg_color.darkened(0.10)
        box.set_corner_radius_all(7)
        if state == "focus":
            box.border_color = Color("#e5eedc")
            box.set_border_width_all(2)
        button.add_theme_stylebox_override(state,box)
    for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
        button.add_theme_color_override(state,Color("#15241e") if primary else Color("#e2e9e4"))
    button.pressed.connect(action)
    content.add_child(button)
    return button

func _show_main() -> void:
    _clear()
    _label("CAMPO DE FOGO",32,Color("#f0f2e9"))
    _label("PARTIDA EXPERIMENTAL",13,Color("#9bad9f"))
    _button("Iniciar partida teste","StartButton",_start_match,true).grab_focus()
    _button("Multiplayer","MultiplayerButton",_show_multiplayer)
    _button("Configurações","ConfigButton",_show_config)
    _button("Sair","ExitButton",func(): get_tree().quit())

func _start_match() -> void:
    var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
    if error != OK:
        _label("Não foi possível iniciar a partida.",15)

func _show_multiplayer() -> void:
    _clear()
    _label("Multiplayer",28)
    var note := _label("Em preparação nesta versão Godot. A partida teste está disponível no menu principal.",17)
    note.name = "MultiplayerStatus"
    _button("Voltar","BackButton",_show_main,true)

func _slider(title: String, node_name: String, low: float, high: float, value: float) -> HSlider:
    var caption := _label(title + "  %d%%" % roundi(value),16)
    var slider := HSlider.new()
    slider.name = node_name
    slider.min_value = low
    slider.max_value = high
    slider.step = 1
    slider.value = value
    slider.custom_minimum_size.y = 28
    slider.value_changed.connect(func(current: float): caption.text = title + "  %d%%" % roundi(current))
    content.add_child(slider)
    return slider

func _show_config() -> void:
    _clear()
    _label("Configurações",28)
    var sensitivity := _slider("Sensibilidade do mouse","SensitivitySlider",20,200,float(settings["sensitivity"]) * 100)
    var volume := _slider("Volume geral","VolumeSlider",0,100,float(settings["volume"]) * 100)
    _label("Suavização das bordas",16)
    var aa := OptionButton.new()
    aa.name = "AASelect"
    aa.add_item("Desligada")
    aa.add_item("2× — equilibrada")
    aa.add_item("4× — maior qualidade")
    aa.select(int(settings["msaa"]))
    aa.custom_minimum_size.y = 40
    content.add_child(aa)
    var fullscreen := CheckButton.new()
    fullscreen.name = "FullscreenToggle"
    fullscreen.text = "Tela cheia"
    fullscreen.button_pressed = settings["fullscreen"]
    content.add_child(fullscreen)
    status = _label("",14)
    _button("Salvar","SaveButton",func():
        var values := {"sensitivity": sensitivity.value/100.0,"volume": volume.value/100.0,"msaa": aa.selected,"fullscreen": fullscreen.button_pressed}
        if Settings.save_settings(values) != OK:
            status.text = "Não foi possível salvar as configurações."
            return
        settings = values
        Settings.apply(settings,get_viewport())
        _show_main()
    ,true)
    _button("Voltar","BackButton",_show_main)
