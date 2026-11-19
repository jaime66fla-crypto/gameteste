extends RefCounted
## "Mouse preso" do jogo. No PC é o cursor capturado na janela; no celular não
## há mouse, então o estado fica guardado aqui e os controles de toque aparecem
## enquanto ele está "preso" (jogando) e somem quando ele é "solto" (menus,
## loja, morte). Use sempre estas funções em vez de mexer em Input.mouse_mode.

## Modo toque: celular/tablet (app ou navegador) ou forçado com --touch.
static var _touch := -1
static var _captured := false

static func touch_mode() -> bool:
	if _touch < 0:
		var forced := OS.get_cmdline_user_args().has("--touch") or OS.get_cmdline_args().has("--touch")
		var on := forced or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		_touch = 1 if on else 0
		if on and forced and not OS.has_feature("mobile"):
			# Teste no PC: o clique do mouse vira um dedo na tela.
			Input.emulate_touch_from_mouse = true
	return _touch == 1

## Celular deitado tem tela bem mais larga que 16:9: a interface estica em vez
## de deixar faixas pretas nas laterais.
static func setup_window(tree: SceneTree) -> void:
	if touch_mode() and tree != null:
		tree.root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

static func capture() -> void:
	if touch_mode():
		_captured = true
		# Jogando, cada dedo é um controle: o toque não pode virar clique
		# (o clique esquerdo é o tiro). O toque que voltou ao jogo virou
		# clique; o "soltar" dele não chega mais, então solta o tiro aqui.
		Input.emulate_mouse_from_touch = false
		Input.action_release("fire")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

static func release() -> void:
	if touch_mode():
		_captured = false
		# Em menus o toque funciona como clique nos botões.
		Input.emulate_mouse_from_touch = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func is_captured() -> bool:
	if touch_mode():
		return _captured
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
