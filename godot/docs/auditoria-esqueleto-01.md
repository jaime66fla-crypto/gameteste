# Auditoria do esqueleto do 01 (Zero One)

Data: 2026-11-26 · Godot 4.7.2 · jogo 1.50.0 (pós-remoção dos personagens, commit `5589f31`)

Gerado por `tools/characters/audit_01_skeleton.gd` (rode de novo com
`godot --headless --path godot --script res://tools/characters/audit_01_skeleton.gd -- --out=<json>`).
Comparação feita contra o **Ch31** (`assets/personagens/downloaded/avatar.fbx`),
que é o rig onde todos os clipes do jogo foram feitos, contra o
`SkeletonProfileHumanoid` do Godot e contra a nomenclatura do Mixamo.
Medidas em metros já na escala do jogo (personagem com 1,8 m).

## Onde está

| Item | Valor |
|---|---|
| Cena do personagem | `scenes/characters/01.tscn` → `scripts/characters/avatar_01.gd` (estende `downloaded_avatar.gd`) |
| Modelo | `assets/personagens/01/01_modelo.scn` (gerado por `tools/characters/build_mannequin_model.gd -- --id=01` a partir de `01.glb`, MakeHuman/MPFB) |
| Skeleton3D | `Avatar/Skeleton3D` · 65 ossos · prefixo `mixamorig_` (Ch31: `mixamorig9_`) |
| Escala aplicada | 0,969 (altura de origem 1,858 m → 1,8 m) |
| Malhas | `01` (corpo, 8 superfícies) + `Roupa_bermuda`, `Roupa_bone`, `Roupa_calca`, `Roupa_camiseta`, `Roupa_tenis` |

## Resumo dos achados

| # | Achado | Gravidade | Efeito no jogo |
|---|---|---|---|
| 1 | **Pés afundam ~3 cm no chão** em todos os clipes parados/andando (Ch31: 0 cm) | Alta | Pé atravessa o chão; corpo parece "pesado/torto" |
| 2 | **Mãos giradas ~31° em torno do antebraço** em relação ao Ch31, em todos os clipes | Alta | Palma/dedos no plano errado; pegada da arma parece torcida |
| 3 | **Proporções diferentes do rig dos clipes**: antebraço maior que o braço (0,319 vs 0,303 m; Ch31 0,216 vs 0,277) e ombros estreitos (0,324 vs 0,422 m) | Média | Poses de arma feitas para o Ch31 colocam as mãos em outro lugar; o IK compensa dobrando cotovelos |
| 4 | Rest pose em **A-pose** (braços 49° abaixo da horizontal); Ch31 está em T-pose | Baixa hoje | Não afeta os clipes atuais (os eixos foram alinhados), mas atrapalha o retarget nativo do Godot (BoneMap), que espera T-pose |
| 5 | Dobra do punho na malha fica 3,3 cm depois da junta, já na mão | Baixa | Punho um pouco "mole" em rotações fortes |
| — | Hierarquia, nomes, ossos obrigatórios, roupas e bind pose | OK | Nada a corrigir |

### O que está certo (não é a causa do "torto")

- **Direção dos membros nos clipes: erro 0°.** Rodando os mesmos clipes no 01 e
  no Ch31, cada segmento (coluna, pescoço, ombro, braço, antebraço, mão, coxa,
  canela, pé) aponta exatamente para o mesmo lado. O `build_mannequin_model.gd`
  alinhou os eixos locais dos ossos do 01 aos do Ch31, então a cópia direta de
  rotação em `downloaded_avatar.gd::_retarget_clip` é válida.
- **Joelhos sempre dobram para a frente** (mínimo +5 cm à frente da linha
  quadril–tornozelo): nunca dobram ao contrário.
- **Cotovelos e joelhos em ângulos possíveis**: cotovelo 57°–152°, joelho
  51°–166° (180° = esticado). Nenhuma hiperextensão.
- **Juntas no lugar certo da malha**: a malha dobra a 1,3 cm do cotovelo, 2 cm
  do joelho e 1 cm do tornozelo.
- **Roupas no mesmo esqueleto**: as 5 `Roupa_*` apontam para o mesmo Skeleton3D
  do corpo, com as mesmas 52 ligações (binds), e a bind pose bate com a rest
  (erro máximo 1,3 mm). Elas se movem junto com o corpo. Nada a alterar.
- **Ossos**: os mesmos 65 do Ch31, mesma hierarquia, nenhum osso a mais ou a
  menos.

## 1. Pés atravessando o chão

Menor altura do pé (dedão/tornozelo) em relação ao chão de repouso, em 12
amostras por clipe. Negativo = abaixo do chão.

| Clipe | 01 | Ch31 |
|---|---|---|
| idle_unarmed | −0,030 m | 0,000 m |
| idle_with_rifle | −0,035 m | 0,000 m |
| walk_unarmed | −0,031 m | 0,000 m |
| walk_with_rifle | −0,028 m | −0,007 m |
| run_in_place | −0,028 m | −0,017 m |
| jog_unarmed | −0,052 m | −0,055 m |

**Causa:** `_retarget_clip` escala a altura do quadril dos clipes por
`altura do quadril do 01 / altura do Ch31` (0,987 / 0,952 = 1,037). Só que as
pernas do 01 são 13% mais longas que as do Ch31 (coxa + canela: 0,900 vs
0,796 m). Com os joelhos levemente dobrados, como em quase todo clipe, a perna
mais longa alcança mais embaixo do que o quadril sobe, e o pé afunda.

**Correção prevista (Etapa 3):** escalar a translação do quadril pelo
comprimento da perna (ou deslocar o quadril até o pé de apoio tocar o chão),
em vez de usar a altura de repouso do quadril. Opcionalmente, IK de pé (Etapa 5).

## 2. Mãos torcidas

O eixo indicador→mindinho da mão do 01 fica **31° (esquerda) / 32° (direita)**
girado em relação ao do Ch31, no mesmo quadro de cada clipe. O valor é igual em
todos os clipes, então é um desvio fixo do rig, não da animação: o osso da mão
do 01 tem o mesmo referencial do Ch31, mas a malha da mão (a geometria do
MakeHuman) está girada dentro dele.

**Correção prevista (Etapa 3):** compensar a torção (twist) da mão no build do
rig (medindo a linha dos dedos ao alinhar o osso) ou aplicar um ajuste fixo de
rotação nas trilhas de `Hand`/dedos ao fazer o retarget.

## 3. Proporções

| Segmento | 01 | Ch31 | Referência humana (1,8 m) |
|---|---|---|---|
| Altura do quadril | 0,987 | 0,952 | ~0,95 |
| Coxa (UpLeg→Leg) | 0,454 | 0,415 | ~0,44 |
| Canela (Leg→Foot) | 0,446 | 0,381 | ~0,44 |
| Tronco (Hips→Neck) | 0,489 | 0,535 | ~0,52 |
| Pescoço (Neck→Head) | 0,087 | 0,070 | ~0,08 |
| Braço (Arm→ForeArm) | 0,303 | 0,277 | ~0,31 |
| **Antebraço (ForeArm→Hand)** | **0,319** | 0,216 | ~0,26 |
| **Ombros (entre as juntas Arm)** | **0,324** | 0,422 | ~0,38–0,40 |
| Quadril (entre as juntas UpLeg) | 0,221 | 0,180 | ~0,18–0,20 |

- O **antebraço do 01 é mais longo que o braço** (razão 1,05; o normal é cerca
  de 0,85). Parte disso é a junta do punho estar 3,3 cm antes da dobra da
  malha (achado 5). O resto vem do modelo low-poly.
- Os **ombros são estreitos**. Com o tronco curto e as pernas longas, o
  personagem fica com silhueta de "boneco".
- Isso **não** é erro de rig: são as medidas do próprio modelo. Corrigir
  exigiria mexer na malha (Blender). Nas animações, o efeito aparece onde as
  mãos precisam chegar a um ponto fixo (arma), e aí o IK dobra mais os
  cotovelos.

## 4. Rest pose (A-pose) e rotações de repouso

Direção de repouso dos segmentos, no espaço do esqueleto (T-pose ideal: braço
esquerdo = +X, perna = −Y):

| Segmento | 01 | Ch31 |
|---|---|---|
| LeftArm | (0,66, −0,75, 0,00) → **49° para baixo** | (1,00, −0,06, −0,06) |
| LeftForeArm | (0,50, −0,49, 0,72) → para baixo e para a frente | (1,00, 0,04, 0,06) |
| LeftUpLeg | (0,10, −0,99, 0,08) | (0,09, −0,99, −0,08) |
| Spine | (0, 1, 0) | (0, 0,995, −0,10) |
| Neck | (0,02, 0,99, 0,13) | (0, 0,96, 0,29) |

Por isso a diferença de rotação de repouso por osso é grande nos braços
(ombro 16°–22°, braço 24°–30°, antebraço 46°), nas pernas (coxa 14°, pé 18°) e
no pescoço (14,5°). Também há um tilt de 5° no Hips. Como os eixos locais foram
alinhados, isso **não** entorta os clipes atuais (ver "Direção dos membros: 0°").
Mas, se a Etapa 3 usar o retarget nativo do Godot (BoneMap +
SkeletonProfileHumanoid + "Fix Silhouette"), a A-pose precisa ser tratada.

## 5. Comparação com o SkeletonProfileHumanoid e o Mixamo

- **52 de 56** ossos do perfil humanoide do Godot existem no 01. Faltam só
  opcionais: `Root`, `LeftEye`, `RightEye`, `Jaw`.
- Todos os ossos **obrigatórios** do perfil existem.
- Nomes: Mixamo padrão com prefixo `mixamorig_`. O jogo não usa BoneMap: o
  `downloaded_avatar.gd` casa os ossos pelo sufixo (`Hips`, `LeftForeArm`…).
- Ossos-folha do Mixamo que não entram no perfil: `HeadTop_End`, `*Thumb4`,
  `*Index4`, `*Middle4`, `*Ring4`, `*Pinky4`, `*Toe_End`. Normal.
- Mapeamento Mixamo → perfil usado: Spine→Spine, Spine1→Chest,
  Spine2→UpperChest, Arm→UpperArm, ForeArm→LowerArm, UpLeg→UpperLeg,
  Leg→LowerLeg, ToeBase→Toes, Thumb1/2/3→ThumbMetacarpal/Proximal/Distal,
  dedos 1/2/3→Proximal/Intermediate/Distal, Pinky→Little.

## O que isso significa para as próximas etapas

- **Etapa 3 (retarget):** o retarget atual por nome e rotação está correto nas
  direções. Não precisa ser refeito do zero. Faltam duas correções concretas:
  (1) altura do quadril pelo comprimento da perna, para o pé parar de afundar;
  (2) compensação fixa da torção das mãos. As roupas já estão no mesmo
  esqueleto.
- **Etapas 4 e 5:** o "torto/não humano" que sobra depois disso tende a vir das
  camadas procedurais do `downloaded_avatar.gd` (braços relaxados, mira, IK da
  arma) e da física do `player.gd` (aceleração e giro). Isso não foi auditado
  aqui: é o próximo passo.

## Ossos (hierarquia completa)

Comprimento = distância até o primeiro filho, na escala do jogo. "Δ rest" =
diferença da rotação local de repouso contra o mesmo osso do Ch31 (⚠ ≥ 20°).

| # | Osso (sem prefixo) | Perfil humanoide | Comp. 01 (m) | Comp. Ch31 (m) | Δ rest |
|---|---|---|---|---|---|
| 0 | `Hips` | Hips | 0,091 | 0,107 | 5,2° |
| 1 | &nbsp;&nbsp;`Spine` | Spine | 0,111 | 0,125 | 0,6° |
| 2 | &nbsp;&nbsp;&nbsp;&nbsp;`Spine1` | Chest | 0,121 | 0,143 | 0,0° |
| 3 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`Spine2` | UpperChest | 0,166 | 0,161 | 0,0° |
| 4 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`Neck` | Neck | 0,087 | 0,070 | 14,5° |
| 5 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`Head` | Head | 0,251 | 0,238 | 9,4° |
| 6 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`HeadTop_End` | — | 0,000 | 0,000 | 0,0° |
| 7 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftShoulder` | LeftShoulder | 0,120 | 0,146 | 22,0° ⚠ |
| 8 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftArm` | LeftUpperArm | 0,303 | 0,277 | 24,4° ⚠ |
| 9 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftForeArm` | LeftLowerArm | 0,319 | 0,216 | 45,5° ⚠ |
| 10 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHand` | LeftHand | 0,051 | 0,046 | 5,4° |
| 11 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandThumb1` | LeftThumbMetacarpal | 0,035 | 0,037 | 29,5° ⚠ |
| 12 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandThumb2` | LeftThumbProximal | 0,041 | 0,033 | 17,5° |
| 13 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandThumb3` | LeftThumbDistal | 0,027 | 0,026 | 67,9° ⚠ |
| 14 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandThumb4` | — | 0,000 | 0,000 | 0,0° |
| 15 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandIndex1` | LeftIndexProximal | 0,029 | 0,034 | 14,7° |
| 16 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandIndex2` | LeftIndexIntermediate | 0,026 | 0,032 | 11,7° |
| 17 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandIndex3` | LeftIndexDistal | 0,029 | 0,028 | 73,3° ⚠ |
| 18 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandIndex4` | — | 0,000 | 0,000 | 0,0° |
| 19 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandMiddle1` | LeftMiddleProximal | 0,038 | 0,035 | 23,9° ⚠ |
| 20 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandMiddle2` | LeftMiddleIntermediate | 0,031 | 0,034 | 9,5° |
| 21 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandMiddle3` | LeftMiddleDistal | 0,031 | 0,030 | 70,3° ⚠ |
| 22 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandMiddle4` | — | 0,000 | 0,000 | 0,0° |
| 23 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandRing1` | LeftRingProximal | 0,033 | 0,029 | 23,7° ⚠ |
| 24 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandRing2` | LeftRingIntermediate | 0,028 | 0,028 | 6,3° |
| 25 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandRing3` | LeftRingDistal | 0,024 | 0,023 | 65,9° ⚠ |
| 26 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandRing4` | — | 0,000 | 0,000 | 0,0° |
| 27 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandPinky1` | LeftLittleProximal | 0,024 | 0,026 | 32,6° ⚠ |
| 28 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandPinky2` | LeftLittleIntermediate | 0,018 | 0,023 | 5,1° |
| 29 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandPinky3` | LeftLittleDistal | 0,019 | 0,018 | 65,1° ⚠ |
| 30 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftHandPinky4` | — | 0,000 | 0,000 | 0,0° |
| 31 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightShoulder` | RightShoulder | 0,118 | 0,146 | 16,4° |
| 32 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightArm` | RightUpperArm | 0,303 | 0,277 | 30,1° ⚠ |
| 33 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightForeArm` | RightLowerArm | 0,319 | 0,215 | 46,0° ⚠ |
| 34 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHand` | RightHand | 0,051 | 0,045 | 5,1° |
| 35 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandThumb1` | RightThumbMetacarpal | 0,035 | 0,036 | 28,3° ⚠ |
| 36 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandThumb2` | RightThumbProximal | 0,041 | 0,034 | 16,1° |
| 37 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandThumb3` | RightThumbDistal | 0,030 | 0,029 | 69,6° ⚠ |
| 38 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandThumb4` | — | 0,000 | 0,000 | 0,0° |
| 39 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandIndex1` | RightIndexProximal | 0,029 | 0,033 | 18,1° |
| 40 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandIndex2` | RightIndexIntermediate | 0,026 | 0,031 | 12,5° |
| 41 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandIndex3` | RightIndexDistal | 0,028 | 0,026 | 76,1° ⚠ |
| 42 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandIndex4` | — | 0,000 | 0,000 | 0,0° |
| 43 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandMiddle1` | RightMiddleProximal | 0,038 | 0,036 | 21,6° ⚠ |
| 44 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandMiddle2` | RightMiddleIntermediate | 0,031 | 0,033 | 6,6° |
| 45 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandMiddle3` | RightMiddleDistal | 0,030 | 0,029 | 70,1° ⚠ |
| 46 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandMiddle4` | — | 0,000 | 0,000 | 0,0° |
| 47 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandRing1` | RightRingProximal | 0,033 | 0,030 | 24,3° ⚠ |
| 48 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandRing2` | RightRingIntermediate | 0,028 | 0,028 | 6,4° |
| 49 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandRing3` | RightRingDistal | 0,025 | 0,024 | 67,3° ⚠ |
| 50 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandRing4` | — | 0,000 | 0,000 | 0,0° |
| 51 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandPinky1` | RightLittleProximal | 0,024 | 0,028 | 33,4° ⚠ |
| 52 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandPinky2` | RightLittleIntermediate | 0,018 | 0,024 | 6,0° |
| 53 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandPinky3` | RightLittleDistal | 0,022 | 0,021 | 65,4° ⚠ |
| 54 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightHandPinky4` | — | 0,000 | 0,000 | 0,0° |
| 55 | &nbsp;&nbsp;`LeftUpLeg` | LeftUpperLeg | 0,454 | 0,415 | 14,3° |
| 56 | &nbsp;&nbsp;&nbsp;&nbsp;`LeftLeg` | LeftLowerLeg | 0,446 | 0,381 | 7,6° |
| 57 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftFoot` | LeftFoot | 0,156 | 0,196 | 18,5° |
| 58 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftToeBase` | LeftToes | 0,084 | 0,080 | 19,4° |
| 59 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`LeftToe_End` | — | 0,000 | 0,000 | 0,0° |
| 60 | &nbsp;&nbsp;`RightUpLeg` | RightUpperLeg | 0,454 | 0,415 | 14,5° |
| 61 | &nbsp;&nbsp;&nbsp;&nbsp;`RightLeg` | RightLowerLeg | 0,446 | 0,381 | 7,2° |
| 62 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightFoot` | RightFoot | 0,156 | 0,200 | 17,6° |
| 63 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightToeBase` | RightToes | 0,084 | 0,080 | 18,9° |
| 64 | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`RightToe_End` | — | 0,000 | 0,000 | 0,0° |
