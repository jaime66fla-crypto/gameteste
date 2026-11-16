# Cena independente de teste SWAT

Objetivo: integrar postura normal, mira e disparo de fuzil somente em `scenes/jaime_swat_test.tscn`, sem alterar o personagem procedural, a câmera/combate principais ou os arquivos importados.

Inspeção: SWAT possui 52 ossos Mixamo, repouso A, altura aproximada de 1 m, origem no centro. Os FBX Human Soldier têm 56 ossos B-*, repousos com eixos locais diferentes, ossos auxiliares e altura aproximada de 1,75 m. Clips selecionados: MilitaryIdle01, AssaultRifle_Aim01 e AssaultRifle_Aim01_Shoot01 (0,8 s).

Abordagem: gerar novas animações Godot a partir de amostragem dos FBX, mapeando ossos e corrigindo os referenciais de repouso. Preservar translações locais/comprimentos e escala dos ossos SWAT; converter somente rotação e compensação vertical da raiz. Não copiar transformações absolutas dos FBX nem modificar seus imports. Mapear dedos e tratar a diferença de quantidade de segmentos da coluna.

Passos:
- [x] Criar regressão que falha enquanto a cena independente não existe.
- [x] Criar gerador reproduzível e recursos novos em `assets/personagens/jaime/retargeted/`.
- [x] Criar palco iluminado, câmera própria, GLB instanciado e AnimationTree com estados Normal/Mira/Disparo. Mouse direito segura mira; esquerdo testa disparo somente mirando. Nenhum InputMap global é modificado.
- [x] Ajustar o fuzil de teste e a empunhadura com correções limitadas de dois segmentos, preservando comprimentos, articulações e poses da animação.
- [x] Verificar poses em amostras de todos os clips, transições, ausência de escala/deformação estrutural e erro de empunhadura. Inspecionar capturas frontal/lateral renderizadas pelo Godot.
- [x] Executar suíte completa e carregamento pelo CLI. Revisar diff e preservação de todos os arquivos anteriores.

Escolhas de implementação: trabalhar na pasta atual para manter os caminhos MCP. Todo código novo é específico do teste. Sem publicação, merge ou mudança da cena inicial. As animações retargetadas são derivados; GLB/FBX originais permanecem intactos.

Resultados: regressão inicialmente falhou pela ausência da cena; versão final passou. Foram verificadas 36 amostras de clips, 9 poses com skinning CPU dos vértices e empunhadura/continuidade dos braços por frame nas transições. Seis capturas frontal/lateral foram renderizadas e inspecionadas. Suíte completa: 15/16; a falha preexistente `menu_flow.gd` espera menu como cena inicial, enquanto a configuração existente abre a partida. A cena SWAT (180 frames) e a principal (60 frames) carregaram com saída 0. MCP/editor: saída 0 sem erros de script, com os avisos Unicode/NUL já observados. Alguns testes principais continuam emitindo avisos ObjectDB de encerramento.

Preservação: SHA-256 dos 313 arquivos anteriores verificados; zero alterações. Índice Git permaneceu com SHA-256 `7469482414B830EB0A1C6FDAD4AA204E54CA20FCCF72E3FEDD32785266CEB2EC`. Sem alteração da branch ou do merge pendente, commit de implementação ou publicação.

Revisão independente: nenhum achado crítico/importante. Melhoria menor adiada: o gerador usa os índices de quadril/dedos dos pés da importação atual para compensação vertical; se a ordem de ossos do GLB mudar, trocar esses acessos por buscas por nome e revalidar o gerador. O alvo desta integração é o GLB atual, cujo mapa/ordem foi verificado.
