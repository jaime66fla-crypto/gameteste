# Instruções para agentes (Codex, ChatGPT, Claude)

## Publicar Campo de Fogo no itch.io — caminho rápido

Quando o Jaime disser **"publique tudo"** (ou "aplique tudo"), isso já é a
autorização: faça o lançamento do cliente (Windows **e** Android, mesma
versão) sem perguntar de novo.
Não leia o projeto inteiro, não rode a suíte toda, não reexplore o código.
São ~6 comandos. Desde a 1.34.0 o Android voltou: **não** use `-SkipAndroid`.

Shell: Windows PowerShell 5.1 (sem `&&`; use `;`). Git não está no PATH:

```powershell
$git = (Get-ChildItem "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe" | Sort-Object FullName | Select-Object -Last 1).FullName
$butler = "$env:LOCALAPPDATA\itch-butler\butler.exe"   # já logado; nunca peça/mostre chave
$target = "jaimexzz/campo-de-fogo:windows"
$android = "jaimexzz/campo-de-fogo:android"
```

### 1. Estado (1 comando)
```powershell
& $git status --short; & $git log --oneline -3; & $butler status jaimexzz/campo-de-fogo; Select-String godot\project.godot -Pattern 'config/version'
```
- Se o `butler status` já mostra a versão nova nos **dois** canais → já está
  publicado, pare. Só um deles atrasado → envie só esse (ver passo 5).
- Arquivos modificados que **não** são da sua tarefa (outra ferramenta
  trabalhando) → pergunte ao Jaime se entram; se não, exporte de uma cópia
  limpa (ver "Cópia limpa" abaixo). Ignore sempre `godot/tools/mcp-godot/.tmp-smoke-project`.

### 2. Versão
Suba `config/version` em `godot/project.godot` (1.25.0 → 1.25.1 correção,
→ 1.26.0 recurso). Edite só essa linha; salve **sem BOM**.

### 3. Teste só o que mudou
Rode 1–2 testes ligados à mudança, sempre com `--quit-after` (alguns testes
antigos travam):
```powershell
$g = "C:\Users\jaime\Documents\Godot area de criação\Godot_v4.7.2-stable_win64.exe"
& $g --headless --path godot --quit-after 3000 --script res://tests/<teste>.gd
```
Falhas já conhecidas (não são regressão): `tests/match_layout.gd` (16),
`tests/training_arena.tscn` (2), `avatar_geometry`/`graphics_materials` travam.

### 4. Backup + commit
```powershell
$old = (& $butler status $target | Select-String '\d+\.\d+\.\d+').Matches[-1].Value
Copy-Item godot\itch\windows\CampoDeFogo.exe "godot\itch\CampoDeFogo_$old.exe"
& $git add <arquivos da tarefa> godot/project.godot
& $git commit -F <arquivo-com-mensagem>   # here-string via pipe NÃO funciona
```
O script apaga `godot/itch/windows` e `godot/itch/android` — o backup tem que
vir antes.

### 5. Exportar e publicar (1 comando, ~5–8 min)
```powershell
Push-Location godot; powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1; Pop-Location
```
Exporta Windows + APK Android assinado (keystore fora do repo, em
`%APPDATA%\Godot\keystores\` — o script lê sozinho) e envia os dois canais.
Já exportou antes e o `export_presets.cfg` já tem a versão? Pode pular o
export e só enviar:
`& $butler push godot\itch\windows $target --userversion <versão>`
`& $butler push godot\itch\android\CampoDeFogo.apk $android --userversion <versão>`

### 6. Fechar
```powershell
& $butler status jaimexzz/campo-de-fogo   # √ + versão nova nos dois canais = no ar
                                          # (o Android pode ficar "∙ processando" ~1 min)
& $git add godot/export_presets.cfg godot/**/*.uid
& $git commit -m "export_presets <versão>"
$env:GIT_TERMINAL_PROMPT="1"; $env:GCM_INTERACTIVE="always"
& $git -c credential.helper= -c credential.helper=manager push origin HEAD
```
Responda ao Jaime em 3–5 linhas: versão, build do itch, commits, o que ficou de fora.

### Servidor (só se precisar)
Mudou protocolo cliente↔servidor ou `godot/data/survival_world.json`?
Então o Worker Cloudflare `floral-haze-1c57` também precisa de deploy, e
subir `GODOT_MIN_BUILD` (wrangler.jsonc) **exige OK explícito do Jaime**.
Publique o itch primeiro, depois o Worker. Mudança só de cliente (armas,
animação, UI, som) → não mexa no servidor.

### Cópia limpa (trabalho alheio não commitado na pasta)
```powershell
$dst = "$env:TEMP\cdf_clean\godot"
robocopy godot $dst /MIR /XD "$((Resolve-Path godot).Path)\itch" /NFL /NDL /NJH /NJS /NP
# nos arquivos alheios: restaure a versão do HEAD (git show HEAD:<arquivo>) e apague os não rastreados
Push-Location $dst; powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1; Pop-Location
Copy-Item "$dst\export_presets.cfg" godot\export_presets.cfg
```

### Nunca
- Mostrar/copiar credenciais (butler, Git, Cloudflare, keystore).
- Publicar só um dos canais quando os dois deveriam sair (Windows e Android
  andam juntos, mesma versão).
- Subir `GODOT_MIN_BUILD` ou fazer `wrangler deploy` sem OK.
- Commitar `godot/itch/`, builds ou `.tmp-smoke-project`.
