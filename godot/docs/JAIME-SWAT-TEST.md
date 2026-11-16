# Jaime SWAT: teste de mira do fuzil

Abra `res://scenes/jaime_swat_test.tscn` no Godot e pressione **F6** (executar cena atual). F5 continua abrindo o jogo principal, que não foi alterado.

## Controles da cena

- Segure o botão direito: mira.
- Clique com o esquerdo enquanto mira: animação de disparo. Ao terminar, retorna à mira.
- Solte o direito: retorna à postura normal, inclusive durante o disparo.
- Teclas 1 e 2: vistas frontal e lateral da câmera exclusiva deste teste.

O teste não captura o cursor, não registra ações no InputMap global e não cria projéteis nem chama o combate principal.

## Recursos e retargeting

Modelo: `assets/personagens/jaime/[FREE] Rigged Stylized SWAT Soldier.glb`.

Clips masculinos do pacote Human Soldier, sob `assets/personagens/jaime/animacoes/Animations/Male/`:

| Estado | Arquivo fonte |
|---|---|
| Normal / prontidão baixa | `Idles/HumanM@MilitaryIdle01.fbx` |
| Mira | `Combat/AssaultRifle/HumanM@AssaultRifle_Aim01.fbx` |
| Disparo | `Combat/AssaultRifle/HumanM@AssaultRifle_Aim01_Shoot01.fbx` |

O SWAT possui 52 ossos `mixamorig*`, e o pacote possui 56 ossos `B-*`. Há diferenças de eixos locais, pose de repouso, origem, proporções e quantidade de segmentos da coluna. Os nomes não são intercambiáveis. O FBX também inclui raiz, mandíbula, pontos de arma e um proxy da coluna que não são ossos de deformação equivalentes no SWAT.

`tools/jaime_swat/build_retarget.gd` mapeia explicitamente os 52 ossos, incluindo dedos. Corrige os referenciais de repouso com bases construídas pela direção das articulações, aplica a rotação relativa da animação fonte e distribui o movimento da coluna. Os comprimentos/posições locais do SWAT permanecem iguais aos originais; a raiz recebe somente compensação vertical para o apoio dos pés. Os clips são amostrados a 30 Hz e salvos como recursos novos em `assets/personagens/jaime/retargeted/`. O disparo dura 0,8 s e não entra em loop.

O GLB mantém sua escala e seu repouso originais. Apenas a instância na cena é normalizada para aproximadamente 1,80 m, elevada até o piso e orientada para -Z. Nenhum `.glb`, `.fbx` ou configuração de importação original é regravado.

O `AnimationTree` e seus estados/transições estão serializados na cena para inspeção no editor. Os fades são 0,20 s entre Normal/Mira, 0,07 s na entrada de Disparo e 0,08 s no retorno. O avanço manual mantém a aplicação de animação, arma e IK numa ordem determinística.

## Empunhadura

O fuzil é uma instância de `animacoes/Models/Weapons/Human_AssaultRifle.fbx`; seu material escuro é aplicado somente à instância de teste. Dois pontos de empunhadura orientam IK analítico dos braços, sem escala ou extensão dos ossos. A calibração das palmas corrige a diferença de orientação dos punhos; os dedos recebem uma pose de empunhadura, com o indicador direito próximo ao gatilho. A postura normal mantém a arma em prontidão baixa. O tronco e os ombros conservam a animação retargetada.

Esta primeira integração é para os três clips de fuzil selecionados e o modelo atual. Não é ainda um controlador de locomoção, sistema de mira livre ou retargeter universal para outros personagens/armas. Animações dos dedos são mascaradas pela pose de empunhadura calibrada.

## Reprodução das verificações

Use o executável Godot 4.7.2 configurado neste computador no lugar de `godot`:

```powershell
godot --headless --path . --script tools/jaime_swat/build_retarget.gd
godot --headless --path . --script tests/jaime_swat.gd
godot --path . --rendering-method gl_compatibility --resolution 1280x720 --script tools/jaime_swat/capture_preview.gd
```

O gerador regrava somente os três recursos derivados que ele próprio cria. O último comando abre brevemente uma janela, gera seis PNGs de inspeção em `.godot/swat-preview-*.png` e encerra.

Os testes verificam os clips aplicados, 52 ossos, comprimentos e escalas, skinning dos vértices em amostras das poses, limites do corpo, empunhadura, estados, botões e cancelamento de disparo, além da preservação do InputMap. As capturas frontal e lateral complementam os testes estruturais; estes não substituem avaliação artística em todas as câmeras possíveis.

Resultado no projeto: teste SWAT aprovado; suíte completa 15/16, com a falha preexistente de `menu_flow.gd`. Cenas SWAT e principal carregadas pelo CLI com saída 0. Os 313 arquivos existentes antes desta integração mantiveram seus hashes SHA-256.

Referências de API: [Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html) e [AnimationTree](https://docs.godotengine.org/en/latest/tutorials/animation/animation_tree.html). O comportamento desta implementação foi verificado no CLI 4.7.2 do projeto.
