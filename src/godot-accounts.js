// Player accounts for the Godot build: register / login, sessions, XP and rank.
// One Durable Object instance ("godot-accounts") owns every account so names
// stay unique. Passwords are stored only as salted PBKDF2-SHA256 hashes.
import ranks from '../godot/data/ranks.json' with { type: 'json' };

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
		xp: account.xp,
		...rankFor(account.xp),
		kills: account.kills,
		botKills: account.botKills,
		wins: account.wins,
		matches: account.matches,
	};
}

const BOARD_KEY = 'board';
const BOARD_SIZE = 100; // players kept in the stored leaderboard
const BOARD_MAX_LIMIT = 50; // most rows one request can return

function boardEntry(key, account) {
	return { key, name: account.name, xp: account.xp || 0, kills: account.kills || 0, wins: account.wins || 0, matches: account.matches || 0 };
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
	const body = request.method === 'POST' ? await request.text() : undefined;
	return accounts.fetch(new Request('https://internal' + route + url.search, { method: request.method, headers, body }));
}

const MAX_FRIENDS = 100;
const ONLINE_MS = 25000; // a client polls every ~8 s while the game is open
const INVITE_MS = 120000;

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
		if (await this.ctx.storage.get(key)) return json({ error: 'Esse nome já está em uso.' }, 409);
		const salt = randomHex(16);
		const account = { name, salt, hash: await hashPassword(password, salt), xp: 0, kills: 0, botKills: 0, wins: 0, matches: 0, created: Date.now(), failures: 0, lockedUntil: 0 };
		await this.ctx.storage.put(key, account);
		await this.updateBoard(key, account);
		return json({ token: await this.newSession(key), profile: profile(account) }, 201);
	}

	async login(body) {
		const key = this.key(String(body?.name || '').trim());
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
		const account = await this.ctx.storage.get(session.account);
		return account ? { key: session.account, account } : null;
	}

	async me(token) {
		const found = await this.accountFor(token);
		return found ? json({ profile: profile(found.account) }) : json({ error: 'Sessão expirada. Entre de novo.' }, 401);
	}

	async session(token) {
		const found = await this.accountFor(token);
		return found ? json({ account: found.key, name: found.account.name, xp: found.account.xp }) : json({ error: 'invalid' }, 401);
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
		const code = /^[A-Z0-9]{5}$/.test(url.searchParams.get('code') || '') ? url.searchParams.get('code') : '';
		const now = Date.now();
		this.presence.set(found.key, { seen: now, status, code: status === 'room' ? code : '' });
		const friends = [];
		for (const key of found.account.friends || []) {
			const friend = await this.ctx.storage.get(key);
			if (!friend) continue;
			const seen = this.presence.get(key);
			const online = !!seen && now - seen.seen < ONLINE_MS;
			friends.push({ name: friend.name, rank: rankFor(friend.xp).rank, online, status: online ? seen.status : 'offline', code: online ? seen.code : '' });
		}
		friends.sort((a, b) => Number(b.online) - Number(a.online) || a.name.localeCompare(b.name));
		const requests = [];
		for (const key of found.account.requests || []) {
			const other = await this.ctx.storage.get(key);
			if (other) requests.push(other.name);
		}
		const invites = (this.invites.get(found.key) || []).filter((invite) => now - invite.at < INVITE_MS);
		this.invites.delete(found.key);
		return json({ friends, requests, invites: invites.map(({ from, code }) => ({ from, code })) });
	}

	/** POST /friends/<add|accept|decline|remove|invite> with {name} (and {code} for invite). */
	async friendAction(token, action, body) {
		const found = await this.accountFor(token);
		if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
		const me = found.account;
		const meKey = found.key;
		const name = String(body?.name || '').trim();
		const otherKey = this.key(name);
		if (!NAME_RULE.test(name)) return json({ error: 'Nome inválido.' }, 400);
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
				const code = String(body?.code || '').toUpperCase();
				if (!/^[A-Z0-9]{5}$/.test(code)) return json({ error: 'Entre numa sala personalizada para convidar.' }, 400);
				if (!me.friends.includes(otherKey)) return json({ error: 'Só dá para convidar amigos.' }, 400);
				const list = (this.invites.get(otherKey) || []).filter((invite) => invite.from !== me.name);
				list.push({ from: me.name, code, at: Date.now() });
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
		account.xp += count(body.xp);
		account.kills += count(body.kills);
		account.botKills += count(body.botKills);
		account.wins += body.win ? 1 : 0;
		account.matches += 1;
		await this.ctx.storage.put(key, account);
		await this.updateBoard(key, account);
		return json({ profile: profile(account), rankUp: rankFor(account.xp).rankIndex > before.rankIndex });
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
		const line = (entry, index) => ({ position: index + 1, name: entry.name, rank: rankFor(entry.xp).rank, xp: entry.xp, kills: entry.kills, wins: entry.wins, matches: entry.matches });
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
