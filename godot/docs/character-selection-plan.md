# Seleção permanente de personagens

Recuperação: `b7fc253710450072727aca59d48f882a3bc5a1b2`, `recovery/character-selection-20261114`. Índice, branch e merge pendente preservados.

Escopo aprovado: menu Personagens com cartões e prévias 3D, catálogo extensível com IDs únicos, seleção persistente em user://, partida usando o visual escolhido e fallback ao Original. Preservar modelos/animações originais, câmera, combate, física, controles, configurações e multiplayer.

Arquitetura:
- Definições Resource e catálogo em `characters/`: IDs `jaime_original` e `jaime_swat`, nome e caminho de cena visual. Registro valida IDs/caminhos e persiste somente seleção em ConfigFile separado, preservando outros campos e arquivos inválidos.
- Original: reutilizar `avatar_controller.gd` sem editar sua implementação ou recursos. A instalação original do jogador continua disponível como fallback.
- SWAT: cena/adaptador visual independente, reaproveitando os três clips validados. Recebe os estados do jogador; utiliza o controlador procedural existente como referência oculta de quadril/pés para caminhada, corrida, agachamento e salto. IK mantém pés e mãos em suas posições sem afetar o corpo físico. Mesmas armas do jogador, sem fuzil duplicado ou câmera própria.
- Menu: cartões com SubViewport/World3D próprios, seleção explícita e erro de salvamento visível. Abertura do jogo passa a `menu.tscn`; iniciar partida continua em `main.tscn`.
- Alterações pontuais em `player.gd` para escolher visual, sinalizar disparo e mostrar fallback. Nenhuma alteração de dano, munição, física ou mira.

Verificações:
1. Regressões inicialmente falham pela ausência do registro/menu. Testar ID inválido, ConfigFile ausente/corrompido, persistência e campos desconhecidos preservados.
2. Testar cartões, prévias, seleção, voltar e início da partida.
3. Testar os dois visuais com a mesma câmera/cápsula/armas; SWAT andando, correndo, agachando, mirando, disparando e recarregando. Testar fallback por recurso indisponível.
4. Reabrir em outro processo Godot e confirmar seleção carregada da gravação anterior. Usar caminhos de teste separados da preferência real do usuário.
5. Executar suíte completa, CLI e MCP; capturar menu/prévias e SWAT em partida. Revisão independente e comparação dos arquivos protegidos.

Execução na pasta atual para manter a conexão MCP; sem trocar branch, resolver merge, publicar ou apagar recursos.

## Resultado

Todas as etapas concluídas. Suíte: 20/20, incluindo reabertura real em outro processo. Testes iniciais falharam pela ausência de registro, seleção no jogador e botão Personagens; agora passam. O teste de corrida foi movido para uma avenida livre porque o trajeto inicial encontrava um banco; não houve alteração das colisões para fazê-lo passar. A empunhadura da escopeta foi ajustada no novo visual SWAT. Captura usa câmera independente para preservar a relação câmera/SpringArm do controlador.

Revisão independente: nenhum achado crítico/importante. Carregamento CLI do menu e partida: saída 0. MCP/editor: saída 0, sem erros de script. Dois logs de parse são esperados no teste que injeta ConfigFile corrompido; arquivo e fallback são preservados. Avisos Unicode/NUL e ObjectDB anteriores continuam fora do escopo.

Comparação por SHA-256: somente `scripts/menu.gd` e `scripts/player.gd` mudaram entre os arquivos existentes protegidos; além deles, `project.godot` recebeu somente a cena inicial do menu. Recursos originais, testes anteriores, implementação procedural e teste SWAT independente permanecem intactos. Índice Git mantém SHA-256 `7469482414B830EB0A1C6FDAD4AA204E54CA20FCCF72E3FEDD32785266CEB2EC`; branch e merge pendente preservados. Sem publicação.
