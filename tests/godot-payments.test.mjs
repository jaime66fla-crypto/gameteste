// Compra de Brasas pelo site (src/godot-payments.js) com o Mercado Pago simulado.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';

const { GodotAccounts } = await import('../src/godot-accounts.js');
const { validSignature, corsHeaders } = await import('../src/godot-payments.js');
const store = JSON.parse(readFileSync(new URL('../godot/data/store.json', import.meta.url), 'utf8'));
const SECRET = 'segredo-de-teste';
const pack = store.pacotes.find((p) => p.destaque) || store.pacotes[0];

function service(env = { MP_ACCESS_TOKEN: 'token-de-teste', MP_WEBHOOK_SECRET: SECRET }) {
	const data = new Map();
	const storage = {
		get: async (k) => structuredClone(data.get(k)),
		put: async (k, v) => {
			if (typeof k === 'object') for (const [key, value] of Object.entries(k)) data.set(key, structuredClone(value));
			else data.set(k, structuredClone(v));
		},
		delete: async (k) => data.delete(k),
		list: async ({ prefix }) => new Map([...data].filter(([key]) => key.startsWith(prefix))),
	};
	return { accounts: new GodotAccounts({ storage }, env), data };
}

/** Mercado Pago falso: guarda as preferências criadas e responde pagamentos de `payments`. */
function fakeMp(payments = new Map()) {
	const calls = [];
	globalThis.fetch = async (url, init = {}) => {
		calls.push({ url: String(url), init });
		if (String(url).endsWith('/checkout/preferences')) return Response.json({ id: 'pref-1', init_point: 'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=pref-1' });
		const id = String(url).split('/').pop();
		return payments.has(id) ? Response.json(payments.get(id)) : new Response('{}', { status: 404 });
	};
	return calls;
}

async function call(accounts, path, { token = '', body, headers = {} } = {}) {
	const h = { 'content-type': 'application/json', 'x-public-origin': 'https://worker.test', ...headers };
	if (token) h.Authorization = 'Bearer ' + token;
	const response = await accounts.fetch(new Request('https://internal' + path, { method: body ? 'POST' : 'GET', headers: h, body: body ? JSON.stringify(body) : undefined }));
	return { status: response.status, data: await response.json() };
}

async function register(accounts, name) {
	const r = await call(accounts, '/register', { body: { name, password: 'segredo1' } });
	assert.equal(r.status, 201);
	return r.data.token;
}

function signed(dataId, secret = SECRET) {
	const ts = '1764150000';
	const requestId = 'req-' + dataId;
	const v1 = createHmac('sha256', secret).update(`id:${dataId};request-id:${requestId};ts:${ts};`).digest('hex');
	return { 'x-signature': `ts=${ts},v1=${v1}`, 'x-request-id': requestId };
}

const webhook = (accounts, id, headers = signed(id)) => call(accounts, `/pay/webhook?data.id=${id}&type=payment`, { body: { type: 'payment', data: { id } }, headers });

test('checkout creates the order with the server price and the right back/notification URLs', async () => {
	const calls = fakeMp();
	const { accounts, data } = service();
	const token = await register(accounts, 'Comprador');
	const r = await call(accounts, '/pay/checkout', { token, body: { pack: pack.id, preco_centavos: 1 } });
	assert.equal(r.status, 200);
	assert.match(r.data.url, /^https:\/\/www\.mercadopago\.com\.br\//);
	const sent = JSON.parse(calls[0].init.body);
	assert.equal(sent.items[0].unit_price, pack.preco_centavos / 100, 'preço vem do store.json, não do navegador');
	assert.equal(sent.items[0].currency_id, 'BRL');
	assert.equal(sent.external_reference, r.data.order);
	assert.equal(sent.notification_url, 'https://worker.test/godot/pay/webhook');
	assert.match(sent.back_urls.success, new RegExp(`loja\\.html\\?pedido=${r.data.order}$`));
	assert.equal(calls[0].init.headers.Authorization, 'Bearer token-de-teste');
	assert.equal(data.get('order:' + r.data.order).status, 'criado');
});

test('checkout refuses unknown packs, missing sessions and an unconfigured token', async () => {
	fakeMp();
	const { accounts } = service();
	const token = await register(accounts, 'Alguem');
	assert.equal((await call(accounts, '/pay/checkout', { token, body: { pack: 'brasas_999999' } })).status, 404);
	assert.equal((await call(accounts, '/pay/checkout', { body: { pack: pack.id } })).status, 401);
	const off = service({});
	const t2 = await register(off.accounts, 'SemChave');
	assert.equal((await call(off.accounts, '/pay/checkout', { token: t2, body: { pack: pack.id } })).status, 503);
});

test('an approved payment credits the Brasas once, even if the webhook repeats', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts } = service();
	const token = await register(accounts, 'Pagador');
	const before = (await call(accounts, '/me', { token })).data.profile.brasas;
	const { order } = (await call(accounts, '/pay/checkout', { token, body: { pack: pack.id } })).data;
	payments.set('111', { id: 111, status: 'pending', external_reference: order, transaction_amount: pack.preco_centavos / 100, currency_id: 'BRL' });
	assert.equal((await webhook(accounts, '111')).status, 200);
	assert.equal((await call(accounts, '/me', { token })).data.profile.brasas, before, 'PIX pendente não credita');
	payments.get('111').status = 'approved';
	await webhook(accounts, '111');
	await webhook(accounts, '111');
	assert.equal((await call(accounts, '/me', { token })).data.profile.brasas, before + pack.brasas);
	const status = (await call(accounts, `/pay/order?id=${order}`, { token })).data;
	assert.equal(status.order.credited, true);
	assert.equal(status.profile.brasas, before + pack.brasas);
});

test('bad signatures, wrong amounts and other accounts never get Brasas', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts } = service();
	const token = await register(accounts, 'Vitima');
	const other = await register(accounts, 'Curioso');
	const before = (await call(accounts, '/me', { token })).data.profile.brasas;
	const { order } = (await call(accounts, '/pay/checkout', { token, body: { pack: pack.id } })).data;
	payments.set('222', { id: 222, status: 'approved', external_reference: order, transaction_amount: 0.01, currency_id: 'BRL' });
	assert.equal((await webhook(accounts, '222', signed('222', 'chave-errada'))).status, 401);
	assert.equal((await webhook(accounts, '222', {})).status, 401);
	await webhook(accounts, '222');
	assert.equal((await call(accounts, '/me', { token })).data.profile.brasas, before, 'valor divergente não credita');
	assert.equal((await call(accounts, `/pay/order?id=${order}`, { token: other })).status, 404);
});

test('a refund after the credit takes the Brasas back once', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts } = service();
	const token = await register(accounts, 'Arrependido');
	const before = (await call(accounts, '/me', { token })).data.profile.brasas;
	const { order } = (await call(accounts, '/pay/checkout', { token, body: { pack: pack.id } })).data;
	payments.set('333', { id: 333, status: 'approved', external_reference: order, transaction_amount: pack.preco_centavos / 100, currency_id: 'BRL' });
	await webhook(accounts, '333');
	payments.get('333').status = 'refunded';
	await webhook(accounts, '333');
	await webhook(accounts, '333');
	assert.equal((await call(accounts, '/me', { token })).data.profile.brasas, before);
});

test('signature check follows the Mercado Pago manifest and CORS only opens to the site', async () => {
	const h = signed('999');
	assert.equal(await validSignature({ signature: h['x-signature'], requestId: h['x-request-id'], dataId: '999', secret: SECRET }), true);
	assert.equal(await validSignature({ signature: h['x-signature'], requestId: h['x-request-id'], dataId: '998', secret: SECRET }), false);
	const site = new Request('https://w/godot/login', { headers: { Origin: 'https://jaime66fla-crypto.github.io' } });
	assert.equal(corsHeaders(site)['Access-Control-Allow-Origin'], 'https://jaime66fla-crypto.github.io');
	assert.equal(corsHeaders(new Request('https://w/godot/login', { headers: { Origin: 'https://malicioso.example' } })), null);
});
