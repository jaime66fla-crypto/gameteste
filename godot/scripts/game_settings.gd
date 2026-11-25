extends RefCounted
const PATH := "user://settings.cfg"
# msaa: 0 = desligado, 1 = 2×, 2 = 4×. Padrão 2×: o 4× custa ~25–30% de FPS em
# vídeo integrado (Intel UHD) e quase não aparece em placa dedicada.
# quality: 0 = Baixa, 1 = Média, 2 = Alta (o padrão depende da plataforma).
const DEFAULTS := {"sensitivity": 1.0, "volume": 1.0, "msaa": 1, "fullscreen": false, "quality": 2}
const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2
const QUALITY_NAMES := ["Baixa — mais leve", "Média", "Alta"]
const MOBILE_MAX_MSAA := 1 # celular e qualidade Baixa: no máximo 2×
## Fração da resolução usada para desenhar o 3D (a interface fica sempre nítida).
const QUALITY_3D_SCALE := [0.75, 0.85, 1.0]
## Alcance máximo da sombra do sol por qualidade (o mapa pode pedir menos).
const QUALITY_SHADOW_DISTANCE := [40.0, 50.0, 1000.0]

static func default_quality() -> int:
    # Celular começa no perfil leve (o mesmo da 1.35.1).
    return QUALITY_LOW if is_mobile() else QUALITY_HIGH

static func load_settings(path: String = PATH) -> Dictionary:
    var result := DEFAULTS.duplicate()
    result["quality"] = default_quality()
    var file := ConfigFile.new()
    if file.load(path) == OK:
        for key in result:
            result[key] = file.get_value("game", key, result[key])
    return _normalize(result)

static func _normalize(values: Dictionary) -> Dictionary:
    return {
        "sensitivity": clampf(float(values.get("sensitivity",1.0)), 0.2, 2.0),
        "volume": clampf(float(values.get("volume",1.0)), 0.0, 1.0),
        "msaa": clampi(int(values.get("msaa",DEFAULTS["msaa"])), 0, 2),
        "fullscreen": bool(values.get("fullscreen",false)),
        "quality": clampi(int(values.get("quality",default_quality())), QUALITY_LOW, QUALITY_HIGH)
    }

static func save_settings(values: Dictionary, path: String = PATH) -> Error:
    var clean := _normalize(values)
    var file := ConfigFile.new()
    for key in clean:
        file.set_value("game",key,clean[key])
    return file.save(path)

static func apply(values: Dictionary, viewport: Viewport) -> void:
    var clean := _normalize(values)
    var quality: int = clean["quality"]
    var limit_msaa := is_mobile() or quality == QUALITY_LOW
    viewport.msaa_3d = mini(clean["msaa"], MOBILE_MAX_MSAA) if limit_msaa else clean["msaa"]
    # Abaixo de Alta o 3D é desenhado numa resolução menor e esticado; a
    # interface (canvas_items) continua na resolução cheia.
    viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
    viewport.scaling_3d_scale = QUALITY_3D_SCALE[quality]
    AudioServer.set_bus_mute(0, clean["volume"] <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(clean["volume"],0.001)))
    if DisplayServer.get_name() == "headless":
        return
    # Celular: sempre tela cheia. No Android, "janela" desliga o modo imersivo
    # e a barra de status e os botões de navegação voltam a aparecer.
    var full: bool = clean["fullscreen"] or is_mobile()
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)

## Sombra do sol conforme a qualidade, chamada depois que o mapa configurou o
## sol. Cada faixa redesenha a cena inteira: Alta/Média usam 2 faixas (no
## treino, 4→2 faixas corta ~1/3 dos triângulos); Baixa usa 1 faixa só.
static func apply_shadow_quality(sun: DirectionalLight3D, quality: int) -> void:
    if sun == null:
        return
    quality = clampi(quality, QUALITY_LOW, QUALITY_HIGH)
    if quality == QUALITY_LOW:
        sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    else:
        sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    sun.directional_shadow_max_distance = minf(sun.directional_shadow_max_distance, QUALITY_SHADOW_DISTANCE[quality])

static func is_mobile() -> bool:
    return OS.has_feature("mobile")
