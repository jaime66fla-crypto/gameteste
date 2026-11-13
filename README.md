# Street Prototype V2

Jogo 3D para navegador com Three.js e salas multiplayer em Cloudflare Durable Objects.

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

## Validação

Use Node.js 22 ou superior:

```sh
npm ci
npm run check
npm test
```

Os testes do jogo atual usam o Three.js r128 incluído em `public/vendor/`. Os testes do protótipo `3d.js` e do carregador FBX usam a dependência de desenvolvimento Three.js 0.187.0 fixada no lockfile. A publicação no `main` só começa depois da validação completa.
