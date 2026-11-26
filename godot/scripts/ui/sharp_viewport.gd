extends TextureRect
## Prévia 3D nítida para a interface (carta do Cofre, vitrines da Loja/Cofre).
## A interface é desenhada em 1280x720 e esticada para a tela (stretch
## canvas_items); um SubViewportContainer renderiza nesse tamanho pequeno e a
## imagem é ampliada -> fica borrada. Aqui o SubViewport segue o tamanho real
## em pixels na tela, com supersampling (SUPERSAMPLE x) e MSAA, e a imagem é
## reduzida para caber no controle.
const GameSettings = preload("res://scripts/game_settings.gd")
const SUPERSAMPLE := 2.0
const SUPERSAMPLE_MOBILE := 1.25
const MAX_SIDE := 2048

var viewport: SubViewport

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.size = Vector2i(64, 64)
	add_child(viewport)

func _ready() -> void:
	texture = viewport.get_texture()
	resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

## Pixels reais do controle na tela vezes o supersampling.
func _fit() -> void:
	if not is_inside_tree() or size.x < 1.0 or size.y < 1.0:
		return
	var screen_scale := get_viewport().get_final_transform().get_scale().x * get_global_transform_with_canvas().get_scale().x
	var factor := maxf(screen_scale, 1.0) * (SUPERSAMPLE_MOBILE if GameSettings.is_mobile() else SUPERSAMPLE)
	var pixels := (size * factor).round()
	var longest := maxf(pixels.x, pixels.y)
	if longest > MAX_SIDE:
		pixels *= MAX_SIDE / longest
	viewport.size = Vector2i(maxi(int(pixels.x), 1), maxi(int(pixels.y), 1))
