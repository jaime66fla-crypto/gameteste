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
Menu > **Jogar online** > **Procurar sala**. A partida é uma eliminatória de 8 jogadores e não começa sozinha: na sala, cada jogador clica em **Estou pronto** e o primeiro jogador da sala (líder, marcado com ★) clica em **Iniciar partida**, liberado só quando todos estão prontos. Se o líder sair, o próximo da sala assume. As vagas livres são completadas com bots. As salas de equipe usam a mesma regra de pronto. Cada um tem uma vida e vence o último vivo. O limite é de 8 minutos; ao final, vence quem tiver mais abates. Quem morre vira espectador (clique para trocar de câmera).

- **Equipes 2x2 / 4x4 (sala personalizada):** Jogar online > aba **Equipes 2x2 / 4x4** > **Criar sala**. O jogo mostra um código de 5 caracteres (botão **Copiar**); os amigos entram em **Entrar com código**. Na sala, cada um escolhe a equipe (Alfa ou Bravo). O líder (quem criou; se sair, passa para o próximo) escolhe 2 contra 2 ou 4 contra 4, liga ou desliga **Completar vagas com bots** e clica em **Iniciar partida**. Alfa nasce no MERCADO/OFICINA e Bravo no GALPÃO/ESCRITÓRIO, dois por construção. Não há fogo amigo (o servidor também recusa). Aliados aparecem com o nome em azul, visível através das paredes. Vence a equipe que eliminar a outra; no limite de 8 minutos, vence quem tiver mais abates (depois, mais sobreviventes). A sala não fecha no fim da partida: **Voltar para a sala** leva todos ao mesmo lobby, com o mesmo código, equipes, líder, modo e opção de bots; cada um confirma pronto de novo e o líder inicia a próxima. O XP é o mesmo da eliminatória, e a vitória vale para toda a equipe vencedora. Servidor: Durable Object `party:<código>` em `../src/godot-match.js`. Testes: `node --test tests/godot-party.test.mjs` (na raiz) e `tests/party_flow.gd`.
- **Granadas (G):** segure G para mirar: aparecem a trajetória prevista (pontos), uma marca onde ela toca primeiro e um círculo vermelho do raio de explosão (7 m) onde ela vai explodir. Solte G para lançar; Esc cancela. Enquanto mira a granada, a arma não dispara. A previsão (`predict_path` em `scripts/weapons/grenade.gd`) aproxima os quiques; teste: `tests/grenade_aim.gd`. Metade das caixas de armas traz uma granada (máximo 3). O jogo de quem lança simula o voo (quica nas paredes, explode em 2,6 s) e informa onde explodiu; o servidor confere o tempo e a distância e aplica dano de até 100 no centro, caindo a 0 em 7 m. Sem dano em aliados; a própria granada fere quem lançou, sem contar abate.
- **Torre de vigia:** no canto leste do parque, rampa de 12 m e plataforma a 6 m com mureta. No topo há uma caixa com sniper e uma granada (`tower` em `data/match_layout.json`); só dá para abrir lá de cima. Os bots não sobem.
- **Inclinar (Q/E):** segurando o botão direito (mira), Q inclina para a esquerda e E para a direita: a visão desliza ~0,4 m e gira, limitada pela parede ao lado. Os outros veem o corpo inclinar (as áreas de acerto acompanham).
- **Kit médico e recarga levam 3 s,** com um relógio simples abaixo da mira. Durante o kit não dá para atirar; o servidor recusa o kit sem os 3 s.
- **Amigos:** Menu > **Amigos** adiciona pelo nome, aceita/recusa pedidos e mostra quem está online, em sala ou em partida (com **Entrar na sala**). Na sala personalizada aparece **Convidar amigos**; o convidado recebe um aviso no menu com **Entrar**. Rotas `/godot/friends*` em `../src/godot-accounts.js`; o jogo consulta a cada 8 s.
- **Bots** que não veem nem ouvem ninguém (30 m) andam por pontos aleatórios do mapa inteiro.
- O menu principal mostra, em letra pequena, todas as patentes com o XP de cada uma.
- Nascimento e loot: cada jogador nasce dentro de uma das 8 construções, virado para a porta, **sem arma**. Há 16 caixas de suprimento (uma em cada construção e 8 em ruas, praça, parque e pátio), cada uma com uma arma e munição extra. Perto de uma caixa, **E** coleta (longe de caixas, E continua sendo a cotovelada). As teclas 1 a 5 seguem a ordem em que as armas foram pegas (a primeira é 1, a próxima 2...). Há também 6 **kits médicos** (caixa branca com cruz vermelha) nas bordas do mapa: **E** guarda o kit (acumula até 5) e **F** usa um, recuperando 50 de vida (máximo 100). Quem morre deixa uma caixa com as armas e os kits que tinha. Os bots coletam kits depois de armados e usam quando a vida cai abaixo de 45. O servidor sorteia o conteúdo, confere a distância, garante que cada caixa só abre uma vez e só aceita dano de armas coletadas. O layout (nascimentos, portas e caixas) fica em `data/match_layout.json`, usado pelo jogo e pelo servidor e validado por `tests/match_layout.gd`. As bordas do mapa têm paredes. Nas áreas abertas há 15 paredes de concreto para se proteger (`COVER_WALLS` em `scripts/world_polish.gd`): muretas de 1,2 m (cobrem agachado, dá para atirar por cima) e paredes de 2,2 m (cobertura total).
- Servidor: Durable Object `GodotMatch` (`../src/godot-match.js`) no Worker `floral-haze-1c57`, rota `wss://floral-haze-1c57.jaime66fla.workers.dev/godot/ws`. O servidor guarda a vida de todos e limita o dano por arma.
- Bots: rodam no jogo do primeiro jogador (anfitrião), com a colisão real do mapa, e patrulham as avenidas. Navegam por uma grade A* gerada da colisão do mapa no início da partida (`scripts/net/bot_nav.gd`), contornando caixotes e prédios; para sair ou entrar numa construção seguem a linha da porta (ponto dentro, em frente à porta → ponto fora). A arma dos personagens em 3ª pessoa aponta para o ponto da mira (`set_aim_target` em `downloaded_avatar.gd`). Se o anfitrião sai, o próximo jogador assume.
- Cliente: autoload `Net` (`scripts/net/net.gd`), `scripts/net/match_controller.gd` e `scripts/net/net_actor.gd`.
- Teste com servidor local: `npx wrangler dev` na raiz do repositório e, no jogo, `-- --server=ws://127.0.0.1:8787/godot/ws`.

## Tela durante a partida (HUD)
Sem blocos de texto fixos. Canto superior esquerdo: **minimapa redondo** que gira com você (ruas, prédios, árvores, grama alta; aliados em azul nas equipes; inimigos e zumbis não aparecem). Canto inferior direito: **munição** (pente / reserva, arma na mão, teclas das armas; no mata-mata, kits e granadas). Os controles aparecem segurando **F1**. Personagem: agachar dobra as pernas e abaixa o corpo (as áreas de acerto descem junto); desarmado, os braços ficam soltos ao lado do corpo. Fotos de conferência: `tools/characters/capture_poses.gd` e `tools/survival/capture_game.tscn`; teste `tests/crouch_pose.gd`.

## Sobrevivência zumbi (mundo aberto, 16 jogadores)
Menu > **Jogar online** > aba **Sobrevivência** > **Entrar no mundo**. Não há sala de espera: você entra num mundo com vaga (até 16 pessoas por mundo) e nasce no mato com água, barra de cereal e bandagem.

- **Mapa (480 × 480 m):** a cidade do Campo de Fogo fica no meio; em volta, Vila Rosário (farmácia), Bairro Novo (mercadinho), Posto Rodovia (conveniência e oficina), Fazenda Boa Vista, Vila Pesqueira (delegacia), Hospital São Lucas e Base Militar, ligadas por estradas com carros abandonados, ~1.000 árvores, rochas, arbustos de frutas, grama baixa pelo campo e 150 manchas de **grama alta** (1,3–1,7 m). Agachado dentro da grama alta, os zumbis só te veem a 4 m e perdem a pista; em pé na grama ou agachado fora dela, enxergam 35% menos. Gerado por `node scripts/gen-survival-world.mjs` em `data/survival_world.json` (semente fixa).
- **Saque (E):** revista geladeiras, armários, guarda-roupas, caixas de ferramentas, armários de remédios, prateleiras, porta-malas, armários de armas e caixas militares (1 s). Cada tipo sorteia da sua tabela; o recipiente esvaziado volta a ter coisas depois de 20 min.
- **Inventário (TAB):** o personagem carrega 10 kg nos bolsos. Mochila se **equipa** nas costas (botão Equipar; aparece no personagem para todos): escolar +12 kg, improvisada +9, militar +24. Só dá para tirar se o resto couber nos bolsos; ao morrer ela cai junto. No inventário: comer/beber/curar, largar, pegar do recipiente e fabricar. Armas vêm descarregadas: a munição do calibre na mochila é a reserva (R recarrega). F usa bandagem/analgésico/kit médico (o kit leva 3 s).
- **Coleta (segure E):** árvore → madeira, rocha → pedra, carro → sucata (às vezes pólvora), arbusto → maçã. Machado rende mais madeira; pé de cabra, mais pedra e sucata. O recurso volta depois de alguns minutos.
- **Fabricação:** bandagem, corda, machado improvisado, mochila improvisada e munição 9mm / calibre 12 / 5.56.
- **Fome e sede** caem com o tempo (~75 e ~50 min); zeradas, tiram vida.
- **Zumbis:** andarilhos lentos, corredores e brutamontes. Veem até 24 m (metade de noite), ouvem tiros a 48 m, perseguem e mordem. Q é soco ou a melhor arma branca da mochila (taco, pé de cabra, machado). Nascem longe dos jogadores, mais nas cidades, no hospital e na base.
- **Dia e noite:** um dia dura 24 min (noite das 20h às 6h, bem escura).
- **Morte:** tudo fica numa mochila no chão (25 min); renasce em 8 s com o kit inicial. Ao sair do jogo, o personagem (posição, vida, fome, sede e mochila) fica guardado no mundo por 3 dias.
- Servidor: Durable Object `GodotSurvival` (`../src/godot-survival.js`, rota `/godot/survival`, mundos `world:1`…`world:12`). Ele guarda vida, fome, sede, mochilas, recipientes e recursos e confere distância e tempo de cada ação. Os zumbis são movidos pelo jogo de um dos jogadores (anfitrião), como os bots; o servidor limita mordidas a 1 por segundo e por zumbi, ao alcance. Itens, saques, coleta e receitas: `data/survival_items.json`.
- Testes: `node --test tests/godot-survival.test.mjs` (na raiz), `tests/survival_world.gd` (`--script`) e `godot --headless --path godot res://tests/survival_session.tscn`.

## Versão e atualizações (Windows)
A versão do jogo fica em `project.godot` (`application/config/version`, hoje 0.5.1) e aparece no menu principal. Ao procurar uma partida, o jogo envia o número da versão (0.1.0 = 100, 0.2.0 = 200). Se o número for menor que `GODOT_MIN_BUILD` (em `../wrangler.jsonc`), o servidor responde "Atualização disponível" com o botão **Baixar no itch.io** (`GODOT_DOWNLOAD_URL`) em vez de colocar o jogador numa sala. Mudanças só nas regras do servidor (dano, tempos, bots) não exigem atualização do jogo.

Publicar uma versão nova:
1. Aumente `config/version` em `project.godot`.
2. `powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1` (exporta e envia com o butler para o canal `windows`; quem instalou pelo app do itch recebe a atualização automaticamente). Use `-DryRun` para só exportar.
3. Só se a comunicação jogo ↔ servidor mudar: aumente `GODOT_MIN_BUILD` e publique o Worker.

O destino do butler (`usuario/jogo`) fica em `tools/itch_target.txt`. O butler está instalado em `%LOCALAPPDATA%\itch-butler\butler.exe`.

## Publicar no itch.io
No editor, abra Projeto > Exportar > **Web** > Exportar Projeto. A saída vai para `itch/web/index.html`. Compacte o *conteúdo* de `itch/web` (com `index.html` na raiz do zip) e envie como jogo HTML no itch.io. O filtro de exclusão do preset deixa de fora as animações de origem (`assets/personagens/jaime/animacoes`, os `.fbx`/`.png` de `downloaded/movements`), os addons de editor, os testes, a documentação e os builds antigos. O jogo usa apenas as versões convertidas em `.tres`. Resultado: pacote de ~85 MB e zip de ~74 MB.

## Menu principal
F5 abre o menu com **Iniciar partida teste**, **Multiplayer**, **Configurações** e **Sair**. A primeira opção carrega o mapa jogável, com três bonecos de treino à frente (dois perto e um a 20 m) que mostram o dano de cada acerto (arma e parte do corpo), quantos acertos matariam e o total da sequência; granadas offline também acertam os bonecos; Multiplayer abre a eliminatória online e as salas personalizadas em equipes.

Configurações permitem salvar sensibilidade do mouse, volume, suavização de bordas (desligada/2×/4×) e tela cheia no armazenamento local do jogo. Durante a partida, pressione Esc para liberar o cursor e clique em **Menu principal** no canto superior direito. Ao iniciar uma partida nova, o clique do menu não dispara a arma.

Na luneta da sniper, o rastro visual parte do eixo do retículo e mantém espessura discreta conforme o zoom; a verificação de acerto continua no mesmo eixo da câmera. Testes adicionais: `menu_flow.gd` e `game_settings.gd`.
