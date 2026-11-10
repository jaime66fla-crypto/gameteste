# Street Prototype V2

Protótipo de jogo 2D para navegador.

## Deploy

O projeto usa Cloudflare Workers Static Assets.

- Worker: `floral-haze-1c57`
- Arquivos públicos: `public/`
- Configuração: `wrangler.jsonc`
- Deploy automático: `.github/workflows/deploy-cloudflare.yml`

Para o deploy automático funcionar, configure no GitHub os secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Depois disso, qualquer push na branch `main` dispara o deploy.
