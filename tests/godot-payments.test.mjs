// Compra de Brasas por PIX no site (src/godot-payments.js) com o Mercado Pago simulado.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';

const { GodotAccounts } = await import('../src/godot-accounts.js');
const { validSignature, corsHeaders } = await import('../src/godot-payments.js');
const store = JSON.parse(readFileSync(new URL('../godot/data/store.json', import.meta.url), 'utf8'));
const SECRET = 'segredo-de-teste';
const EMAIL = 'jogador@exemplo.com';
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

/** Mercado Pago falso: cria PIX (id 900, pendente) e responde pagamentos de `payments`. */
function fakeMp(payments = new Map()) {
	const calls = [];
	globalThis.fetch = async (url, init = {}) => {
		calls.push({ url: String(url), init });
		if (String(url).endsWith('/v1/payments') && init.method === 'POST') {
			const sent = JSON.parse(init.body);
			payments.set('900', { id: 900, status: 'pending', external_reference: sent.external_reference, transaction_amount: sent.transaction_amount, currency_id: 'BRL' });
			return Response.json({ id: 900, status: 'pending', point_of_interaction: { transaction_data: { qr_code: '00020126pix-copia-e-cola', qr_code_base64: 'iVBORw0KGgo=' } } });
		}
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

const pix = (accounts, token, body = {}) => call(accounts, '/pay/pix', { token, body: { pack: pack.id, email: EMAIL, ...body } });
const brasas = async (accounts, token) => (await call(accounts, '/me', { token })).data.profile.brasas;

function signed(dataId, secret = SECRET) {
	const ts = '1764150000';
	const requestId = 'req-' + dataId;
	const v1 = createHmac('sha256', secret).update(`id:${dataId};request-id:${requestId};ts:${ts};`).digest('hex');
	return { 'x-signature': `ts=${ts},v1=${v1}`, 'x-request-id': requestId };
}

const webhook = (accounts, id, headers = signed(id)) => call(accounts, `/pay/webhook?data.id=${id}&type=payment`, { body: { type: 'payment', data: { id } }, headers });

test('pix creates the order with the server price and returns the QR code', async () => {
	const calls = fakeMp();
	const { accounts, data } = service();
	const token = await register(accounts, 'Comprador');
	const r = await pix(accounts, token, { preco_centavos: 1 });
	assert.equal(r.status, 200);
	assert.equal(r.data.qr, '00020126pix-copia-e-cola');
	assert.ok(r.data.qrImage);
	const sent = JSON.parse(calls[0].init.body);
	assert.equal(sent.payment_method_id, 'pix');
	assert.equal(sent.transaction_amount, pack.preco_centavos / 100, 'preço vem do store.json, não do navegador');
	assert.equal(sent.payer.email, EMAIL);
	assert.equal(sent.external_reference, r.data.order);
	assert.equal(sent.notification_url, 'https://worker.test/godot/pay/webhook');
	assert.match(sent.date_of_expiration, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}-03:00$/);
	assert.equal(calls[0].init.headers.Authorization, 'Bearer token-de-teste');
	assert.equal(data.get('order:' + r.data.order).payment, '900');
});

test('pix refuses bad e-mails, unknown packs, missing sessions and an unconfigured token', async () => {
	fakeMp();
	const { accounts } = service();
	const token = await register(accounts, 'Alguem');
	assert.equal((await pix(accounts, token, { email: 'sem-arroba' })).status, 400);
	assert.equal((await pix(accounts, token, { pack: 'brasas_999999' })).status, 404);
	assert.equal((await pix(accounts, '')).status, 401);
	const off = service({});
	const t2 = await register(off.accounts, 'SemChave');
	assert.equal((await pix(off.accounts, t2)).status, 503);
});

test('an approved PIX credits the Brasas once, even if the webhook repeats', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts } = service();
	const token = await register(accounts, 'Pagador');
	const before = await brasas(accounts, token);
	const { order } = (await pix(accounts, token)).data;
	assert.equal((await webhook(accounts, '900')).status, 200);
	assert.equal(await brasas(accounts, token), before, 'PIX pendente não credita');
	payments.get('900').status = 'approved';
	await webhook(accounts, '900');
	await webhook(accounts, '900');
	assert.equal(await brasas(accounts, token), before + pack.brasas);
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
	const before = await brasas(accounts, token);
	const { order } = (await pix(accounts, token)).data;
	payments.set('222', { id: 222, status: 'approved', external_reference: order, transaction_amount: 0.01, currency_id: 'BRL' });
	assert.equal((await webhook(accounts, '222', signed('222', 'chave-errada'))).status, 401);
	assert.equal((await webhook(accounts, '222', {})).status, 401);
	await webhook(accounts, '222');
	assert.equal(await brasas(accounts, token), before, 'valor divergente não credita');
	assert.equal((await call(accounts, `/pay/order?id=${order}`, { token: other })).status, 404);
});

test('a refund after the credit takes the Brasas back once', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts } = service();
	const token = await register(accounts, 'Arrependido');
	const before = await brasas(accounts, token);
	await pix(accounts, token);
	payments.get('900').status = 'approved';
	await webhook(accounts, '900');
	payments.get('900').status = 'refunded';
	await webhook(accounts, '900');
	await webhook(accounts, '900');
	assert.equal(await brasas(accounts, token), before);
});

test('unsigned legacy IPN is acknowledged but never credits', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts } = service();
	const token = await register(accounts, 'Ipn');
	const before = await brasas(accounts, token);
	await pix(accounts, token);
	payments.get('900').status = 'approved';
	const r = await call(accounts, '/pay/webhook?id=900&topic=payment', { body: { resource: '900', topic: 'payment' } });
	assert.equal(r.status, 200);
	assert.equal(await brasas(accounts, token), before);
});

test('history lists only the account own purchases, newest first, with a friendly status', async () => {
	const payments = new Map();
	fakeMp(payments);
	const { accounts, data } = service();
	const token = await register(accounts, 'Historico');
	const other = await register(accounts, 'Outro');
	const first = (await pix(accounts, token)).data.order;
	payments.get('900').status = 'approved';
	await webhook(accounts, '900');
	data.get('acct:historico').lastCheckout = 0;
	const second = (await pix(accounts, token, { pack: store.pacotes[0].id })).data.order;
	const h = (await call(accounts, '/pay/history', { token })).data;
	assert.deepEqual(h.orders.map((o) => o.id).sort(), [first, second].sort());
	assert.equal(h.orders.find((o) => o.id === first).status, 'pago');
	assert.equal(h.orders.find((o) => o.id === second).status, 'aguardando');
	assert.ok(h.orders[0].at >= h.orders[1].at);
	assert.deepEqual((await call(accounts, '/pay/history', { token: other })).data.orders, []);
	assert.equal((await call(accounts, '/pay/history')).status, 401);
});

test('signature check follows the Mercado Pago manifest and CORS only opens to the site', async () => {
	const h = signed('999');
	assert.equal(await validSignature({ signature: h['x-signature'], requestId: h['x-request-id'], dataId: '999', secret: SECRET }), true);
	assert.equal(await validSignature({ signature: h['x-signature'], requestId: h['x-request-id'], dataId: '998', secret: SECRET }), false);
	const site = new Request('https://w/godot/login', { headers: { Origin: 'https://jaime66fla-crypto.github.io' } });
	assert.equal(corsHeaders(site)['Access-Control-Allow-Origin'], 'https://jaime66fla-crypto.github.io');
	assert.equal(corsHeaders(new Request('https://w/godot/login', { headers: { Origin: 'https://malicioso.example' } })), null);
});
