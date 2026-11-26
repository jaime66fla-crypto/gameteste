// Anticheat do servidor (src/godot-anticheat.js) e o que ele liga: partida, contas (teto de Brasas, infrações, ban).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ShotGate, MoveGate, CheatLog, FIRE, FIRE_SLACK, CREDIT_MS, MOVE_BURST, flagPoints } from '../src/godot-anticheat.js';

const store = JSON.parse(readFileSync(new URL('../godot/data/store.json', import.meta.url), 'utf8'));

// ------------------------------------------------------------- ShotGate ---

test('a hit needs a recent shot of the same weapon; a shotgun shot covers its 8 pellets', () => {
	const g = new ShotGate();
	assert.equal(g.hit('a', 'rifle', 1000), false, 'hit without a shot');
	assert.equal(g.shot('a', 'rifle', 1000), true);
	assert.equal(g.hit('a', 'sniper', 1000), false, 'other weapon');
	assert.equal(g.hit('a', 'rifle', 1000), true);
	assert.equal(g.hit('a', 'rifle', 1000), false, 'one bullet, one hit');
	g.shot('a', 'rifle', 2000);
	assert.equal(g.hit('a', 'rifle', 2000 + CREDIT_MS + 1), false, 'too old');
	g.shot('a', 'shotgun', 10000);
	let pellets = 0;
	while (g.hit('a', 'shotgun', 10000)) pellets++;
	assert.equal(pellets, FIRE.shotgun.pellets);
	assert.equal(g.hit('b', 'shotgun', 10000), false, 'credits belong to the shooter');
});

test('fire rate: a burst after lag passes, a sustained rate above the weapon does not', () => {
	const g = new ShotGate();
	// Sniper: 1,3 s entre tiros. Spam de 20 tiros no mesmo instante: só a rajada mínima (3) vale.
	let ok = 0;
	for (let i = 0; i < 20; i++) ok += g.shot('a', 'sniper', 1000) ? 1 : 0;
	assert.equal(ok, 3);
	// Fuzil no ritmo do jogo (0,115 s) por 10 s: tudo vale.
	const r = new ShotGate();
	let t = 0;
	let fine = 0;
	for (; t < 10000; t += 115) fine += r.shot('a', 'rifle', t) ? 1 : 0;
	assert.equal(fine, Math.floor(10000 / 115) + 1);
	// Fuzil 3× mais rápido por 10 s: no máximo ~1/FIRE_SLACK do ritmo, mais a rajada inicial.
	const c = new ShotGate();
	let cheat = 0;
	for (t = 0; t < 10000; t += 38) cheat += c.shot('a', 'rifle', t) ? 1 : 0;
	const legal = 10 / (FIRE.rifle.interval * FIRE_SLACK);
	assert.ok(cheat <= legal + 1.5 / (FIRE.rifle.interval * FIRE_SLACK) + 1, `${cheat} tiros`);
	assert.ok(cheat < (10000 / 38) * 0.6);
});

// ------------------------------------------------------------- MoveGate ---

test('movement: running is accepted, a teleport is cut to what the time allows', () => {
	const g = new MoveGate(9.5);
	let p = [0, 0, 0];
	// Correndo a 8 m/s, 20 pacotes por segundo, por 5 s: nada cortado.
	for (let t = 0; t <= 5000; t += 50) {
		const to = [(t / 1000) * 8, 0, 0];
		const r = g.move('a', p, to, t);
		assert.equal(r.over, 0);
		p = r.p;
	}
	// Teletransporte de 300 m: anda só o saldo (no máximo MOVE_BURST).
	const r = g.move('a', p, [p[0] + 300, 0, 0], 5050);
	assert.ok(r.over > 290);
	assert.ok(r.p[0] - p[0] <= MOVE_BURST + 0.01);
	// Muitos pacotes curtos sem tempo passando também não somam velocidade.
	let q = r.p;
	for (let i = 0; i < 100; i++) q = g.move('a', q, [q[0] + 1, 0, 0], 5050).p;
	assert.ok(q[0] - r.p[0] < 1, 'no extra metres without time');
});

test('movement: after the server places someone, the first packet may come from near there', () => {
	const g = new MoveGate(9.5);
	g.place('a', 0);
	assert.equal(g.move('a', [0, 0, 0], [20, 0, 0], 10).over, 0, 'within the grace radius');
	g.place('b', 0);
	assert.ok(g.move('b', [0, 0, 0], [200, 0, 0], 10).over > 0, 'far from the spawn');
	assert.equal(g.move('c', null, [123, 0, 0], 0).over, 0, 'unknown start: accepted');
});

test('cheat log sums kinds and empties on take', () => {
	const log = new CheatLog();
	log.add('a', 'nocredit');
	log.add('a', 'teleport', 2);
	log.add('a', 'bogus');
	assert.deepEqual(log.take('a'), { nocredit: 1, teleport: 2 });
	assert.equal(log.take('a'), null);
	assert.equal(flagPoints({ nocredit: 1, teleport: 2, headshots: 1 }), 1 + 6 + 10);
});

// ---------------------------------------------------------- match room ---

class FakeSocket {
	constructor() {
		this.sent = [];
		this.attachment = null;
	}
	send(text) {
		this.sent.push(JSON.parse(text));
	}
	close() {}
	serializeAttachment(value) {
		this.attachment = value;
	}
	deserializeAttachment() {
		return this.attachment;
	}
}
globalThis.WebSocketPair = class {
	constructor() {
		this[0] = new FakeSocket();
		this[1] = new FakeSocket();
	}
};
const RealResponse = globalThis.Response;
globalThis.Response = class extends RealResponse {
	constructor(body, init = {}) {
		super(body, { ...init, status: init.status === 101 ? 200 : init.status });
		this.upgraded = init.status === 101;
	}
	get status() {
		return this.upgraded ? 101 : super.status;
	}
};

const { GodotMatch } = await import('../src/godot-match.js');
const { GodotAccounts, resolveSession } = await import('../src/godot-accounts.js');

async function runningMatch() {
	const xpCalls = [];
	const ctx = {
		storage: { get: async () => undefined, put: async () => {}, setAlarm: async () => {}, deleteAll: async () => {} },
		blockConcurrencyWhile: (fn) => fn(),
		acceptWebSocket: () => {},
		getWebSockets: () => [],
		waitUntil: (p) => p,
	};
	const env = {
		GODOT_ACCOUNTS: {
			idFromName: () => 'a',
			get: () => ({ fetch: async (req) => (xpCalls.push(await req.json()), new RealResponse('{}', { status: 500 })) }),
		},
	};
	const match = new GodotMatch(ctx, env);
	const players = [];
	for (const [i, name] of ['A', 'B'].entries()) {
		const url = `https://internal/join?party=1${i ? '' : '&create=1'}&room=ABCDE&name=${name}&account=acct:${name.toLowerCase()}&xp=0`;
		const response = await match.fetch(new Request(url, { headers: { Upgrade: 'websocket' } }));
		assert.equal(response.status, 101);
		const ws = [...match.sessions.values()].at(-1);
		players.push({ ws, id: ws.deserializeAttachment().id });
	}
	const [a, b] = players;
	const say = (p, data) => match.webSocketMessage(p.ws, JSON.stringify(data));
	say(b, { t: 'team', team: 1 });
	say(b, { t: 'ready' });
	say(a, { t: 'start' });
	assert.equal(match.match.phase, 'running');
	const me = match.match.players[a.id];
	const them = match.match.players[b.id];
	me.inv = { rifle: true, sniper: true };
	me.p = [0, 0, 0];
	them.p = [20, 0, 0];
	them.hp = 1000; // não morre no meio do teste
	return { match, a, b, me, them, say, xpCalls };
}

test('match: a hit without a shot does nothing; with a shot it hurts', async () => {
	const { a, b, them, say, match } = await runningMatch();
	say(a, { t: 'hit', target: b.id, zone: 'chest', w: 'rifle' });
	assert.equal(them.hp, 1000);
	say(a, { t: 'shot', w: 'rifle', o: [0, 1.5, 0], e: [20, 1.5, 0] });
	say(a, { t: 'hit', target: b.id, zone: 'chest', w: 'rifle' });
	assert.equal(them.hp, 1000 - 27);
	assert.deepEqual(match.cheat.take(a.id), { nocredit: 1 });
});

test('match: sniper spam deals at most the burst, not 18 shots a second', async () => {
	const { a, b, them, say } = await runningMatch();
	for (let i = 0; i < 18; i++) {
		say(a, { t: 'shot', w: 'sniper', o: [0, 1.5, 0], e: [20, 1.5, 0] });
		say(a, { t: 'hit', target: b.id, zone: 'chest', w: 'sniper' });
	}
	assert.equal(them.hp, 1000 - 3 * 95);
});

test('match: a teleport is cut and the hit range uses the server position', async () => {
	const { a, b, me, them, say, match, xpCalls } = await runningMatch();
	me.inv.shotgun = true;
	them.p = [200, 0, 0]; // longe demais para a escopeta (70 m)
	say(a, { t: 's', p: [195, 0, 0] });
	assert.ok(me.p[0] <= MOVE_BURST + 0.01 + 30, `server kept the runner near the spawn (${me.p[0]})`);
	say(a, { t: 'shot', w: 'shotgun', o: [195, 1.5, 0], e: [200, 1.5, 0] });
	say(a, { t: 'hit', target: b.id, zone: 'chest', w: 'shotgun' });
	assert.equal(them.hp, 1000, 'out of range from where the server says you are');
	// As infrações vão para a conta no fim da partida.
	await match.flush(me, false);
	assert.equal(xpCalls.at(-1).account, 'acct:a');
	assert.ok(xpCalls.at(-1).flags.teleport >= 1);
});

// -------------------------------------------------------------- accounts ---

function accountsService(env = {}) {
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
	return { accounts: new GodotAccounts({ storage, getWebSockets: () => [] }, env), data };
}

async function call(accounts, path, { token = '', body } = {}) {
	const headers = { 'content-type': 'application/json' };
	if (token) headers.Authorization = 'Bearer ' + token;
	const response = await accounts.fetch(new Request('https://internal' + path, { method: body ? 'POST' : 'GET', headers, body: body ? JSON.stringify(body) : undefined }));
	return { status: response.status, data: await response.json() };
}

test('brasas earned by playing stop at the daily cap; xp still counts', async (t) => {
	let now = Date.UTC(2026, 10, 26, 15);
	t.mock.method(Date, 'now', () => now);
	const { accounts } = accountsService();
	const token = (await call(accounts, '/register', { body: { name: 'Farmer', password: 'segredo1' } })).data.token;
	const cap = store.brasas_dia_max;
	assert.ok(Number.isInteger(cap) && cap > 0);
	let total = 0;
	for (let i = 0; i < 20; i++) total += (await call(accounts, '/internal/xp', { body: { account: 'acct:farmer', xp: 2000 } })).data.brasasGained;
	assert.equal(total, cap);
	const me = (await call(accounts, '/me', { token })).data.profile;
	assert.equal(me.brasas, store.start + cap);
	assert.equal(me.xp, 40000, 'xp is not capped');
	now += 24 * 3600 * 1000; // dia seguinte
	const next = await call(accounts, '/internal/xp', { body: { account: 'acct:farmer', xp: 100 } });
	assert.equal(next.data.brasasGained, 100 / store.xp_per_brasa);
});

test('flags pile up on the account and show on the admin panel (only with the secret)', async () => {
	const secret = 'x'.repeat(32);
	const { accounts } = accountsService({ ADMIN_TOKEN: secret });
	await call(accounts, '/register', { body: { name: 'Hacker', password: 'segredo1' } });
	await call(accounts, '/register', { body: { name: 'Honesto', password: 'segredo1' } });
	await call(accounts, '/internal/xp', { body: { account: 'acct:hacker', xp: 10, flags: { teleport: 4, nocredit: 30 } } });
	await call(accounts, '/internal/xp', { body: { account: 'acct:honesto', xp: 10, flags: { nocredit: 1 } } });
	assert.equal((await call(accounts, '/admin/flags')).status, 404, 'no secret');
	assert.equal((await call(accounts, '/admin/flags', { token: 'y'.repeat(32) })).status, 404, 'wrong secret');
	const panel = await call(accounts, '/admin/flags', { token: secret });
	assert.equal(panel.status, 200);
	assert.deepEqual(panel.data.accounts.map((r) => [r.name, r.points]), [['Hacker', 42], ['Honesto', 1]]);
	const weak = accountsService({ ADMIN_TOKEN: 'curto' });
	assert.equal((await call(weak.accounts, '/admin/flags', { token: 'curto' })).status, 404, 'a short secret never opens the panel');
});

test('a banned account cannot log in, play, chat or buy; unban restores it', async () => {
	const secret = 'z'.repeat(32);
	const { accounts } = accountsService({ ADMIN_TOKEN: secret, MP_ACCESS_TOKEN: 'x' });
	const token = (await call(accounts, '/register', { body: { name: 'Trapaça', password: 'segredo1' } })).data.token;
	const ban = await call(accounts, '/admin/ban', { token: secret, body: { name: 'trapaça', hours: 24, reason: 'aimbot' } });
	assert.equal(ban.status, 200);
	const login = await call(accounts, '/login', { body: { name: 'Trapaça', password: 'segredo1' } });
	assert.equal(login.status, 403);
	assert.match(login.data.error, /suspensa.*aimbot/);
	assert.equal((await call(accounts, '/me', { token })).status, 401);
	assert.equal((await call(accounts, '/internal/session', { token })).status, 403);
	const env = { GODOT_ACCOUNTS: { idFromName: () => 'a', get: () => accounts } };
	const session = await resolveSession(env, token);
	assert.equal(session.banned, true);
	assert.match(session.message, /aimbot/);
	assert.equal((await call(accounts, '/pay/pix', { token, body: { pack: store.pacotes[0].id, email: 'a@b.com' } })).status, 403);
	const board = await call(accounts, '/leaderboard?limit=50');
	assert.ok(!board.data.players.some((p) => p.name === 'Trapaça'), 'banned players leave the ranking');
	assert.equal((await call(accounts, '/admin/unban', { token: secret, body: { name: 'Trapaça' } })).status, 200);
	assert.equal((await call(accounts, '/login', { body: { name: 'Trapaça', password: 'segredo1' } })).status, 200);
	assert.equal((await call(accounts, '/me', { token })).status, 200);
});
