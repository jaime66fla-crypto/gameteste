# Novo avatar humanoide - Campo de Fogo

Esta primeira etapa inclui um avatar **procedural estilizado** construído em GDScript, sem dependência de arquivos externos.

## Arquivos
- `scripts/avatar/avatar_controller.gd`: cria corpo, membros, cabeça e pontos de montagem; anima os pivôs.
- `scripts/player.gd`: troca o visual quadrado pelo novo avatar mantendo `CharacterBody3D`, câmera e armas.
- `tests/polish_smoke.gd`: inclui verificações de montagem do avatar.

## Limites atuais
- **Não é um personagem humano realista em GLB**, nem possui um esqueleto humanoide `Skeleton3D`. É uma base modular para testes de proporção e movimentação; futuras versões deverão trocar a malha por um modelo mais humano e rigado.
- `WeaponMount` mantém a arma em um ponto associado ao corpo, mas ainda precisa de refinamento visual de mãos, dedos e poses conforme cada arma.
- Animação procedural usa transições simplificadas, sem IK, captura de movimento nem ciclo detalhado de recarga.
- Não houve teste de execução do Godot nesta sessão.

## Como testar depois do Pull origin
1. Abra `godot/project.godot` pela pasta `Documentos/GitHub/gameteste`, na branch `feature/campo-de-fogo-rebuild`.
2. Pressione F5 e verifique a orientação (costas para a câmera), proporções e se não há corpo duplo.
3. Teste WASD, Shift, Ctrl, salto, mira com botão direito, tiro com esquerdo, recarga e teclas 1–5.
4. Confira a aba Depurador para erros e mande foto do avatar visto de costas, parado, correndo e mirando.
5. Opcional: `godot --headless --path godot --script res://tests/polish_smoke.gd` a partir da raiz do repositório.

A versão principal e a branch anterior não foram alteradas.
