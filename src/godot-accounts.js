// Player accounts for the Godot build: register / login, sessions, XP and rank.
// One Durable Object instance ("godot-accounts") owns every account so names
// stay unique. Passwords are stored only as salted PBKDF2-SHA256 hashes.
import ranks from '../godot/data/ranks.json' with { type: 'json' };
import store from '../godot/data/store.json' with { type: 'json' };
import { installChat } from './godot-chat.js';
import { installPayments } from './godot-payments.js';

// Loja interna (godot/data/store.json): Brasas ficam na conta; só o servidor
// soma (XP de partida/sobrevivência) e desconta (compra). Itens de preço 0 são
// de todo mundo e não entram em "owned".
const STORE_ITEMS = new Map(store.items.map((item) => [item.id, item]));
const HISTORY_SIZE = 50;

// Conta do dono do jogo (Jaimexzz.dev): tem todos os itens pagos da loja sem
// comprar (inclusive os que entrarem depois). Vale pela chave da conta (nome do
// cadastro) ou pelo nome atual, sem diferenciar maiúsculas.
const MASTER_ACCOUNTS = new Set(['acct:jaimexzz.dev']);
const MASTER_NAMES = new Set(['jaimexzz.dev']);
const PAID_ITEMS = store.items.filter((item) => item.preco > 0).map((item) => item.id);

/** Conta master: soma todos os itens pagos ao "owned" (sem tirar nada do que já tinha). */
export function withMaster(key, account) {
	if (account && (MASTER_ACCOUNTS.has(key) || MASTER_NAMES.has(String(account.name || '').toLowerCase()))) account.owned = [...new Set([...(account.owned || []), ...PAID_ITEMS])];
	return account;
}

/** Saldo atual (contas antigas começam com o bônus inicial). */
const brasasOf = (account) => (Number.isFinite(account.brasas) ? account.brasas : store.start);

/**
 * Personagem que os outros podem ver: um personagem pago da loja só vale se a
 * conta comprou (senão '' e os outros veem o padrão). owned = itens da conta.
 */
export function allowedCharacter(ch, owned) {
	const item = STORE_ITEMS.get(ch);
	if (!item || item.grupo !== 'personagens' || item.preco <= 0) return ch;
	return Array.isArray(owned) && owned.includes(ch) ? ch : '';
}

/**
 * Roupas e skin de arma que os outros podem ver, a partir do estado do cliente:
 * rp = roupas do 01 (grátis ou compradas, uma por peça, no máximo 4) e
 * ws = skin comprada da arma que está na mão. Cliente antigo (sem "rp") não
 * manda rp, e os outros continuam vendo a roupa padrão.
 */
export function allowedCosmetics(d, weapon, owned) {
	const mine = (item) => item.preco <= 0 || (Array.isArray(owned) && owned.includes(item.id));
	const out = {};
	if (Array.isArray(d?.rp)) {
		const pieces = new Set();
		out.rp = [];
		for (const id of d.rp.slice(0, 4)) {
			const item = STORE_ITEMS.get(id);
			if (!item || item.grupo !== 'skins_personagens' || !mine(item) || pieces.has(item.peca)) continue;
			pieces.add(item.peca);
			out.rp.push(id);
		}
	}
	const skin = STORE_ITEMS.get(d?.ws);
	out.ws = skin && skin.grupo === 'skins_armas' && skin.arma === weapon && mine(skin) ? skin.id : '';
	return out;
}

/** Itens da conta na URL interna de entrada numa sala (&own=a,b,c). */
export const ownedQuery = (session) => '&own=' + encodeURIComponent((session.owned || []).join(','));
export const ownedFrom = (url) => (url.searchParams.get('own') || '').split(',').filter((id) => STORE_ITEMS.has(id));

const SESSION_DAYS = 90;
const PBKDF2_ITERATIONS = 100000;
const MAX_FAILURES = 8; // wrong passwords before a temporary lock
const LOCK_MS = 5 * 60 * 1000;
const NAME_RULE = /^[\p{L}\p{N}._-]{3,16}$/u;

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
	});
}

const hex = (bytes) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');
const randomHex = (n) => hex(crypto.getRandomValues(new Uint8Array(n)));

async function hashPassword(password, saltHex) {
	const salt = new Uint8Array(saltHex.match(/../g).map((h) => parseInt(h, 16)));
	const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
	const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ITERATIONS }, key, 256);
	return hex(bits);
}

function sameHash(a, b) {
	if (a.length !== b.length) return false;
	let diff = 0;
	for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
	return diff === 0;
}

/** Rank for an XP total, with progress to the next one. */
export function rankFor(xp) {
	let index = 0;
	for (let i = 0; i < ranks.ranks.length; i++) if (xp >= ranks.ranks[i].xp) index = i;
	const next = ranks.ranks[index + 1];
	return { rank: ranks.ranks[index].name, rankIndex: index, rankXp: ranks.ranks[index].xp, nextRank: next ? next.name : null, nextRankXp: next ? next.xp : null };
}

export const XP_REWARDS = ranks.xp;

function profile(account) {
	return {
		name: account.name,
		avatar: account.avatar || 0, // versão da foto (0 = sem foto: iniciais)
		renamedAt: account.renamedAt || 0,
		xp: account.xp,
		...rankFor(account.xp),
		kills: account.kills,
		botKills: account.botKills,
		wins: account.wins,
		matches: account.matches,
		brasas: brasasOf(account), // só o dono vê o perfil completo (amigos e ranking usam outros campos)
		owned: account.owned || [],
	};
}

const BOARD_KEY = 'board';
const BOARD_SIZE = 100; // players kept in the stored leaderboard
const BOARD_MAX_LIMIT = 50; // most rows one request can return

function boardEntry(key, account) {
	return { key, name: account.name, avatar: account.avatar || 0, xp: account.xp || 0, kills: account.kills || 0, wins: account.wins || 0, matches: account.matches || 0 };
}

/** XP first, then wins, then kills, then name. */
function sortBoard(entries) {
	return entries.sort((a, b) => b.xp - a.xp || b.wins - a.wins || b.kills - a.kills || a.name.localeCompare(b.name));
}

function bearer(request, url) {
	const header = request.headers.get('Authorization') || '';
	if (header.startsWith('Bearer ')) return header.slice(7).trim();
	return url.searchParams.get('token') || '';
}

/**
 * Public routes: POST /godot/register, POST /godot/login, GET /godot/me and the
 * friends API under /godot/friends (list + presence, add, accept, decline,
 * remove, invite).
 */
export async function handleGodotAccount(request, env, url) {
	const accounts = env.GODOT_ACCOUNTS.get(env.GODOT_ACCOUNTS.idFromName('godot-accounts'));
	const route = url.pathname.slice('/godot'.length); // /register, /login, /me, /friends...
	const headers = { 'content-type': 'application/json' };
	const token = bearer(request, url);
	if (token) headers.Authorization = 'Bearer ' + token;
	// Webhook do Mercado Pago: a assinatura vem nos cabeçalhos (src/godot-payments.js).
	for (const name of ['x-signature', 'x-request-id']) if (request.headers.get(name)) headers[name] = request.headers.get(name);
	headers['x-public-origin'] = url.origin;
	const body = request.method === 'POST' ? await request.text() : undefined;
	return accounts.fetch(new Request('https://internal' + route + url.search, { method: request.method, headers, body }));
}

const MAX_FRIENDS = 100;
const RENAME_COOLDOWN_MS = 24 * 3600 * 1000; // trocar de nick no máximo 1 vez por dia
const AVATAR_MAX_BYTES = 60 * 1024; // foto já reduzida pelo jogo (128×128 JPEG fica bem abaixo)
const ONLINE_MS = 25000; // a client polls every ~8 s while the game is open
const INVITE_MS = 120000;

/**
 * GET /godot/chat (WebSocket): chat do menu, global e com amigos (src/godot-chat.js).
 * O pedido vai inteiro para o Durable Object de contas (o Upgrade passa junto).
 */
export async function handleGodotChat(request, env, url) {
	const accounts = env.GODOT_ACCOUNTS.get(env.GODOT_ACCOUNTS.idFromName('godot-accounts'));
	const headers = new Headers(request.headers);
	const token = bearer(request, url);
	if (token) headers.set('Authorization', 'Bearer ' + token);
	return accounts.fetch(new Request('https://internal/chat', { headers }));
}

/** Resolve a session token to {account, name, xp} (used by the match socket route). */
export async function resolveSession(env, token) {
	if (!token) return null;
	const accounts = env.GODOT_ACCOUNTS.get(env.GODOT_ACCOUNTS.idFromName('godot-accounts'));
	const response = await accounts.fetch(new Request('https://internal/internal/session', { headers: { Authorization: 'Bearer ' + token } }));
	return response.ok ? response.json() : null;
}

export class GodotAccounts {
	constructor(ctx, env) {
		this.ctx = ctx;
		this.env = env;
		// Presence and invites are short-lived: kept in memory, refreshed by polling.
		this.presence = new Map(); // account key -> {seen, status, code}
		this.invites = new Map(); // account key -> [{from, code, at}]
	}

	async fetch(request) {
		const url = new URL(request.url);
		try {
			if (url.pathname.startsWith('/pay/')) return await this.payRoute(request, url, bearer(request, url));
			switch (url.pathname) {
				case '/register':
					return request.method === 'POST' ? this.register(await request.json()) : json({ error: 'Método não permitido.' }, 405);
				case '/login':
					return request.method === 'POST' ? this.login(await request.json()) : json({ error: 'Método não permitido.' }, 405);
				case '/me':
					return this.me(bearer(request, url));
				case '/leaderboard':
					return this.leaderboard(bearer(request, url), url);
				case '/internal/session':
					return this.session(bearer(request, url));
				case '/internal/xp':
					return this.addXp(await request.json());
				case '/friends':
					return this.friends(bearer(request, url), url);
				case '/chat':
					return this.chatConnect(request, bearer(request, url));
				case '/profile/name':
					return request.method === 'POST' ? this.rename(bearer(request, url), await request.json()) : json({ error: 'Método não permitido.' }, 405);
				case '/profile/avatar':
					return request.method === 'POST' ? this.setAvatar(bearer(request, url), await request.json()) : json({ error: 'Método não permitido.' }, 405);
				case '/avatar':
					return this.avatar(url);
				case '/store/buy':
					return request.method === 'POST' ? this.buy(bearer(request, url), await request.json()) : json({ error: 'Método não permitido.' }, 405);
				case '/friends/add':
				case '/friends/accept':
				case '/friends/decline':
				case '/friends/remove':
				case '/friends/invite':
					if (request.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);
					return this.friendAction(bearer(request, url), url.pathname.slice('/friends/'.length), await request.json());
			}
		} catch {
			return json({ error: 'Pedido inválido.' }, 400);
		}
		return json({ error: 'Rota não encontrada.' }, 404);
	}

	key(name) {
		return 'acct:' + String(name).toLowerCase();
	}

	/**
	 * Conta pelo nick atual. A chave da conta nunca muda (amigos, sessões,
	 * ranking e personagens apontam para ela); quem trocou de nick ganha um
	 * apelido "name:<nick>" → chave. O nick original continua reservado.
	 */
	async keyForName(name) {
		const lower = String(name).toLowerCase();
		return (await this.ctx.storage.get('name:' + lower)) || 'acct:' + lower;
	}

	/** Nick em uso por outra conta (nick atual de alguém ou nick original reservado). */
	async nameTaken(name, exceptKey = '') {
		const lower = String(name).toLowerCase();
		const alias = await this.ctx.storage.get('name:' + lower);
		if (alias && alias !== exceptKey) return true;
		const direct = 'acct:' + lower;
		return direct !== exceptKey && !!(await this.ctx.storage.get(direct));
	}

	/** POST /profile/name {name}: troca o nick (1 vez por dia, único). */
	async rename(token, body) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const { key, account } = found;
		const name = String(body?.name || '').trim();
		if (!NAME_RULE.test(name)) return json({ error: 'O nick deve ter de 3 a 16 letras, números, ponto, traço ou sublinhado.' }, 400);
		if (name === account.name) return json({ profile: profile(account), message: 'Esse já é o seu nick.' });
		const wait = (account.renamedAt || 0) + RENAME_COOLDOWN_MS - Date.now();
		if (wait > 0) return json({ error: `Você já trocou de nick hoje. Tente de novo em ${Math.ceil(wait / 3600000)} h.` }, 429);
		const oldLower = account.name.toLowerCase();
		const newLower = name.toLowerCase();
		if (newLower !== oldLower && (await this.nameTaken(name, key))) return json({ error: 'Esse nick já está em uso.' }, 409);
		if ('acct:' + oldLower !== key && (await this.ctx.storage.get('name:' + oldLower)) === key) await this.ctx.storage.delete('name:' + oldLower);
		if ('acct:' + newLower !== key) await this.ctx.storage.put('name:' + newLower, key);
		account.name = name;
		account.renamedAt = Date.now();
		await this.ctx.storage.put(key, account);
		await this.updateBoard(key, account);
		return json({ profile: profile(account), message: `Agora você é ${name}.` });
	}

	/** POST /profile/avatar {image: base64 JPEG/PNG} troca a foto; image vazia remove. */
	async setAvatar(token, body) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const { key, account } = found;
		const data = String(body?.image || '');
		if (!data) {
			await this.ctx.storage.delete('avatar:' + key);
			account.avatar = 0;
		} else {
			let bytes;
			try {
				bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
			} catch {
				return json({ error: 'Imagem inválida.' }, 400);
			}
			const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
			const png = bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
			if (!jpeg && !png) return json({ error: 'A foto precisa ser JPG ou PNG.' }, 400);
			if (bytes.length > AVATAR_MAX_BYTES) return json({ error: 'Foto grande demais.' }, 413);
			await this.ctx.storage.put('avatar:' + key, { type: jpeg ? 'image/jpeg' : 'image/png', data });
			account.avatar = Date.now();
		}
		await this.ctx.storage.put(key, account);
		await this.updateBoard(key, account);
		return json({ profile: profile(account), message: data ? 'Foto atualizada.' : 'Foto removida.' });
	}

	/** GET /avatar?name=<nick>&v=<versão>: a foto de um jogador (cache longo: a URL muda com a versão). */
	async avatar(url) {
		const name = String(url.searchParams.get('name') || '');
		if (!NAME_RULE.test(name)) return new Response('Not found', { status: 404 });
		const stored = await this.ctx.storage.get('avatar:' + (await this.keyForName(name)));
		if (!stored) return new Response('Not found', { status: 404 });
		const bytes = Uint8Array.from(atob(stored.data), (c) => c.charCodeAt(0));
		return new Response(bytes, { headers: { 'content-type': stored.type, 'cache-control': 'public, max-age=86400' } });
	}

	async newSession(accountKey) {
		const token = randomHex(32);
		await this.ctx.storage.put('sess:' + token, { account: accountKey, expires: Date.now() + SESSION_DAYS * 86400000 });
		return token;
	}

	async register(body) {
		const name = String(body?.name || '').trim();
		const password = String(body?.password || '');
		if (!NAME_RULE.test(name)) return json({ error: 'Nome deve ter de 3 a 16 letras, números, ponto, traço ou sublinhado.' }, 400);
		if (password.length < 6 || password.length > 72) return json({ error: 'A senha precisa ter entre 6 e 72 caracteres.' }, 400);
		const key = this.key(name);
		if (await this.nameTaken(name)) return json({ error: 'Esse nome já está em uso.' }, 409);
		const salt = randomHex(16);
		const account = { name, salt, hash: await hashPassword(password, salt), xp: 0, kills: 0, botKills: 0, wins: 0, matches: 0, created: Date.now(), failures: 0, lockedUntil: 0 };
		await this.ctx.storage.put(key, account);
		await this.updateBoard(key, account);
		return json({ token: await this.newSession(key), profile: profile(account) }, 201);
	}

	async login(body) {
		const key = await this.keyForName(String(body?.name || '').trim()); // nick atual (ou o original)
		const password = String(body?.password || '');
		const account = await this.ctx.storage.get(key);
		const wrong = json({ error: 'Nome ou senha incorretos.' }, 401);
		if (!account) {
			await hashPassword(password, randomHex(16)); // same cost as a real check
			return wrong;
		}
		if (account.lockedUntil > Date.now()) return json({ error: 'Muitas tentativas. Tente de novo em alguns minutos.' }, 429);
		if (!sameHash(await hashPassword(password, account.salt), account.hash)) {
			account.failures = (account.failures || 0) + 1;
			if (account.failures >= MAX_FAILURES) {
				account.failures = 0;
				account.lockedUntil = Date.now() + LOCK_MS;
			}
			await this.ctx.storage.put(key, account);
			return wrong;
		}
		account.failures = 0;
		account.lockedUntil = 0;
		withMaster(key, account);
		await this.ctx.storage.put(key, account);
		return json({ token: await this.newSession(key), profile: profile(account) });
	}

	async accountFor(token) {
		if (!/^[0-9a-f]{64}$/.test(token)) return null;
		const session = await this.ctx.storage.get('sess:' + token);
		if (!session) return null;
		if (session.expires < Date.now()) {
			await this.ctx.storage.delete('sess:' + token);
			return null;
		}
		const account = withMaster(session.account, await this.ctx.storage.get(session.account));
		return account ? { key: session.account, account } : null;
	}

	async me(token) {
		const found = await this.accountFor(token);
		return found ? json({ profile: profile(found.account) }) : json({ error: 'Sessão expirada. Entre de novo.' }, 401);
	}

	async session(token) {
		const found = await this.accountFor(token);
		return found ? json({ account: found.key, name: found.account.name, xp: found.account.xp, owned: found.account.owned || [] }) : json({ error: 'invalid' }, 401);
	}

	// ------------------------------------------------------------ friends ---

	/**
	 * GET /friends?status=menu|room|match&code=XXXXX — records the caller's
	 * presence and returns friends (with online status), pending requests and
	 * room invites (each invite is delivered once).
	 */
	async friends(token, url) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const status = ['menu', 'room', 'match'].includes(url.searchParams.get('status')) ? url.searchParams.get('status') : 'menu';
		// Sala personalizada (5 letras/números) ou sala de espera de eliminatória (6 hex).
		const raw = url.searchParams.get('code') || '';
		const code = /^[A-Z0-9]{5}$/.test(raw) || /^[0-9a-f]{6}$/.test(raw) ? raw : '';
		const now = Date.now();
		this.presence.set(found.key, { seen: now, status, code: status === 'room' ? code : '' });
		const friends = [];
		for (const key of found.account.friends || []) {
			const friend = await this.ctx.storage.get(key);
			if (!friend) continue;
			const seen = this.presence.get(key);
			const online = !!seen && now - seen.seen < ONLINE_MS;
			friends.push({ name: friend.name, avatar: friend.avatar || 0, rank: rankFor(friend.xp).rank, online, status: online ? seen.status : 'offline', code: online ? seen.code : '' });
		}
		friends.sort((a, b) => Number(b.online) - Number(a.online) || a.name.localeCompare(b.name));
		const requests = [];
		for (const key of found.account.requests || []) {
			const other = await this.ctx.storage.get(key);
			if (other) requests.push(other.name);
		}
		const invites = (this.invites.get(found.key) || []).filter((invite) => now - invite.at < INVITE_MS);
		this.invites.delete(found.key);
		return json({ friends, requests, invites: invites.map(({ from, code, kind }) => ({ from, code, kind: kind || 'party' })) });
	}

	/** POST /friends/<add|accept|decline|remove|invite> with {name} (and {code} for invite). */
	async friendAction(token, action, body) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const me = found.account;
		const meKey = found.key;
		const name = String(body?.name || '').trim();
		if (!NAME_RULE.test(name)) return json({ error: 'Nome inválido.' }, 400);
		const otherKey = await this.keyForName(name);
		if (otherKey === meKey) return json({ error: 'Esse é você.' }, 400);
		const other = await this.ctx.storage.get(otherKey);
		if (!other) return json({ error: `Jogador ${name} não encontrado.` }, 404);
		me.friends = me.friends || [];
		me.requests = me.requests || [];
		other.friends = other.friends || [];
		other.requests = other.requests || [];
		const drop = (list, key) => list.filter((k) => k !== key);
		const save = async () => this.ctx.storage.put({ [meKey]: me, [otherKey]: other });
		switch (action) {
			case 'add': {
				if (me.friends.includes(otherKey)) return json({ message: `${other.name} já é seu amigo.` });
				if (me.friends.length >= MAX_FRIENDS) return json({ error: `Limite de ${MAX_FRIENDS} amigos.` }, 400);
				if (me.requests.includes(otherKey)) {
					// They already asked: accept right away.
					me.requests = drop(me.requests, otherKey);
					me.friends.push(otherKey);
					if (!other.friends.includes(meKey)) other.friends.push(meKey);
					await save();
					return json({ message: `Agora você e ${other.name} são amigos.` });
				}
				if (!other.requests.includes(meKey)) other.requests.push(meKey);
				await save();
				return json({ message: `Pedido de amizade enviado para ${other.name}.` });
			}
			case 'accept': {
				if (!me.requests.includes(otherKey)) return json({ error: 'Não há pedido desse jogador.' }, 400);
				me.requests = drop(me.requests, otherKey);
				if (!me.friends.includes(otherKey)) me.friends.push(otherKey);
				if (!other.friends.includes(meKey)) other.friends.push(meKey);
				other.requests = drop(other.requests, meKey);
				await save();
				return json({ message: `Agora você e ${other.name} são amigos.` });
			}
			case 'decline': {
				me.requests = drop(me.requests, otherKey);
				await save();
				return json({ message: 'Pedido recusado.' });
			}
			case 'remove': {
				me.friends = drop(me.friends, otherKey);
				other.friends = drop(other.friends, meKey);
				await save();
				return json({ message: `${other.name} foi removido dos amigos.` });
			}
			case 'invite': {
				// kind "party": sala personalizada (5 letras); "elim": sala de espera de eliminatória (6 hex).
				const kind = body?.kind === 'elim' ? 'elim' : 'party';
				const code = kind === 'elim' ? String(body?.code || '').toLowerCase() : String(body?.code || '').toUpperCase();
				if (!(kind === 'elim' ? /^[0-9a-f]{6}$/ : /^[A-Z0-9]{5}$/).test(code)) return json({ error: 'Entre numa sala para convidar.' }, 400);
				if (!me.friends.includes(otherKey)) return json({ error: 'Só dá para convidar amigos.' }, 400);
				const list = (this.invites.get(otherKey) || []).filter((invite) => invite.from !== me.name);
				list.push({ from: me.name, code, kind, at: Date.now() });
				this.invites.set(otherKey, list.slice(-5));
				return json({ message: `Convite enviado para ${other.name}.` });
			}
		}
		return json({ error: 'Ação desconhecida.' }, 400);
	}

	/** Called by match rooms only: add XP and stats earned in one match. */
	async addXp(body) {
		const key = String(body?.account || '');
		const account = key.startsWith('acct:') ? await this.ctx.storage.get(key) : null;
		if (!account) return json({ error: 'unknown account' }, 404);
		const before = rankFor(account.xp);
		const count = (value) => Math.max(0, Math.min(2000, Math.floor(Number(value) || 0)));
		// XP da partida pode ser negativo (morrer, sair no meio); o total nunca fica abaixo de 0.
		const delta = Math.max(-2000, Math.min(2000, Math.floor(Number(body.xp) || 0)));
		account.xp = Math.max(0, account.xp + delta);
		account.kills += count(body.kills);
		account.botKills += count(body.botKills);
		account.wins += body.win ? 1 : 0;
		account.matches += 1;
		// Brasas: 1 a cada xp_per_brasa de XP positivo; a sobra fica para a próxima partida.
		let brasasGained = 0;
		if (delta > 0) {
			const pool = (account.brasaXp || 0) + delta;
			brasasGained = Math.floor(pool / store.xp_per_brasa);
			account.brasaXp = pool % store.xp_per_brasa;
			account.brasas = brasasOf(account) + brasasGained;
		}
		await this.ctx.storage.put(key, account);
		await this.updateBoard(key, account);
		const after = rankFor(account.xp).rankIndex;
		return json({ profile: profile(account), brasasGained, rankUp: after > before.rankIndex, rankDown: after < before.rankIndex });
	}

	// --------------------------------------------------------------- store ---

	/** POST /store/buy {item}: compra um item da loja com Brasas (uma vez por conta). */
	async buy(token, body) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const { key, account } = found;
		const item = STORE_ITEMS.get(String(body?.item || ''));
		if (!item) return json({ error: 'Item não encontrado na loja.' }, 404);
		const owned = account.owned || [];
		if (item.preco <= 0 || owned.includes(item.id)) return json({ profile: profile(account), message: `${item.nome} já é seu.` });
		const balance = brasasOf(account);
		if (balance < item.preco) return json({ error: `Faltam ${item.preco - balance} ${store.currency} para ${item.nome}.` }, 402);
		account.brasas = balance - item.preco;
		account.owned = [...owned, item.id];
		account.purchases = [...(account.purchases || []), { item: item.id, price: item.preco, at: Date.now() }].slice(-HISTORY_SIZE);
		await this.ctx.storage.put(key, account);
		return json({ profile: profile(account), message: `${item.nome} comprado!` });
	}

	// --------------------------------------------------------- leaderboard ---

	/** Stored top list; built once from every account the first time it is needed. */
	async board() {
		let board = await this.ctx.storage.get(BOARD_KEY);
		if (Array.isArray(board)) return board;
		board = [];
		if (typeof this.ctx.storage.list === 'function') {
			const all = await this.ctx.storage.list({ prefix: 'acct:' });
			for (const [key, account] of all) board.push(boardEntry(key, account));
		}
		board = sortBoard(board).slice(0, BOARD_SIZE);
		await this.ctx.storage.put(BOARD_KEY, board);
		return board;
	}

	async updateBoard(key, account) {
		const board = (await this.board()).filter((entry) => entry.key !== key);
		board.push(boardEntry(key, account));
		await this.ctx.storage.put(BOARD_KEY, sortBoard(board).slice(0, BOARD_SIZE));
	}

	/**
	 * GET /leaderboard?limit=10 — public top players by XP. With a session it
	 * also returns the caller's own line ({position: null} when outside the top 100).
	 */
	async leaderboard(token, url) {
		const limit = Math.max(1, Math.min(BOARD_MAX_LIMIT, Math.floor(Number(url.searchParams.get('limit')) || 10)));
		const board = await this.board();
		const line = (entry, index) => ({ position: index + 1, name: entry.name, avatar: entry.avatar || 0, rank: rankFor(entry.xp).rank, xp: entry.xp, kills: entry.kills, wins: entry.wins, matches: entry.matches });
		const players = board.slice(0, limit).map(line);
		let me = null;
		const found = token ? await this.accountFor(token) : null;
		if (found) {
			const index = board.findIndex((entry) => entry.key === found.key);
			me = index >= 0 ? line(board[index], index) : { ...line(boardEntry(found.key, found.account), 0), position: null };
		}
		return json({ players, me, total: board.length });
	}
}

installChat(GodotAccounts, rankFor);
installPayments(GodotAccounts, { json, profile, brasasOf, randomHex });
