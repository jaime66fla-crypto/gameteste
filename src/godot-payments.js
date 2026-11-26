// Compra de Brasas com dinheiro real (Mercado Pago Checkout Pro), vendida no site
// do GitHub Pages (loja.html). Os métodos entram no Durable Object de contas
// (installPayments) para que crédito e pedido sejam gravados juntos.
//
// Fluxo: POST /godot/pay/checkout {pack} (com sessão) cria o pedido e a
// preferência no Mercado Pago e devolve a URL de pagamento. O Mercado Pago avisa
// em POST /godot/pay/webhook; só depois de validar a assinatura e consultar o
// pagamento na API é que as Brasas são creditadas, uma vez por pedido.
// Segredos do Worker: MP_ACCESS_TOKEN e MP_WEBHOOK_SECRET (wrangler secret put).
import store from '../godot/data/store.json' with { type: 'json' };

export const SHOP_URL = 'https://jaime66fla-crypto.github.io/gameteste/loja.html';
/** Origens que podem chamar login/pagamento pelo navegador (site + teste local). */
export const SHOP_ORIGINS = ['https://jaime66fla-crypto.github.io', 'http://localhost:8765'];
/** Rotas abertas para o site (CORS). O webhook não precisa: quem chama é o Mercado Pago. */
export const SHOP_PATHS = ['/godot/login', '/godot/me', '/godot/pay/checkout', '/godot/pay/order'];

const MP_API = 'https://api.mercadopago.com';
const PACKS = new Map((store.pacotes || []).map((pack) => [pack.id, pack]));
const CHECKOUT_COOLDOWN_MS = 3000;
const ORDER_RULE = /^[0-9a-f]{24}$/;

/** Cabeçalhos CORS para a origem do site (ou nada, se a origem não é a do site). */
export function corsHeaders(request) {
	const origin = request.headers.get('Origin') || '';
	if (!SHOP_ORIGINS.includes(origin)) return null;
	return {
		'Access-Control-Allow-Origin': origin,
		'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
		'Access-Control-Allow-Headers': 'Content-Type, Authorization',
		'Access-Control-Max-Age': '86400',
		Vary: 'Origin',
	};
}

/** Resposta do preflight (OPTIONS) das rotas do site. */
export function preflight(request) {
	const headers = corsHeaders(request);
	return new Response(null, { status: headers ? 204 : 403, headers: headers || {} });
}

/** Copia a resposta acrescentando o CORS do site. */
export function withCors(request, response) {
	const extra = corsHeaders(request);
	if (!extra) return response;
	const out = new Response(response.body, response);
	for (const [key, value] of Object.entries(extra)) out.headers.set(key, value);
	return out;
}

/** x-signature "ts=...,v1=..." → {ts, v1}. */
function parseSignature(header) {
	const out = {};
	for (const part of String(header || '').split(',')) {
		const [key, value] = part.split('=');
		if (key && value) out[key.trim()] = value.trim();
	}
	return out;
}

async function hmacHex(secret, message) {
	const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
	const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
	return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function sameText(a, b) {
	if (a.length !== b.length) return false;
	let diff = 0;
	for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
	return diff === 0;
}

/**
 * Valida a assinatura do Mercado Pago: HMAC-SHA256(segredo,
 * "id:<data.id>;request-id:<x-request-id>;ts:<ts>;"), partes ausentes omitidas.
 */
export async function validSignature({ signature, requestId, dataId, secret }) {
	const { ts, v1 } = parseSignature(signature);
	if (!secret || !ts || !v1) return false;
	let manifest = '';
	if (dataId) manifest += `id:${String(dataId).toLowerCase()};`;
	if (requestId) manifest += `request-id:${requestId};`;
	manifest += `ts:${ts};`;
	return sameText(await hmacHex(secret, manifest), v1.toLowerCase());
}

const brl = (cents) => (cents / 100).toFixed(2).replace('.', ',');

/** Junta os métodos de pagamento ao Durable Object de contas. */
export function installPayments(Accounts, { json, profile, brasasOf, randomHex }) {
	const proto = Accounts.prototype;

	proto.payRoute = async function (request, url, token) {
		switch (url.pathname) {
			case '/pay/checkout':
				return request.method === 'POST' ? this.payCheckout(token, await request.json(), request) : json({ error: 'Método não permitido.' }, 405);
			case '/pay/order':
				return this.payOrder(token, url);
			case '/pay/webhook':
				return request.method === 'POST' ? this.payWebhook(request, url) : json({ ok: true });
		}
		return json({ error: 'Rota não encontrada.' }, 404);
	};

	proto.mp = async function (path, init = {}) {
		return fetch(MP_API + path, {
			...init,
			headers: { Authorization: 'Bearer ' + this.env.MP_ACCESS_TOKEN, 'Content-Type': 'application/json', ...(init.headers || {}) },
		});
	};

	/** POST /pay/checkout {pack}: cria o pedido e devolve a URL do Checkout Pro. */
	proto.payCheckout = async function (token, body, request) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const pack = PACKS.get(String(body?.pack || ''));
		if (!pack) return json({ error: 'Pacote não encontrado.' }, 404);
		if (!this.env?.MP_ACCESS_TOKEN) return json({ error: 'A compra de Brasas ainda não está disponível.' }, 503);
		const { key, account } = found;
		if (Date.now() - (account.lastCheckout || 0) < CHECKOUT_COOLDOWN_MS) return json({ error: 'Aguarde um instante e tente de novo.' }, 429);
		account.lastCheckout = Date.now();
		const id = randomHex(12);
		const order = { id, account: key, name: account.name, pack: pack.id, brasas: pack.brasas, cents: pack.preco_centavos, status: 'criado', at: Date.now() };
		await this.ctx.storage.put({ [key]: account, ['order:' + id]: order });
		const origin = request.headers.get('x-public-origin') || 'https://floral-haze-1c57.jaime66fla.workers.dev';
		const back = `${SHOP_URL}?pedido=${id}`;
		const response = await this.mp('/checkout/preferences', {
			method: 'POST',
			headers: { 'X-Idempotency-Key': id },
			body: JSON.stringify({
				items: [{ id: pack.id, title: `${pack.brasas} Brasas · Campo de Fogo`, description: `Pacote de ${pack.brasas} Brasas para a conta ${account.name}`, quantity: 1, unit_price: pack.preco_centavos / 100, currency_id: 'BRL' }],
				external_reference: id,
				notification_url: `${origin}/godot/pay/webhook`,
				back_urls: { success: back, failure: back, pending: back },
				auto_return: 'approved',
				statement_descriptor: 'CAMPO DE FOGO',
			}),
		});
		if (!response.ok) {
			order.status = 'erro';
			await this.ctx.storage.put('order:' + id, order);
			return json({ error: 'Não foi possível abrir o pagamento. Tente de novo.' }, 502);
		}
		const pref = await response.json();
		order.preference = pref.id;
		await this.ctx.storage.put('order:' + id, order);
		return json({ order: id, url: pref.init_point, price: brl(pack.preco_centavos) });
	};

	/** GET /pay/order?id=: situação do pedido (só o dono vê). */
	proto.payOrder = async function (token, url) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const id = String(url.searchParams.get('id') || '');
		const order = ORDER_RULE.test(id) ? await this.ctx.storage.get('order:' + id) : null;
		if (!order || order.account !== found.key) return json({ error: 'Pedido não encontrado.' }, 404);
		return json({ order: { id, pack: order.pack, brasas: order.brasas, status: order.status, credited: !!order.credited }, profile: profile(found.account) });
	};

	/**
	 * POST /pay/webhook?data.id=&type=payment (Mercado Pago). Assinatura inválida
	 * → 401. Erro ao consultar o pagamento → 502 (o Mercado Pago tenta de novo).
	 */
	proto.payWebhook = async function (request, url) {
		let body = {};
		try {
			body = await request.json();
		} catch {}
		const type = url.searchParams.get('type') || url.searchParams.get('topic') || body?.type || '';
		const dataId = url.searchParams.get('data.id') || body?.data?.id || '';
		if (type !== 'payment') return json({ ok: true, ignored: type || 'sem tipo' });
		if (!/^\d{1,20}$/.test(String(dataId))) return json({ error: 'Pagamento inválido.' }, 400);
		const ok = await validSignature({ signature: request.headers.get('x-signature'), requestId: request.headers.get('x-request-id'), dataId, secret: this.env?.MP_WEBHOOK_SECRET });
		if (!ok) return json({ error: 'Assinatura inválida.' }, 401);
		const response = await this.mp('/v1/payments/' + dataId);
		if (!response.ok) return json({ error: 'Falha ao consultar o pagamento.' }, 502);
		return this.applyPayment(await response.json());
	};

	/** Aplica a situação do pagamento ao pedido: credita na aprovação, estorna no reembolso. */
	proto.applyPayment = async function (payment) {
		const id = String(payment?.external_reference || '');
		const order = ORDER_RULE.test(id) ? await this.ctx.storage.get('order:' + id) : null;
		if (!order) return json({ ok: true, ignored: 'pedido desconhecido' });
		const paymentId = String(payment.id);
		if (order.payment && order.payment !== paymentId && order.credited) return json({ ok: true, ignored: 'pedido já pago por outro pagamento' });
		const account = await this.ctx.storage.get(order.account);
		if (!account) return json({ ok: true, ignored: 'conta removida' });
		const amountOk = Math.round(Number(payment.transaction_amount) * 100) === order.cents && payment.currency_id === 'BRL';
		const status = String(payment.status || '');
		order.status = status;
		order.updated = Date.now();
		if (status === 'approved' && !order.credited) {
			if (!amountOk) {
				order.status = 'valor_divergente';
				await this.ctx.storage.put('order:' + id, order);
				return json({ ok: true, ignored: 'valor divergente' });
			}
			order.credited = true;
			order.payment = paymentId;
			account.brasas = brasasOf(account) + order.brasas;
			account.brasasBought = [...(account.brasasBought || []), { order: id, pack: order.pack, brasas: order.brasas, cents: order.cents, payment: paymentId, at: Date.now() }].slice(-50);
		} else if ((status === 'refunded' || status === 'charged_back') && order.credited && !order.reversed && order.payment === paymentId) {
			order.reversed = true;
			account.brasas = brasasOf(account) - order.brasas; // pode ficar negativo: gastou e pediu o dinheiro de volta
		}
		await this.ctx.storage.put({ ['order:' + id]: order, [order.account]: account });
		return json({ ok: true, status: order.status, credited: !!order.credited });
	};
}
