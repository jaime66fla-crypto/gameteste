# Seleção permanente de personagens

O jogo agora abre pelo menu principal (`scenes/menu.tscn`). Execute o projeto com **F5**, abra **Personagens**, escolha **Selecionar**, volte e inicie a partida. A última escolha é carregada automaticamente ao reabrir o jogo.

Para trocar após uma partida, pressione Esc, use Menu principal e volte a Personagens. A seleção é aplicada na próxima partida. Jaime Original permanece disponível.

## Catálogo e salvamento

O catálogo `characters/catalog.tres` contém definições independentes:

| ID permanente | Nome | Definição |
|---|---|---|
| `jaime_original` | Jaime Original | `characters/jaime_original.tres` |
| `jaime_swat` | Jaime SWAT | `characters/jaime_swat.tres` |

Cada definição tem nome, descrição, cena visual e recursos necessários. Adicione outra definição ao catálogo para disponibilizar um novo cartão; IDs devem ser únicos e não devem ser renomeados depois de gravados.

A escolha é salva por ConfigFile em `user://character_selection.cfg`, seção `characters`, chave `selected_id`. O arquivo é separado das configurações de sensibilidade, volume, tela e gráficos. Campos desconhecidos existentes são preservados. O salvamento usa um arquivo temporário exclusivo e renomeia após gravar; falhas de gravação são informadas pelo menu.

Arquivo ausente, ID desconhecido ou leitura inválida usam o Original. Um arquivo corrompido é preservado para recuperação; selecionar outro personagem não o sobrescreve silenciosamente. Se o SWAT não puder ser instanciado, a partida usa o Original, apresenta um aviso no HUD e mantém a preferência gravada. O usuário pode escolher explicitamente Original no menu quando o arquivo de seleção é válido.

## Separação visual e jogabilidade

`player.gd` continua sendo o único controlador da física, câmera, colisão/agachamento, controles, inventário, munição, disparos, dano e recarga. As alterações nele se limitam à instalação do visual selecionado, notificação visual de disparo e identificação no HUD. A instalação procedural anterior permanece como caminho padrão e fallback.

O SWAT está em `scenes/characters/jaime_swat.tscn`, com `scripts/characters/swat_visual.gd`. O adaptador reutiliza os três clips retargetados já validados e um AnimationTree. Quadril/pés usam uma referência procedural oculta do controlador original, com IK nos ossos SWAT, para acompanhar caminhada, corrida, agachamento e salto. As mãos usam os pontos de empunhadura das armas reais do jogador, com ajuste para cada arma e recarga. O adaptador não cria câmera, entrada, projéteis, áudio ou uma segunda arma.

O contrato visual para futuros personagens é: `animate(...)`, `configure_weapon(id, model_scale)`, propriedade `weapon_mount` e, opcionalmente, `is_visual_ready()` e `notify_shot()`. As cenas devem ser normalizadas para 1,80 m; o controlador aplica sua altura configurável por escala uniforme. Personalize aparência e animações na cena/recursos visuais sem alterar o controlador compartilhado. A implementação atual usa clips normais/mira/disparo e adaptação procedural de membros; não acrescenta clips externos de locomoção/recarga ainda não validados.

As prévias usam SubViewports com mundos 3D próprios. Não usam o controlador do jogador, não capturam mouse nem alteram a câmera ou os controles globais.

## Arquivos e preservação

Existentes modificados: `scripts/menu.gd`, `scripts/player.gd`, `project.godot` (somente a cena inicial).

Novos: `characters/*.tres`, `scripts/characters/*.gd`, `scenes/characters/*.tscn`, quatro testes `tests/character_*.gd`, `tools/characters/capture_selection.gd` e esta documentação/plano. Os `.uid` novos são metadados do Godot.

Nenhum modelo GLB/FBX, textura, animação retargetada, `avatar_controller.gd` ou arquivo da cena independente SWAT foi alterado. Configurações e implementação de multiplayer permanecem iguais.

Ponto de recuperação local: `recovery/character-selection-20261114`, commit `b7fc253710450072727aca59d48f882a3bc5a1b2`, com 392 arquivos. O índice Git, a branch ativa e o merge anterior foram preservados. Não houve publicação ou commit da implementação na branch ativa.

## Verificação

Godot 4.7.2: **20 testes aprovados, zero falhas**. Cobertura nova:

- Catálogo, IDs inválidos, arquivo ausente/corrompido e preservação de campos desconhecidos.
- Cartões, prévias, estado de seleção, Voltar e início da partida.
- Preferência carregada em um segundo processo Godot, sem memória compartilhada.
- Ambos os personagens andando, correndo, agachando, mirando, disparando e recarregando com as cinco armas.
- Recurso SWAT indisponível: Original funciona e preferência SWAT permanece no arquivo.
- Suíte anterior completa, incluindo áudio, câmera/luneta, armas, movimento, mapa e cena independente SWAT.

Menu e partida carregaram por 120 frames cada com saída 0. MCP/editor também retornou saída 0, sem erros de script. Há avisos Unicode/NUL do editor e ObjectDB em alguns testes, já observados anteriormente. O teste negativo de ConfigFile produz intencionalmente erros de parse ao injetar um arquivo corrompido; as asserções de fallback e preservação passaram.

Foram inspecionadas quatro capturas em `.godot/character-selection-*.png`: seleção Original, seleção SWAT, SWAT mirando e agachado em partida. O script de captura usa uma câmera de inspeção independente somente durante a captura. Revisão independente: nenhum problema crítico/importante identificado.

Os testes usam arquivos `user://character_*_<pid>.cfg` e removem apenas seus próprios arquivos. A variável `CAMPO_CHARACTER_TEST_PATH` permite executar a suíte com outra preferência de teste, sem alterar a escolha real.

Referências de API utilizadas: [SubViewportContainer 4.7](https://docs.godotengine.org/en/4.7/classes/class_subviewportcontainer.html) e [DirAccess](https://docs.godotengine.org/en/stable/classes/class_diraccess.html).
