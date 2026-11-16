# Campo de Fogo — integração aplicada em 15/11/2026

Projeto atualizado: `C:/Users/jaime/Documents/GitHub/gameteste/godot`.

As armas Polyy e a locomoção estão ligadas à partida real com Jaime SWAT e à prévia do menu. A escolha local foi confirmada como `jaime_swat`. Jaime Original permanece selecionável e conserva sua apresentação anterior. O controlador físico e as velocidades 5/8 m/s, controles, câmera, munição, dano e recarga foram preservados.

## Armas

Fonte: `C:/Users/jaime/Downloads/3D_low_poly_guns_pack.zip`. GLBs originais em `assets/weapons/polyy/models/`, com PBR importado nativamente. Cenas adaptadoras em `scenes/weapons/polyy/`; sockets de calibração gerados no WeaponModel em runtime.

| Arma | Modelo exato | Comprimento | Triângulos |
| --- | --- | ---: | ---: |
| Pistola | compact_polymer_pistol.glb | 0,21 m | 56.840 |
| Fuzil | modern_tactical_carbine.glb | 0,78 m | 60.012 |
| Sniper | bolt_action_sniper_rifle.glb | 1,10 m | 60.950 |
| Escopeta | pump_action_shotgun.glb | 0,95 m | 60.438 |
| SMG | compact_submachine_gun.glb | 0,55 m | 57.826 |

A inspeção visual mostrou cano em −X na pistola e +X nas outras quatro, apesar da indicação genérica do README. Transformações absolutas evitam escala acumulada. Marcadores Grip, RightGrip, LeftGrip, ReloadGrip, Muzzle e Sight acompanham o modelo. O socket existente no skeleton foi preservado; não foi necessário substituí-lo por BoneAttachment3D. IK ajusta braços/palmas sem escalar ossos. Poses distintas: descanso, caminhada, corrida, agachamento, mira e apresentação procedural de recarga. Não foi fabricado clipe de recarga nem ejeção animada.

Disparo: câmera escolhe alvo; raycast cano→alvo verifica obstrução; cabo→cano impede tiro quando o cano já atravessou uma parede próxima. Luneta mantém FOV real até 8× e traçante de apresentação alinhado ao retículo. A câmera de ombro existente foi preservada: Sight prepara calibração, não constitui nova câmera ADS em primeira pessoa.

Bindings reais preservados: 1 fuzil, 2 sniper, 3 pistola, 4 escopeta, 5 SMG. Não existe granada funcional neste checkout. Os modelos procedurais antigos permanecem no Jaime Original e no fallback; as cinco armas SWAT validadas usam os GLBs detalhados.

## Animação

Fonte: `C:/Users/jaime/Downloads/WALK-RUN-CYCLES-MOCAP.zip`, 16 FBXs em `assets/personagens/jaime/animacoes/rokoko/`. Importação nativa Godot 4.7.2; Blender/conversão não foram necessários. Dois rigs: Rokoko 76 ossos e Mixamo com prefixo mixamorig_ de 54 ossos. Mapas verificáveis para os 52 ossos reais do SWAT, rest transforms e nomes internos dos clipes constam de `tools/rokoko/inspection.json` e `tools/rokoko/report.json`.

| Alias usado | Fonte real | Intervalo/ciclo |
| --- | --- | --- |
| walk_forward | 02-walkforward.fbx | 7,166667–8,3 s; saída 0,833333 s |
| run_forward | 05-running-treadmill.fbx | 6,746666–7,68 s; saída 0,566667 s |
| 7 walks direcionais | HumanM@Walk01_{Backward,Left,Right,ForwardLeft,ForwardRight,BackwardLeft,BackwardRight}.fbx | ciclos existentes; saída 0,833333 s |
| 7 runs direcionais | HumanM@Run01_{Backward,Left,Right,ForwardLeft,ForwardRight,BackwardLeft,BackwardRight}.fbx | ciclos existentes; saída 0,566667 s |
| idle | normal.tres preexistente | preservado |

Os 17 aliases não representam 17 novas capturas Rokoko. Não há sprint independente identificado. Variantes injured/happy/cool/wind permanecem inventariadas, sem serem rebatizadas como sprint. Derivados preservam comprimento/rest do destino e escala, transferem rotações e compensação vertical dos quadris; XZ da raiz é removido para não duplicar deslocamento. Ciclos alinhados por fase, com fechamento suave de 100 ms. Método reproduzível descrito em `tools/rokoko/README.md`.

AnimationTree: BlendSpace2D com oito direções e velocidade local, mais camada superior Tactical filtrada, preservando pernas/quadris. Transição ajustável entre 0,12 e 0,25 s; disparo 0,12 s. Idle/agachar/pulo conservam fallback procedural onde faltam substitutos validados. `set_armed(bool)` desliga camada tática e IK; não foi criado binding de guardar arma nem idle neutro desarmado separado.

Ground IK mantém FK gravado e plantas breves em espaço global, liberadas ao exceder alcance/distância. A medição abaixo vale somente durante plantas ativas em piso plano; não certifica deslizamento zero durante todo ciclo, transições, velocidades ou terrenos. A inspeção por capturas não garante ausência universal de clipping em todas as combinações.

## Testes e resultados

- **25/25 PASS, exit 0**, suíte completa existente e novos testes. Inclui combate, recarga, armas, movimento, colisão/agachar, terreno, áudio, menu, seleção/salvamento e reabertura. Logs: `.godot/regression-polyy-rokoko/results.json`; executor `tools/run_regression.ps1 -Godot <executável>`.
- Novos testes: `weapon_proportions` (cinco fontes exatas, dimensões, 3 ciclos de troca, poses, recarga/reaquisição, cano e fallback); `weapon_obstruction` (parede à frente e cabo→cano); `rokoko_locomotion` (17 aliases, 52 ossos, mapas/loops/períodos); `swat_locomotion_runtime` (oito direções a 5/8 m/s, filtros, armado/desarmado e pés).
- Sniper: teste original e modo `--swat` passaram, incluindo FOV real 4–8×, alvo, munição, sensibilidade, movimento e retorno da câmera.
- Pés: 166 pares de observações de plantas ativas; deslizamento horizontal máximo 0,000001349 m; menor altura dos dedos no piso plano +0,0179997 m. Plantas são curtas e limitadas pelo alcance.
- MCP `godot_check_errors(run_godot:true)`: **exit 0, errors=[]**. Avisos estáticos falsos de extends nos dois scripts que herdam por path; parser Godot aceita ambos. Editor ainda registra três mensagens Unicode/NUL preexistentes.
- CLI carregou `scenes/jaime_swat_game_test.tscn` por 120 frames: **exit 0**. Alguns encerramentos curtos/testes registram avisos ObjectDB de instâncias não liberadas, inclusive dois no carregamento; não foram ocultados.
- Capturas conferidas: cinco modelos, cinco armas × seis poses/vistas e movimento real (idle, walk, run, strafe, backward, mira+movimento, crouch, jump). Artefatos `.godot/weapon-*.png`, `.godot/locomotion-*.png`, `.godot/swat-game-mcp00000029.png`. Sem inversão de câmera ou arma dentro do tronco nas vistas conferidas; isso não substitui sessão humana longa no mapa.
- Medição limitada MCP em Intel UHD/OpenGL Compatibility, 1280×720, 30 frames estáticos: CPU render médio 2,54 ms/frame; GPU 10,23 ms/frame. Codificação Movie Maker domina o tempo total. Nenhum LOD/redução de qualidade aplicado; não é benchmark de combate/multiplayer.

Não executados/inaplicáveis: networking real (menu multiplayer sem backend neste checkout), prone/deitar, escadas, granadas, bots, zona segura e paraquedas não implementados aqui. Nenhum desses sistemas foi inventado ou removido.

## Uso e preservação

Inicie o projeto: **Personagens → Jaime SWAT → Selecionar → Iniciar Partida Teste**. Para teste direto, abra `scenes/jaime_swat_game_test.tscn` e use F6; a cena escolhe SWAT temporariamente sem alterar o salvamento real. O teste anterior `scenes/jaime_swat_test.tscn` também foi preservado.

[Proveniência, nomes dos 16 FBXs, ZIPs, hashes e licenças](ASSET-PROVENANCE-POLYY-ROKOKO.md). Polyy é CC0; a permissão Rokoko verificada cobre uso em projetos inclusive comerciais, sem presumir CC0 ou revenda de FBXs crus. Cinco GLBs e 16 FBXs coincidem por hash com os ZIPs locais. Nenhum ZIP solicitado está faltando.

O `WeaponProportions.gd` citado como fornecido não foi localizado/recebido: a versão integrada é uma implementação local identificada como tal.

Git preservado: branch `feature/campo-de-fogo-rebuild`, índice SHA256 `7469482414B830EB0A1C6FDAD4AA204E54CA20FCCF72E3FEDD32785266CEB2EC`, merge pendente `4d6169dd1b940b1dc6bd75ec7dfbaa851ed9be15`. Sem stage/commit/push/merge/build de distribuição nesta etapa.

[Paths criados/editados](POLYY-ROKOKO-FILES.md)
