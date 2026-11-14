# Campo de Fogo - Godot

Protótipo experimental em Godot 4. A versão web permanece preservada na branch main.

## Abrir no Godot

Clone ou baixe a branch `feature/campo-de-fogo-rebuild` e importe `godot/project.godot` no editor. Execute com F5.

## Controles

WASD movimentar, mouse girar, Shift correr, Espaço pular, Ctrl agachar, botão direito mirar, esquerdo atirar, R recarregar, Esc liberar cursor.

Armas: 1 fuzil, 2 sniper, 3 pistola, 4 escopeta e 5 SMG.

Na sniper, segure o botão direito para abrir a luneta fechada. A roda do mouse ajusta o aumento entre 4× e 8×; o zoom inicial é 4×. Movimento e tiro continuam disponíveis. Recarregar, trocar de arma ou pressionar Esc fecha a luneta. O campo de visão é calculado para produzir a ampliação indicada, com sensibilidade reduzida conforme o zoom.

O Jaime é um avatar estilizado procedural. Esta branch contém mapa organizado e animações articuladas; multiplayer e exportação web do projeto Godot ainda não estão concluídos.

Teste da luneta: `godot --headless --path godot --script res://tests/sniper_scope.gd`, a partir da raiz do repositório. O teste valida estado da mira, zoom, movimento, disparo no centro e restauração da câmera. A máscara e o mouse capturado ainda precisam de conferência na renderização do jogo.

## Materiais e imagem
Texturas procedurais pequenas de asfalto, concreto, grama, reboco, casca, madeira, metal, tecido e cobertura metálica são geradas uma vez por padrão e compartilhadas. Incluem mapas de cor, normal e rugosidade, com mipmaps e filtragem anisotrópica. O cenário usa escala de textura em metros por projeção triplanar; roupa e armas usam coordenadas locais para o detalhe acompanhar a peça.

Céu com gradiente de horizonte, luz solar e ambiente equilibradas, névoa mais leve e MSAA 2× no renderizador de compatibilidade. Não foram adicionados efeitos de pós-processamento que dependam de Forward+. Verificação de recursos: `godot --headless --path godot --script res://tests/graphics_materials.gd`. A aparência e o desempenho na GPU ainda precisam de teste no jogo.
