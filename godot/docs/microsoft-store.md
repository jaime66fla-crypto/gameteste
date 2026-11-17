# Publicar na Microsoft Store

## 1. Conta e nome (uma vez)
1. Crie a conta de desenvolvedor individual em https://storedeveloper.microsoft.com (gratuita para pessoa física).
2. No Partner Center: **Apps e jogos > Novo produto > Aplicativo MSIX ou PWA** e reserve o nome **Campo de Fogo**.
3. Em **Gerenciamento de produto > Identidade do produto**, copie os três valores para `tools/store_identity.json`:

```json
{ "Name": "<Package/Identity/Name>",
  "Publisher": "<Package/Identity/Publisher, começa com CN=>",
  "PublisherDisplayName": "<Package/Properties/PublisherDisplayName>" }
```

## 2. Gerar o pacote
```powershell
powershell -ExecutionPolicy Bypass -File tools\build_msix.ps1 -Export
```
Sai em `store\CampoDeFogo_<versão>_x64.msix`. Sem o `store_identity.json`, o arquivo sai como `_teste.msix`
e não é aceito pela loja. Para cada atualização, aumente `config/version` em `project.godot`: a loja recusa um pacote com versão repetida.

Teste local (opcional): rode com `-TestSign`, importe o `.cer` gerado em `Cert:\LocalMachine\TrustedPeople`
(PowerShell como administrador) e dê dois cliques no `.msix`. Nunca envie à loja um pacote `-TestSign`.

## 3. Envio no Partner Center
- **Preços e disponibilidade:** gratuito, mercados desejados.
- **Propriedades:** categoria *Jogos > Ação e aventura*. Política de privacidade: **obrigatória** (o jogo tem contas e é online). Hospede o texto abaixo numa URL pública (página do itch.io, GitHub Pages, etc.).
- **Classificações etárias:** responda ao questionário IARC (violência com armas, interação online entre usuários).
- **Pacotes:** envie o `.msix`. O aviso sobre a capacidade restrita `runFullTrust` é normal para jogos Win32; justifique com: "Jogo feito na engine Godot, um executável Win32 que precisa de confiança total para rodar."
- **Listagem da loja (pt-BR):** descrição abaixo, pelo menos 1 captura de tela de 1920×1080 ou 1366×768 e o logo 1:1 (300×300+; pode usar `icon.png` ampliado ou arte nova).
- Envie para certificação (de 1 a 3 dias úteis).

## Descrição sugerida
**Campo de Fogo** é um jogo de tiro em terceira pessoa com eliminatória online. Entre numa partida, junte armas,
kits médicos e granadas e seja o último de pé, ou jogue em equipes (Alfa x Bravo) até eliminar o time adversário.

- Partidas online contra outros jogadores e bots
- Modo solo e modo em equipes
- Saque de caixas deixadas pelos eliminados
- Grupos para jogar com amigos
- Progressão de XP e patentes

## Política de privacidade (rascunho)
> **Política de Privacidade — Campo de Fogo**
> Última atualização: <data>
>
> **Dados que coletamos.** Ao criar uma conta, guardamos o nome de jogador que você escolher e a sua senha (armazenada
> de forma protegida, nunca em texto puro). Durante as partidas, o servidor processa dados de jogo (posição, abates, XP,
> patente) e o seu endereço IP para manter a conexão.
>
> **Dados no seu computador.** O jogo salva as configurações e o personagem escolhido localmente; esses arquivos não são enviados.
>
> **Uso.** Usamos os dados apenas para autenticar a sua conta, rodar as partidas, mostrar o seu nome a outros jogadores
> e guardar o seu progresso. Não vendemos dados nem usamos publicidade ou rastreamento de terceiros.
>
> **Compartilhamento.** O servidor do jogo roda num provedor de nuvem (Cloudflare), que processa os dados em nosso nome.
>
> **Exclusão.** Para apagar a sua conta e os dados dela, escreva para <seu e-mail de contato>.
>
> **Crianças.** O jogo não se destina a menores de 13 anos e não coleta dados que identifiquem a pessoa além do nome de jogador.
>
> **Contato.** <seu e-mail de contato>
