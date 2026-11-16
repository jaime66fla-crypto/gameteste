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

function bearer(request, url) {
	const header = request.headers.get('Authorization') || '';
	if (header.startsWith('Bearer ')) return header.slice(7).trim();
	return url.searchParams.get('token') || '';
}

/** Public routes: POST /godot/register, POST /godot/login, GET /godot/me. */
export async function handleGodotAccount(request, env, url) {
	const accounts = env.GODOT_ACCOUNTS.get(env.GODOT_ACCOUNTS.idFromName('godot-accounts'));
	const route = url.pathname.slice('/godot'.length); // /register, /login, /me
	const headers = { 'content-type': 'application/json' };
	const token = bearer(request, url);
	if (token) headers.Authorization = 'Bearer ' + token;
	const body = request.method === 'POST' ? await request.text() : undefined;
	return accounts.fetch(new Request('https://internal' + route, { method: request.method, headers, body }));
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
				case '/internal/session':
					return this.session(bearer(request, url));
				case '/internal/xp':
					return this.addXp(await request.json());
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
		return json({ profile: profile(account), rankUp: rankFor(account.xp).rankIndex > before.rankIndex });
	}
}
