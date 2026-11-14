# Mapa organizado — Campo de Fogo

Mapa de 120 × 120 m construído por uma única rotina em `scripts/world_polish.gd`. `main.gd` fornece apenas chão e iluminação; os blocos de teste e as árvores antigas foram retirados.

- Avenidas centrais e via perimetral conectadas; ruas locais atendem casas e comércio.
- Noroeste: quatro casas com caminhos até as ruas.
- Sudoeste: mercado, oficina e área de convivência.
- Nordeste: galpão, escritório, acesso de carga e estacionamento.
- Sudeste: parque com caminhos, bancos e árvores.
- Início na praça junto às avenidas, fora do interior de construções.

As oito construções têm entrada aberta e colisão nas paredes e nos telhados. Janelas são decorativas; não existem andares superiores sem escada. Caixas aparecem no galpão e na oficina. Árvores têm colisão no tronco e posições fixas, longe das portas e das vias.

Validação: `godot --headless --path godot --script res://tests/map_layout.gd`. O teste usa a cápsula do jogador para verificar ruas, início, passagens das portas e acesso às entradas por deslocamentos sem atravessar paredes. Também foram executados os cinco testes anteriores de avatar, armas e inicialização.

A disposição superior foi conferida por projeção dos limites da geometria. Ainda falta avaliar o mapa caminhando na renderização final do Godot.
