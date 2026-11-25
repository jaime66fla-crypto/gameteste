extends RefCounted
const PATH := "user://settings.cfg"
const DEFAULTS := {"sensitivity": 1.0, "volume": 1.0, "msaa": 2, "fullscreen": false} # msaa 2 = 4×
const MOBILE_MAX_MSAA := 1 # celular: no máximo 2× (4× pesa muito na GPU do aparelho)
const MOBILE_3D_SCALE := 0.75

static func load_settings(path: String = PATH) -> Dictionary:
    var result := DEFAULTS.duplicate()
    var file := ConfigFile.new()
    if file.load(path) == OK:
        for key in result:
            result[key] = file.get_value("game", key, result[key])
    return _normalize(result)

static func _normalize(values: Dictionary) -> Dictionary:
    return {
        "sensitivity": clampf(float(values.get("sensitivity",1.0)), 0.2, 2.0),
        "volume": clampf(float(values.get("volume",1.0)), 0.0, 1.0),
        "msaa": clampi(int(values.get("msaa",2)), 0, 2),
        "fullscreen": bool(values.get("fullscreen",false))
    }

static func save_settings(values: Dictionary, path: String = PATH) -> Error:
    var clean := _normalize(values)
    var file := ConfigFile.new()
    for key in clean:
        file.set_value("game",key,clean[key])
    return file.save(path)

static func apply(values: Dictionary, viewport: Viewport) -> void:
    var clean := _normalize(values)
    viewport.msaa_3d = mini(clean["msaa"], MOBILE_MAX_MSAA) if is_mobile() else clean["msaa"]
    # Celular: o 3D é desenhado a 75% da resolução da tela (≈56% dos pixels) e
    # esticado; a interface (canvas_items) continua na resolução cheia.
    if is_mobile():
        viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
        viewport.scaling_3d_scale = MOBILE_3D_SCALE
    AudioServer.set_bus_mute(0, clean["volume"] <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(clean["volume"],0.001)))
    if DisplayServer.get_name() == "headless":
        return
    # Celular: sempre tela cheia. No Android, "janela" desliga o modo imersivo
    # e a barra de status e os botões de navegação voltam a aparecer.
    var full: bool = clean["fullscreen"] or is_mobile()
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)

static func is_mobile() -> bool:
    return OS.has_feature("mobile")
