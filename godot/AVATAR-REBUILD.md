# Novo avatar humanoide - Campo de Fogo

Esta primeira etapa inclui um avatar **procedural estilizado** construído em GDScript, sem dependência de arquivos externos.

## Arquivos
- `scripts/avatar/avatar_controller.gd`: cria corpo, membros, cabeça e pontos de montagem; anima os pivôs.
- `scripts/player.gd`: troca o visual quadrado pelo novo avatar mantendo `CharacterBody3D`, câmera e armas.
- `tests/polish_smoke.gd`: inclui verificações de montagem do avatar.

## Limites atuais
- **Não é um personagem humano realista em GLB**, nem possui um esqueleto humanoide `Skeleton3D`. É uma base modular para testes de proporção e movimentação; futuras versões deverão trocar a malha por um modelo mais humano e rigado.
- `WeaponMount` foi aproximado do corpo. Os braços usam solução geométrica de dois segmentos para manter as mãos nos apoios da pistola; poses específicas das armas longas e dedos ainda precisam de refinamento visual.
- Animação procedural usa transições simplificadas e IK dos braços, sem captura de movimento nem ciclo detalhado de recarga.
- Validado no Godot 4.6.3 em modo headless: importação, teste básico e encaixe das mãos parado, andando e agachado. A aparência final ainda requer conferência visual no editor. O teste básico já apresenta um aviso de objetos não liberados ao sair.

## Como testar depois do Pull origin
1. Abra `godot/project.godot` pela pasta `Documentos/GitHub/gameteste`, na branch `feature/campo-de-fogo-rebuild`.
2. Pressione F5 e verifique a orientação (costas para a câmera), proporções e se não há corpo duplo.
3. Teste WASD, Shift, Ctrl, salto, mira com botão direito, tiro com esquerdo, recarga e teclas 1–5.
4. Confira a aba Depurador para erros e mande foto do avatar visto de costas, parado, correndo e mirando.
5. Opcional: `godot --headless --path godot --script res://tests/polish_smoke.gd` a partir da raiz do repositório.

A versão principal e a branch anterior não foram alteradas.

Teste de encaixe da pistola: `godot --headless --path godot --script res://tests/avatar_grip.gd`.

## Redesenho tático
- Tronco e pelve com contornos afunilados, colete frontal/traseiro, tiras e bolsos.
- Rosto com mandíbula, nariz, olhos, sobrancelhas e cabelo curto; braços e pernas mais finos, luvas, joelheiras e botas.
- Os apoios das armas e os pivôs de animação continuam ativos. Altura visual acompanha a cápsula configurada (1,80 m por padrão).
- Continua sendo um personagem estilizado procedural, sem modelo humano fotorealista.
- Verificações: `avatar_geometry.gd`, `avatar_grip.gd`, `pistol_visibility.gd`, `weapon_slots.gd` e `polish_smoke.gd`. Geometria também inspecionada em vistas frontal, lateral e traseira por renderização auxiliar; a apresentação final no jogo ainda requer conferência visual no Godot.
