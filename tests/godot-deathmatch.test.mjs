// Mata-mata (public rooms with mode=dm) in src/godot-match.js, with a fake Durable Object runtime.
import test from 'node:test';
import assert from 'node:assert/strict';

class FakeSocket {
	constructor() {
		this.sent = [];
		this.attachment = null;
	}
	accept() {}
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
	last(type) {
		return this.sent.filter((m) => m.t === type).at(-1);
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
		const status = init.status === 101 ? 200 : init.status;
		super(body, { ...init, status });
		this.upgraded = init.status === 101;
		this.webSocket = init.webSocket;
	}
	get status() {
		return this.upgraded ? 101 : super.status;
	}
};

const { GodotMatch } = await import('../src/godot-match.js');

function room() {
	const store = new Map();
	const alarms = [];
	const ctx = {
		storage: {
			get: async (k) => store.get(k),
			put: async (k, v) => store.set(k, v),
			setAlarm: async (at) => alarms.push(at),
			deleteAll: async () => store.clear(),
		},
		blockConcurrencyWhile: (fn) => fn(),
		acceptWebSocket: () => {},
		getWebSockets: () => [],
		waitUntil: () => {},
	};
	const env = { GODOT_ACCOUNTS: { idFromName: () => 'a', get: () => ({ fetch: async () => new RealResponse('{}', { status: 500 }) }) } };
	const match = new GodotMatch(ctx, env);
	match.alarms = alarms;
	match.store = store;
	return match;
}

let accountSeq = 0;
async function join(match, { mode = 'dm', name = 'P', invite = false } = {}) {
	const url = `https://internal/join?room=abc123&name=${name}&account=acc${++accountSeq}&xp=0${mode ? '&mode=' + mode : ''}${invite ? '&invite=1' : ''}`;
	const response = await match.fetch(new Request(url, { headers: { Upgrade: 'websocket' } }));
	if (response.status !== 101) return { status: response.status, text: await response.text() };
	const server = [...match.sessions.values()].at(-1);
	return { status: 101, ws: server, id: server.deserializeAttachment().id };
}
const say = (match, player, data) => match.webSocketMessage(player.ws, JSON.stringify(data));

async function started() {
	const match = room();
	const a = await join(match, { name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	return { match, a, b, m: match.match };
}

test('the first player sets the room mode; other queues and invites follow it', async () => {
	const match = room();
	const a = await join(match, { name: 'A' });
	assert.equal(a.ws.last('welcome').mode, 'dm');
	assert.equal(a.ws.last('party').mode, 'dm');
	assert.equal(a.ws.last('party').goal, 15);
	const wrong = await join(match, { mode: '', name: 'X' });
	assert.equal(wrong.status, 409, 'an elimination player is never put in a mata-mata room');
	const friend = await join(match, { mode: '', invite: true, name: 'F' });
	assert.equal(friend.status, 101, 'friend invites join whatever mode the room has');
	assert.equal(friend.ws.last('welcome').mode, 'dm');
});

test('the matchmaker keeps a separate open room for mata-mata', async () => {
	const mm = room();
	const elim = await (await mm.assign(new URL('https://internal/assign'))).json();
	const dm = await (await mm.assign(new URL('https://internal/assign?mode=dm'))).json();
	assert.notEqual(elim.room, dm.room);
	assert.equal((await (await mm.assign(new URL('https://internal/assign?mode=dm'))).json()).room, dm.room);
	assert.equal((await (await mm.assign(new URL('https://internal/assign'))).json()).room, elim.room);
});

test('mata-mata starts everyone with a pistol and announces the rules', async () => {
	const { a, m } = await started();
	const start = a.ws.last('start');
	assert.equal(start.mode, 'dm');
	assert.equal(start.goal, 15);
	assert.deepEqual(start.kit, { pistol: 45 });
	assert.equal(start.roster.length, 8, 'bots fill the room');
	for (const id of m.order) assert.deepEqual(m.players[id].inv, { pistol: true });
});

test('dying schedules a respawn with a pistol, costs no XP, and the alarm brings you back', async () => {
	const { match, a, b, m } = await started();
	const victim = m.players[b.id];
	victim.inv.rifle = true;
	match.damage(m.players[a.id], victim, 999, 'pistol', 'chest');
	assert.equal(victim.dead, true);
	assert.equal(victim.deaths, 1);
	assert.equal(m.players[a.id].kills, 1);
	assert.equal(b.ws.last('hp').respawn, 3000);
	assert.equal(victim.xpGain, 0, 'no death penalty in mata-mata');
	assert.ok(Object.values(m.crates).some((c) => c.drop && c.items.rifle), 'weapons drop in a crate');
	assert.ok(match.alarms.at(-1) <= Date.now() + 3000, 'alarm set for the respawn');
	match.dmTick(Date.now() + 1000);
	assert.equal(victim.dead, true, 'not before the 3 s');
	match.dmTick(Date.now() + 3100);
	assert.equal(victim.dead, false);
	assert.equal(victim.hp, 100);
	assert.deepEqual(victim.inv, { pistol: true });
	const respawn = a.ws.last('respawn');
	assert.equal(respawn.id, b.id);
	assert.equal(respawn.w, 'pistol');
	assert.equal(respawn.p.length, 3);
});

test('spawn protection blocks damage until the protected player attacks', async () => {
	const { match, a, b, m } = await started();
	const victim = m.players[b.id];
	match.damage(m.players[a.id], victim, 999, 'pistol', 'chest');
	match.dmTick(Date.now() + 3100);
	match.damage(m.players[a.id], victim, 30, 'pistol', 'chest');
	assert.equal(victim.hp, 100, 'protected right after respawning');
	const bot = Object.values(m.players).find((p) => p.bot);
	match.damage(victim, bot, 10, 'pistol', 'chest');
	match.damage(m.players[a.id], victim, 30, 'pistol', 'chest');
	assert.equal(victim.hp, 70, 'attacking ends the protection');
});

test('players who left do not respawn', async () => {
	const { match, b, m } = await started();
	const victim = m.players[b.id];
	const bot = Object.values(m.players).find((p) => p.bot);
	match.damage(bot, victim, 999, 'rifle', 'chest');
	match.webSocketClose(b.ws);
	match.dmTick(Date.now() + 5000);
	assert.equal(victim.dead, true);
});

test('opened map crates refill after a while', async () => {
	const { match, a, m } = await started();
	const crate = Object.values(m.crates).find((c) => !c.med && !c.tower);
	m.players[a.id].p = [...crate.p];
	say(match, a, { t: 'loot', crate: crate.id });
	assert.equal(crate.open, true);
	assert.ok(crate.refillAt > Date.now());
	match.dmTick(crate.refillAt + 1);
	assert.equal(crate.open, false);
	assert.equal(Object.keys(crate.items).length, 1);
	assert.equal(a.ws.last('refill').crate.id, crate.id);
});

test('the first to 15 kills wins; the board is sorted by kills then deaths', async () => {
	const { match, a, m } = await started();
	const me = m.players[a.id];
	const bots = Object.values(m.players).filter((p) => p.bot);
	for (let i = 0; i < 15; i++) {
		const target = bots[i % bots.length];
		Object.assign(target, { dead: false, hp: 100, safeUntil: 0 });
		match.damage(me, target, 999, 'pistol', 'chest');
	}
	assert.equal(m.phase, 'finished');
	const end = a.ws.last('end');
	assert.equal(end.winner, a.id);
	assert.equal(end.reason, 'abates');
	assert.equal(end.mode, 'dm');
	assert.equal(end.board[0].id, a.id);
	assert.equal(end.board[0].kills, 15);
	assert.ok('deaths' in end.board[0]);
});

test('on timeout the most kills wins, even if that player is dead right now', async () => {
	const { match, a, b, m } = await started();
	const [bot, other] = Object.values(m.players).filter((p) => p.bot);
	match.damage(m.players[a.id], m.players[b.id], 999, 'pistol', 'chest');
	match.damage(m.players[a.id], other, 999, 'pistol', 'chest');
	match.damage(bot, m.players[a.id], 999, 'rifle', 'chest');
	match.checkEnd(true);
	assert.equal(a.ws.last('end').winner, a.id);
	assert.equal(a.ws.last('end').reason, 'tempo');
});

test('ties on kills go to the player with fewer deaths', async () => {
	const { match, a, b, m } = await started();
	const bot = Object.values(m.players).find((p) => p.bot);
	match.damage(m.players[a.id], m.players[b.id], 999, 'pistol', 'chest');
	match.damage(bot, m.players[a.id], 999, 'rifle', 'chest');
	match.checkEnd(true);
	assert.equal(a.ws.last('end').winner, bot.id, '1 kill / 0 deaths beats 1 kill / 1 death');
});

test('elimination rooms keep one life', async () => {
	const match = room();
	const a = await join(match, { mode: '', name: 'A' });
	const b = await join(match, { mode: '', name: 'B' });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	assert.equal(a.ws.last('start').mode, 'elim');
	assert.deepEqual(m.players[a.id].inv, {}, 'unarmed start');
	match.damage(m.players[a.id], m.players[b.id], 999, 'rifle', 'chest');
	assert.equal(m.players[b.id].respawnAt, 0);
	match.dmTick(Date.now() + 10000);
	assert.equal(m.players[b.id].dead, true);
});
