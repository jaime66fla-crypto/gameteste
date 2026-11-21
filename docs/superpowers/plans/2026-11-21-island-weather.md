Campo de Fogo — ilha, rio e cheias

Pedido: substituir cercas e paredes laterais por litoral e mar; adicionar rio e chuva que alteram rios e lagos. O usuário confirmou que as cheias podem alcançar o entorno das casas.

Implementação: sistema leve de bacias e nível de água, compartilhado pelo cliente e servidor. Sem simulação de fluido por partícula. O relógio persistente do mundo determina chuva e acumulação, de modo que todos vejam a mesma cheia e reconexões preservem a fase. A chuva aumenta o rio, expande os lagos existentes e enche depressões temporárias; o tempo seco drena gradualmente. Construções permanecem e podem ficar alagadas.

1. Adicionar hydrology ao mapa, fórmulas espelhadas JS/GDScript e testes de chuva, cheia, drenagem, costa e paridade.
2. Substituir placa plana e barreiras por terreno com leito de rio, bacias, praia e fundo do mar. Preservar cidades, montanhas, IDs e estado dos mundos. Construir pontes onde o rio cruza estradas.
3. Renderizar água animada, margens e chuva local com som e abrigo de telhados. Integrar natação, mapa, fontes de água doce e validação de construção/nascimento de animais.
4. Validar testes dirigidos, colisão por raycast, reconexão/sincronização e capturas em tempo seco e chuva. Revisão independente antes de aplicar ao projeto original.

Publicação: este pedido autoriza as alterações no projeto; não modifica por si só a versão mínima de cliente e não apaga mundos existentes.
