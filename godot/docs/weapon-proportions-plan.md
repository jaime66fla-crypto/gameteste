# Proporções e empunhadura das armas SWAT

**Plano inicial histórico, anterior à localização dos ZIPs.** A etapa foi executada com os cinco GLBs Polyy e os FBXs Rokoko posteriormente encontrados. As observações abaixo sobre modelos ausentes descrevem somente aquela inspeção inicial. Estado final, testes e limitações: [POLYY-ROKOKO-INTEGRATION.md](POLYY-ROKOKO-INTEGRATION.md). Paths exatos: [POLYY-ROKOKO-FILES.md](POLYY-ROKOKO-FILES.md).

Inspeção: as cinco armas em partida usam o fallback procedural; não há GLB em assets/weapons. As escalas combinam Skeleton/Soldier (1,796), WeaponMount (0,48) e weapon_model (0,7 ou 1). Pontos de mão fixos e distância de cano estimada não acompanham o modelo. A pistola provisória tem aproximadamente 43 cm de comprimento axial, antes de considerar a rotação da pose, muito grande para a mão.

O arquivo WeaponProportions.gd citado não foi encontrado no projeto/repositório, Downloads ou Desktop; foi solicitado o caminho/conteúdo. Não afirmar que uma versão fornecida foi integrada sem recebê-la. Prosseguir com uma implementação local isolada dos perfis necessários, registrando essa pendência.

Recursos aproveitáveis, preservados sem edição: Human_Gun.fbx, Human_AssaultRifle.fbx e Human_Rifle.fbx, em assets/personagens/jaime/animacoes/Models/Weapons. Escopeta e SMG não têm modelo próprio importado: manter/ajustar os provisórios existentes e documentar que precisam de substituição artística; jamais substituir um modelo detalhado por primitivas. GLB externo específico em assets/weapons continua prioritário.

Plano:
1. Criar regressão que falhe antes do componente de proporções existir.
2. Centralizar comprimento, origem no cabo, pontos de apoio/cano e poses por arma. Normalizar por dimensões medidas e escala global do pai, usando transformação absoluta, sem multiplicações acumuladas.
3. Integrar somente o caminho visual SWAT. Preservar a reconstrução Original como caminho legado. Marcadores reais fornecem alvos das palmas e cano; mãos usam IK sem alongar os ossos.
4. Ajustar poses de descanso, movimento, corrida, agachamento e mira; manter recarga. Atualizar empunhadura após aplicar recuo visual.
5. Usar o marcador do cano como origem física do disparo, preservando o alvo da câmera, dano, munição, recarga e o traçante de apresentação da luneta.
6. Testar as cinco armas em todas as poses, dimensões/escala após trocas repetidas, mãos, cano e combate. Inspecionar capturas por arma/pose. Rodar suíte, CLI, MCP e revisão independente.

Os modelos/animações originais, controlador procedural, seleção permanente, câmera e dados de combate não devem ser alterados. Cópias dos quatro scripts visuais/controlador antes da mudança e hashes dos recursos foram guardados em .godot/weapon-proportions-before e .godot/weapon-protected.json. Nenhuma publicação autorizada.
