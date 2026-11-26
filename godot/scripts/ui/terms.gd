extends Control
## Termos de Uso e Privacidade dentro do jogo: janela por cima da tela atual
## (quem está criando conta não perde o que já digitou). Esc ou "Fechar" fecha.
## O mesmo texto está no site (termos.html no branch gh-pages): mude os dois juntos.

signal closed

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const VERSION := "26 de novembro de 2026"
const SITE_URL := "https://jaime66fla-crypto.github.io/gameteste/termos.html"
const MAX_WIDTH := 860.0

const SUMMARY := """[ul]O jogo é grátis. Brasas são opcionais e só valem dentro do jogo.
Trapaça dá suspensão: o servidor confere tiros, velocidade e saldo.
Respeite os outros jogadores no chat, no nick e na foto.
Guardamos só o que a sua conta precisa para funcionar. Não vendemos seus dados.
Comprou Brasas e não gastou? Você tem 7 dias para pedir o dinheiro de volta.[/ul]"""

## [título, corpo em BBCode]
const SECTIONS := [
	["1. Sobre estes termos", """Estes termos valem para o jogo [b]Campo de Fogo[/b] (Windows e Android), para os servidores online do jogo e para o site, incluindo a Loja de Brasas. O Campo de Fogo é um jogo independente feito por [b]jaimexzz[/b] (“nós”).

Ao criar uma conta, jogar online ou comprar Brasas, você concorda com estes termos. Se não concordar, não use o serviço."""],
	["2. Idade e responsáveis", """[ul]O jogo tem combate com armas de fogo. Se você tem menos de 18 anos, jogue com o conhecimento dos seus pais ou responsáveis.
Menores de 18 anos só podem comprar Brasas com autorização de um responsável.
Se você tem menos de 12 anos, um responsável precisa concordar com estes termos e com o uso de dados descrito na seção 8 antes de você criar uma conta.[/ul]"""],
	["3. Sua conta", """[ul]Você escolhe um [b]nome de jogador[/b] (3 a 16 letras) e uma [b]senha[/b]. O nome é público: aparece no ranking, no chat e para os seus amigos.
A senha é guardada só como hash (PBKDF2-SHA256): nem nós conseguimos lê-la. Não use a mesma senha de outros serviços. [b]Nunca[/b] pediremos sua senha pelo chat.
A conta é pessoal. Você responde pelo que acontece nela. Não compartilhe, empreste, venda nem compre contas.
A conta não tem e-mail, então não existe recuperação automática de senha. Guarde a sua senha. Se perder, fale conosco: tentamos ajudar, mas não garantimos a recuperação.
Nicks ofensivos, que imitem outra pessoa ou a equipe do jogo podem ser trocados, e a conta pode ser suspensa.[/ul]"""],
	["4. Regras de conduta", """Não é permitido:
[ul]usar cheats, hacks, aimbot, wallhack, speed hack, macros ou qualquer programa que dê vantagem;
modificar o jogo, a memória dele ou o tráfego de rede, ou mandar mensagens falsas para o servidor;
explorar bugs de propósito (por exemplo, duplicar itens ou Brasas) em vez de avisar;
atacar, sobrecarregar ou tentar invadir os servidores ou a conta de outra pessoa;
ofender, ameaçar, assediar ou discriminar alguém (por raça, cor, etnia, religião, gênero, orientação sexual, deficiência, origem ou qualquer outro motivo) no chat, no nick ou na foto de perfil;
enviar conteúdo sexual, violência real, dados pessoais de outras pessoas, golpes, links maliciosos ou spam;
vender, trocar ou anunciar contas, Brasas ou itens por dinheiro fora da loja oficial;
se passar pela equipe do Campo de Fogo.[/ul]
Achou um bug ou um trapaceiro? Avise pelos canais da seção 13."""],
	["5. Anticheat e punições", """[ul]O servidor confere as partidas automaticamente: o momento dos tiros em relação aos acertos, a cadência das armas, a velocidade de movimento e o saldo de Brasas. As infrações ficam registradas na conta.
Conforme a gravidade, a punição pode ser: aviso, saída do ranking, suspensão temporária ou banimento permanente. Conta suspensa não aparece no ranking.
Brasas e itens de uma conta banida por trapaça [b]não são reembolsados[/b].
Acha que foi punido por engano? Fale conosco: revisamos o caso.[/ul]"""],
	["6. Brasas e itens virtuais", """[ul]Brasas são a moeda virtual do jogo. Você ganha jogando e também pode comprar. Elas servem para liberar itens no jogo (personagens, roupas, skins de armas e outros).
Brasas [b]não têm valor em dinheiro[/b]: não podem ser sacadas, trocadas por dinheiro nem transferidas para outra conta.
Os itens liberados são uma licença pessoal para usar o conteúdo dentro do jogo, enquanto o jogo existir. Eles não são propriedade sua fora do jogo.
Preços e pacotes podem mudar. Mudanças não afetam compras já pagas.
Para manter o jogo justo, itens e armas podem ser rebalanceados (dano, cadência, alcance etc.).[/ul]"""],
	["7. Compras de Brasas por PIX", """[ul]Brasas são vendidas só na Loja de Brasas do site, com [b]PIX processado pelo Mercado Pago[/b]. Não pedimos nem guardamos dados bancários ou de cartão. O pagamento segue também os termos e a política de privacidade do Mercado Pago.
Pedimos um e-mail para o comprovante. Ele é enviado ao Mercado Pago e fica guardado no pedido.
As Brasas caem na conta quando o Mercado Pago confirma o pagamento, normalmente em segundos. Se o PIX expirar sem pagamento, nada é cobrado.
[b]Direito de arrependimento:[/b] conforme o art. 49 do Código de Defesa do Consumidor, você pode desistir da compra em até [b]7 dias[/b] depois do pagamento. Devolvemos o valor pelo Mercado Pago, desde que as Brasas daquele pacote ainda não tenham sido gastas.
Pagou e as Brasas não caíram, ou foi cobrado duas vezes? Fale conosco com o número do pedido (está no Histórico de compras da loja). Corrigimos creditando as Brasas ou devolvendo o dinheiro.
Se o pagamento for devolvido ou contestado (chargeback), as Brasas daquele pedido são retiradas da conta, mesmo que o saldo fique negativo. Contestação de má-fé pode levar à suspensão da conta.[/ul]"""],
	["8. Privacidade e dados pessoais", """Tratamos dados pessoais conforme a Lei Geral de Proteção de Dados (LGPD, Lei 13.709/2018). Guardamos só o necessário:
[ul][b]Nome de jogador e senha (em hash):[/b] entrar na conta. O nome é público.
[b]Progresso:[/b] XP, patente, abates, vitórias, partidas, personagens, roupas, skins e saldo de Brasas, para o jogo e o ranking funcionarem.
[b]Foto de perfil (opcional):[/b] mostrada aos outros jogadores. Você pode remover quando quiser.
[b]Amigos:[/b] lista de amigos, pedidos, convites e se você está online.
[b]Chat:[/b] as últimas 50 mensagens do chat global e de cada conversa com amigo ficam no servidor; as mais antigas são apagadas sozinhas. O chat global é visível para todos.
[b]Anticheat:[/b] registros de infrações e suspensões, para manter as partidas justas.
[b]Compras:[/b] pacote, valor, data, situação, número do pagamento no Mercado Pago e e-mail do comprovante, para entregar as Brasas, atender reembolsos e cumprir obrigações legais.
[b]Dados de conexão:[/b] endereço IP e dados técnicos passam pela Cloudflare para entregar o serviço e proteger contra ataques.
[b]No seu aparelho:[/b] o jogo guarda seu nome, a sessão e as configurações. O site guarda no navegador o nome usado no feedback, o login da loja e o e-mail da última compra.
[b]Feedback do site:[/b] o nome e o comentário que você envia aparecem publicamente na página inicial.[/ul]
[b]Bases legais:[/b] execução do contrato (conta, jogo e compras), legítimo interesse (segurança e anticheat) e cumprimento de obrigação legal (registros de pagamento).

[b]Com quem compartilhamos:[/b] só com quem faz o serviço funcionar: Cloudflare (servidores do jogo), Mercado Pago (pagamentos), GitHub Pages (site) e itch.io (download do jogo). Não vendemos seus dados e não usamos seus dados para anúncios.

[b]Seus direitos:[/b] você pode pedir confirmação e acesso aos seus dados, correção, cópia (portabilidade), informações sobre o compartilhamento e a exclusão da conta. O nick e a foto você troca no próprio jogo, em Perfil. Os outros pedidos são feitos pelo contato da seção 13.

Excluir a conta apaga o progresso, os itens e as Brasas, sem reembolso das Brasas já usadas. Os registros de compras ficam guardados pelo tempo exigido por lei.

[b]Segurança:[/b] a comunicação usa conexão criptografada (HTTPS/WSS) e as senhas ficam só em hash. Nenhum sistema é 100% seguro; se acontecer um incidente que afete seus dados, avisaremos no jogo e no site."""],
	["9. O jogo está em desenvolvimento", """[ul]O Campo de Fogo é oferecido no estado em que está. Pode ter bugs, quedas de servidor e perda de progresso, e os mundos de Sobrevivência podem ser reiniciados.
Podemos mudar, adicionar ou remover conteúdo, modos e mapas, e exigir a versão mais nova para jogar online.
Se o serviço online for encerrado, avisaremos no jogo e no site com pelo menos [b]30 dias[/b] de antecedência, e a venda de Brasas para no dia do aviso.[/ul]"""],
	["10. Propriedade intelectual", """[ul]O jogo, o nome, o logo, os personagens, os mapas, o código, os sons e as artes pertencem ao Campo de Fogo ou a quem nos licenciou.
Você pode fazer vídeos, lives e prints do jogo, inclusive monetizados, desde que não diga que são oficiais.
Não é permitido copiar, vender, redistribuir, fazer engenharia reversa ou distribuir versões modificadas do jogo. Baixe só pela página oficial no itch.io.[/ul]"""],
	["11. Responsabilidade e suspensão", """[ul]Fazemos o possível para manter o jogo no ar e seguro, mas não garantimos funcionamento sem interrupções. Dentro do que a lei permite, não respondemos por danos indiretos, como partidas perdidas ou posição no ranking.
Nada nestes termos tira os direitos que o Código de Defesa do Consumidor garante a você.
Você pode parar de jogar e pedir a exclusão da conta quando quiser. Podemos suspender ou encerrar contas que violem estes termos (seção 5).[/ul]"""],
	["12. Mudanças nos termos e lei aplicável", """[ul]Podemos atualizar estes termos. A data no topo mostra a versão em vigor. Mudanças importantes serão avisadas no jogo ou no site; continuar jogando depois do aviso significa que você concorda.
Estes termos seguem as leis do Brasil. Fica eleito o foro do domicílio do consumidor.[/ul]"""],
	["13. Contato", """Reembolsos, pedidos sobre seus dados, denúncias e suspensões: escreva para [b]jaime66fla@gmail.com[/b]. Em pedidos de compra, mande o número do pedido e o nome da sua conta.

Dúvidas e bugs também podem ir na página do Campo de Fogo no itch.io (jaimexzz.itch.io/campo-de-fogo). Não mande sua senha em nenhuma mensagem."""],
]

var _margin: MarginContainer
var _close_button: Button

## Texto completo em BBCode (resumo + seções), também usado pelos testes.
static func bbcode() -> String:
	var accent := UiTheme.ACCENT.to_html(false)
	var parts := PackedStringArray()
	parts.append("[color=#%s][b]RESUMO RÁPIDO[/b][/color]\n%s" % [accent, SUMMARY])
	for section in SECTIONS:
		parts.append("[font_size=19][b][color=#%s]%s[/color][/b][/font_size]\n%s" % [accent, section[0], section[1]])
	return "\n\n".join(parts)

func _ready() -> void:
	name = "TermsOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # nada atrás recebe clique
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.74)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.card(22.0, UiTheme.PANEL_SOLID))
	_margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	column.add_child(UiTheme.caps("CAMPO DE FOGO", 12, UiTheme.ACCENT))
	column.add_child(UiTheme.title("Termos de Uso e Privacidade", 26))
	column.add_child(UiTheme.label("Versão de " + VERSION, 13, UiTheme.MUTED))

	var text := RichTextLabel.new()
	text.name = "TermsText"
	text.bbcode_enabled = true
	text.fit_content = false
	text.scroll_active = true
	text.selection_enabled = true
	text.focus_mode = Control.FOCUS_ALL # setas/PageDown rolam o texto
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.y = 160
	text.add_theme_font_override("normal_font", UiTheme.font(400))
	text.add_theme_font_override("bold_font", UiTheme.font(700))
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.add_theme_color_override("default_color", Color("#d6dfd9"))
	text.add_theme_constant_override("line_separation", 3)
	var inset := UiTheme.inset(16.0)
	text.add_theme_stylebox_override("normal", inset)
	text.add_theme_stylebox_override("focus", UiTheme.box(Color.TRANSPARENT, Color(UiTheme.ACCENT, 0.5), 1, 8))
	text.text = bbcode()
	column.add_child(text)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var site := UiTheme.secondary(Button.new(), 14)
	site.name = "TermsSiteButton"
	site.text = "Abrir no site"
	site.custom_minimum_size = Vector2(0, 44)
	site.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	site.pressed.connect(func(): OS.shell_open(SITE_URL))
	buttons.add_child(site)
	_close_button = UiTheme.primary(Button.new(), 15)
	_close_button.name = "TermsCloseButton"
	_close_button.text = "Fechar"
	_close_button.custom_minimum_size = Vector2(0, 44)
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.pressed.connect(close)
	for button in [site, _close_button]:
		button.focus_mode = Control.FOCUS_ALL # teclado/controle navegam
	buttons.add_child(_close_button)

	resized.connect(_fit)
	_fit()
	_close_button.grab_focus()

## Janela centrada de até MAX_WIDTH; no celular ocupa a tela com margem pequena.
func _fit() -> void:
	if _margin == null:
		return
	var view := size if size.x > 0.0 else get_viewport_rect().size
	var side := int(maxf(12.0, (view.x - MAX_WIDTH) * 0.5))
	var vertical := int(clampf(view.y * 0.06, 12.0, 48.0))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", vertical)
	_margin.add_theme_constant_override("margin_bottom", vertical)

func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
