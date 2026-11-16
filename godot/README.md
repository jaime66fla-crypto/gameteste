# Campo de Fogo - Godot

Protótipo experimental em Godot 4. A versão web permanece preservada na branch main.

## Abrir no Godot

Clone ou baixe a branch `feature/campo-de-fogo-rebuild` e importe `godot/project.godot` no editor. Execute com F5.

## Controles

WASD movimentar, mouse girar, Shift correr, Espaço pular, Ctrl agachar, botão direito mirar, esquerdo atirar, R recarregar, Esc liberar cursor.

Armas: 1 fuzil, 2 sniper, 3 pistola, 4 escopeta e 5 SMG.

Mira em primeira pessoa: com fuzil, pistola, escopeta ou SMG, segurar o botão direito leva a câmera para os olhos do personagem (estilo CS). O corpo some, a arma aparece no canto inferior direito com os braços e a mira "+" fica no centro. Ao soltar, a câmera volta para a 3ª pessoa. O disparo sai do centro da tela. Ao recarregar, a arma desce e gira. Encostado numa parede, ela fica em posição baixa para não atravessar o cenário. A posição da arma na tela fica em `HOLD`, em `scripts/weapons/first_person_viewmodel.gd`.

Na sniper, segure o botão direito para abrir a luneta fechada. A roda do mouse ajusta o aumento entre 4× e 8×; o zoom inicial é 4×. Movimento e tiro continuam disponíveis. Recarregar, trocar de arma ou pressionar Esc fecha a luneta. O campo de visão é calculado para produzir a ampliação indicada, com sensibilidade reduzida conforme o zoom.

O Jaime é um avatar estilizado procedural. Esta branch contém mapa organizado e animações articuladas; multiplayer e exportação web do projeto Godot ainda não estão concluídos.

Teste da luneta: `godot --headless --path godot --script res://tests/sniper_scope.gd`, a partir da raiz do repositório. O teste valida estado da mira, zoom, movimento, disparo no centro e restauração da câmera. A máscara e o mouse capturado ainda precisam de conferência na renderização do jogo.

## Materiais e imagem
Texturas procedurais pequenas de asfalto, concreto, grama, reboco, casca, madeira, metal, tecido e cobertura metálica são geradas uma vez por padrão e compartilhadas. Incluem mapas de cor, normal e rugosidade, com mipmaps e filtragem anisotrópica. O cenário usa escala de textura em metros por projeção triplanar; roupa e armas usam coordenadas locais para o detalhe acompanhar a peça.

Céu com gradiente de horizonte, luz solar e ambiente equilibradas, névoa mais leve e MSAA 2× no renderizador de compatibilidade. Não foram adicionados efeitos de pós-processamento que dependam de Forward+. Verificação de recursos: `godot --headless --path godot --script res://tests/graphics_materials.gd`. A aparência e o desempenho na GPU ainda precisam de teste no jogo.

## Multiplayer online
Menu > **Multiplayer** > digite o nome > **Procurar partida**. A partida é uma eliminatória de 8 jogadores: começa 20 s depois que o primeiro jogador entra (ou na hora, com 8), e as vagas livres são completadas com bots. Cada um tem uma vida e vence o último vivo. O limite é de 8 minutos; ao final, vence quem tiver mais abates. Quem morre vira espectador (clique para trocar de câmera).

- Servidor: Durable Object `GodotMatch` (`../src/godot-match.js`) no Worker `floral-haze-1c57`, rota `wss://floral-haze-1c57.jaime66fla.workers.dev/godot/ws`. O servidor guarda a vida de todos e limita o dano por arma.
- Bots: rodam no jogo do primeiro jogador (anfitrião), com a colisão real do mapa, e patrulham as avenidas. Se o anfitrião sai, o próximo jogador assume.
- Cliente: autoload `Net` (`scripts/net/net.gd`), `scripts/net/match_controller.gd` e `scripts/net/net_actor.gd`.
- Teste com servidor local: `npx wrangler dev` na raiz do repositório e, no jogo, `-- --server=ws://127.0.0.1:8787/godot/ws`.

## Versão e atualizações (Windows)
A versão do jogo fica em `project.godot` (`application/config/version`, hoje 0.1.0) e aparece no menu principal. Ao procurar uma partida, o jogo envia o número da versão (0.1.0 = 100, 0.2.0 = 200). Se o número for menor que `GODOT_MIN_BUILD` (em `../wrangler.jsonc`), o servidor responde "Atualização disponível" com o botão **Baixar no itch.io** (`GODOT_DOWNLOAD_URL`) em vez de colocar o jogador numa sala. Mudanças só nas regras do servidor (dano, tempos, bots) não exigem atualização do jogo.

Publicar uma versão nova:
1. Aumente `config/version` em `project.godot`.
2. `powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1` (exporta e envia com o butler para o canal `windows`; quem instalou pelo app do itch recebe a atualização automaticamente). Use `-DryRun` para só exportar.
3. Só se a comunicação jogo ↔ servidor mudar: aumente `GODOT_MIN_BUILD` e publique o Worker.

O destino do butler (`usuario/jogo`) fica em `tools/itch_target.txt`. O butler está instalado em `%LOCALAPPDATA%\itch-butler\butler.exe`.

## Publicar no itch.io
No editor, abra Projeto > Exportar > **Web** > Exportar Projeto. A saída vai para `itch/web/index.html`. Compacte o *conteúdo* de `itch/web` (com `index.html` na raiz do zip) e envie como jogo HTML no itch.io. O filtro de exclusão do preset deixa de fora as animações de origem (`assets/personagens/jaime/animacoes`, os `.fbx`/`.png` de `downloaded/movements`), os addons de editor, os testes, a documentação e os builds antigos. O jogo usa apenas as versões convertidas em `.tres`. Resultado: pacote de ~85 MB e zip de ~74 MB.

## Menu principal
F5 abre o menu com **Iniciar partida teste**, **Multiplayer**, **Configurações** e **Sair**. A primeira opção carrega o mapa jogável; Multiplayer informa que a conexão ainda está em preparação nesta versão Godot.

Configurações permitem salvar sensibilidade do mouse, volume, suavização de bordas (desligada/2×/4×) e tela cheia no armazenamento local do jogo. Durante a partida, pressione Esc para liberar o cursor e clique em **Menu principal** no canto superior direito. Ao iniciar uma partida nova, o clique do menu não dispara a arma.

Na luneta da sniper, o rastro visual parte do eixo do retículo e mantém espessura discreta conforme o zoom; a verificação de acerto continua no mesmo eixo da câmera. Testes adicionais: `menu_flow.gd` e `game_settings.gd`.
