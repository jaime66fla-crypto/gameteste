// Custom team rooms (2x2 / 4x4) in src/godot-match.js, with a fake Durable Object runtime.
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
// The runtime allows status 101; Node's Response does not.
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
	const ctx = {
		storage: {
			get: async (k) => store.get(k),
			put: async (k, v) => store.set(k, v),
			setAlarm: async () => {},
			deleteAll: async () => store.clear(),
		},
		blockConcurrencyWhile: (fn) => fn(),
		acceptWebSocket: () => {},
		getWebSockets: () => [],
		waitUntil: () => {},
	};
	const env = { GODOT_ACCOUNTS: { idFromName: () => 'a', get: () => ({ fetch: async () => new RealResponse('{}', { status: 500 }) }) } };
	return new GodotMatch(ctx, env);
}

let accountSeq = 0;
async function join(match, { create = false, code = 'ABCDE', name = 'P' } = {}) {
	const url = `https://internal/join?party=1${create ? '&create=1' : ''}&room=${code}&name=${name}&account=acc${++accountSeq}&xp=0`;
	const response = await match.fetch(new Request(url, { headers: { Upgrade: 'websocket' } }));
	if (response.status !== 101) return { status: response.status, text: await response.text() };
	const server = [...match.sessions.values()].at(-1);
	return { status: 101, ws: server, id: server.deserializeAttachment().id };
}
const say = (match, player, data) => match.webSocketMessage(player.ws, JSON.stringify(data));

test('XP penalties: dying costs XP and quitting a running match while alive costs more (once)', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	const c = await join(match, { name: 'C' });
	say(match, b, { t: 'ready' });
	say(match, c, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	assert.equal(m.phase, 'running');
	const bot = Object.values(m.players).find((p) => p.bot);
	// A morre para um bot: -40 XP, avisado na hora.
	match.damage(bot, m.players[a.id], 999, 'rifle', 'chest');
	assert.equal(a.ws.last('xp').amount, -40);
	assert.equal(a.ws.last('xp').reason, 'death');
	assert.equal(m.players[a.id].xpGain, -40);
	// A, já morto, sai: sem penalidade de saída (estava só assistindo).
	match.webSocketClose(a.ws);
	assert.equal(m.players[a.id].xpGain, -40);
	// C sai vivo no meio da partida: -100, e a eliminação por sair não cobra a morte de novo.
	match.webSocketClose(c.ws);
	assert.equal(m.players[c.id].xpGain, -100);
	assert.equal(m.players[c.id].dead, true);
});

test('joining a code that was never created is refused', async () => {
	const match = room();
	const r = await join(match);
	assert.equal(r.status, 404);
});

test('leader creates, friends join, teams balance and the leader configures', async () => {
	const match = room();
	const leader = await join(match, { create: true, name: 'Lider' });
	assert.equal(leader.status, 101);
	assert.equal(leader.ws.last('welcome').party, true);
	const friend = await join(match, { name: 'Amigo' });
	const party = friend.ws.last('party');
	assert.equal(party.leader, leader.id);
	assert.deepEqual(party.players.map((p) => p.team), [0, 1]);
	// Non-leaders cannot change the mode or start.
	say(match, friend, { t: 'config', size: 4, bots: true });
	assert.equal(match.match.size, 2);
	say(match, friend, { t: 'start' });
	assert.equal(match.match.phase, 'waiting');
	// Friend switches to the leader's team.
	say(match, friend, { t: 'team', team: 0 });
	assert.deepEqual(leader.ws.last('party').players.map((p) => p.team), [0, 0]);
	// A third player cannot squeeze into a full team in 2x2.
	const third = await join(match, { name: 'Terceiro' });
	assert.equal(match.match.players[third.id].team, 1);
	say(match, third, { t: 'team', team: 0 });
	assert.match(third.ws.last('party_note').message, /cheia/);
	say(match, leader, { t: 'config', size: 4, bots: true });
	assert.equal(match.match.size, 4);
});

test('2x2 with bots: teams filled, no friendly fire, team wins when the other side is gone', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'team', team: 0 }); // both humans on Alfa, Bravo is all bots
	say(match, a, { t: 'start' }); // B has not confirmed: no start
	assert.equal(match.match.phase, 'waiting');
	assert.match(a.ws.last('party_note').message, /Aguardando/);
	say(match, b, { t: 'ready' });
	assert.equal(a.ws.last('party').allReady, true);
	say(match, a, { t: 'start' });
	const start = a.ws.last('start');
	assert.equal(start.party, true);
	assert.equal(start.roster.length, 4);
	assert.deepEqual(start.roster.map((r) => r.team).sort(), [0, 0, 1, 1]);
	assert.ok(start.roster.every((r) => Array.isArray(r.sp)));
	const m = match.match;
	for (const id of Object.keys(m.players)) m.players[id].inv = { rifle: true };
	// Friendly fire is ignored.
	say(match, a, { t: 'hit', target: b.id, zone: 'chest', w: 'rifle' });
	assert.equal(m.players[b.id].hp, 100);
	// Wipe out Bravo's bots.
	const bots = start.roster.filter((r) => r.team === 1).map((r) => r.id);
	for (const bot of bots) for (let i = 0; i < 4; i++) say(match, a, { t: 'hit', target: bot, zone: 'chest', w: 'rifle' });
	const end = b.ws.last('end');
	assert.ok(end, 'match ended');
	assert.equal(end.team, 0);
	assert.equal(end.name, 'Equipe Alfa');
	assert.equal(m.phase, 'finished');
});

test('custom room is preserved after the match: same code, teams, leader and mode; ready again', async () => {
	const match = room();
	const a = await join(match, { create: true, code: 'KEEP1', name: 'A' });
	const b = await join(match, { code: 'KEEP1', name: 'B' });
	say(match, a, { t: 'config', size: 4, bots: true });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	for (const id of Object.keys(m.players)) m.players[id].inv = { rifle: true };
	// Alfa (A) wipes out Bravo (B + 3 bots).
	const bravo = a.ws.last('start').roster.filter((r) => r.team === 1).map((r) => r.id);
	for (const target of bravo) for (let i = 0; i < 4; i++) say(match, a, { t: 'hit', target, zone: 'chest', w: 'rifle' });
	assert.equal(b.ws.last('end').team, 0);
	const lobby = b.ws.last('party');
	assert.equal(match.match.phase, 'waiting');
	assert.equal(lobby.code, 'KEEP1');
	assert.equal(lobby.leader, a.id);
	assert.equal(lobby.size, 4);
	assert.equal(lobby.bots, true);
	assert.deepEqual(lobby.players.map((p) => [p.id, p.team]), [[a.id, 0], [b.id, 1]]);
	assert.equal(lobby.players.find((p) => p.id === b.id).ready, false, 'ready resets');
	assert.ok(Object.values(match.match.players).every((p) => !p.bot), 'bots removed');
	assert.equal(match.match.players[b.id].hp, 100);
	// A friend can still join with the same code, and a new match starts normally.
	const c = await join(match, { code: 'KEEP1', name: 'C' });
	assert.equal(c.status, 101);
	say(match, a, { t: 'start' });
	assert.equal(match.match.phase, 'waiting', 'waits for ready again');
	say(match, b, { t: 'ready' });
	say(match, c, { t: 'ready' });
	say(match, a, { t: 'start' });
	assert.equal(match.match.phase, 'running');
	assert.equal(a.ws.last('start').roster.length, 8);
});

test('without bots both teams need a player; leader leaving passes leadership', async () => {
	const match = room();
	const a = await join(match, { create: true });
	const b = await join(match);
	say(match, b, { t: 'team', team: 0 });
	say(match, a, { t: 'config', size: 2, bots: false });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	assert.equal(match.match.phase, 'waiting');
	assert.match(a.ws.last('party_note').message, /duas equipes/);
	match.webSocketClose(a.ws);
	assert.equal(match.match.leader, b.id);
	assert.equal(b.ws.last('party').leader, b.id);
});

test('fewer weapon crates; medkits are collected, stack, and F (heal) uses one', async () => {
	const match = room();
	const a = await join(match, { create: true });
	const b = await join(match);
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const start = a.ws.last('start');
	const weapons = start.crates.filter((c) => !c.med && !c.tower);
	const meds = start.crates.filter((c) => c.med);
	assert.equal(weapons.length, 16);
	const tower = start.crates.find((c) => c.tower);
	assert.ok(tower && tower.items.sniper && tower.p[1] >= 5, 'sniper crate on the tower roof');
	assert.ok(meds.length >= 4);
	const m = match.match;
	const me = m.players[a.id];
	// Collect two kits at full health: they go to the inventory.
	for (const kit of meds.slice(0, 2)) {
		me.p = [...kit.p];
		say(match, a, { t: 'loot', crate: kit.id });
		assert.equal(m.crates[kit.id].open, true);
	}
	assert.equal(me.medkits, 2);
	assert.equal(me.hp, 100);
	assert.equal(b.ws.last('medkits').count, 2);
	// A used crate cannot be looted again.
	m.players[b.id].p = [...meds[0].p];
	say(match, b, { t: 'loot', crate: meds[0].id });
	assert.equal(m.players[b.id].medkits, 0);
	// Using a kit takes 3 s: heal_start, then heal (server checks the time).
	const useKit = () => {
		say(match, a, { t: 'heal_start' });
		if (me.healAt) me.healAt -= 3000;
		say(match, a, { t: 'heal' });
	};
	useKit(); // full health: nothing
	assert.equal(me.medkits, 2);
	me.hp = 30;
	say(match, a, { t: 'heal_start' });
	say(match, a, { t: 'heal' }); // instant heal refused
	assert.equal(me.hp, 30, 'heal without waiting 3 s is refused');
	say(match, a, { t: 'heal' }); // without heal_start: refused
	assert.equal(me.hp, 30);
	useKit();
	assert.equal(me.hp, 80);
	assert.equal(me.medkits, 1);
	assert.equal(b.ws.last('hp').hp, 80);
	useKit();
	assert.equal(me.hp, 100, 'capped at 100');
	assert.equal(me.medkits, 0);
	useKit();
	assert.equal(me.medkits, 0);
	// Carried kits drop with the player.
	me.medkits = 3;
	me.inv = {};
	match.dropCrate(me);
	const drop = b.ws.last('crate').crate;
	assert.equal(drop.medkits, 3);
	m.players[b.id].p = [...drop.p];
	say(match, b, { t: 'loot', crate: drop.id });
	assert.equal(m.players[b.id].medkits, 3);
});

test('grenades: looted, thrown, server-checked blast with falloff, no team damage, self damage without kill credit', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	const me = m.players[a.id];
	// Tower crate: only from the roof, not from under it.
	const tower = m.crates.t0;
	me.p = [tower.p[0], 0, tower.p[2]];
	say(match, a, { t: 'loot', crate: 't0' });
	assert.equal(tower.open, false, 'cannot loot the roof crate from the ground');
	me.p = [tower.p[0], tower.p[1], tower.p[2]];
	say(match, a, { t: 'loot', crate: 't0' });
	assert.equal(tower.open, true);
	assert.equal(me.nades, 1);
	assert.equal(b.ws.last('nades').count, 1);
	// No grenades: throw ignored.
	const enemy = Object.values(m.players).find((p) => p.team !== me.team && p.bot);
	const ally = Object.values(m.players).find((p) => p.team === me.team && p.id !== me.id);
	me.p = [0, 0, 0];
	enemy.p = [10, 0, 0];
	ally.p = [11, 0, 0];
	say(match, a, { t: 'throw', id: 'gren1', o: [0, 1.5, 0], v: [10, 4, 0] });
	assert.equal(me.nades, 0);
	assert.equal(b.ws.last('nade').id, 'gren1');
	say(match, a, { t: 'throw', id: 'gren2', o: [0, 1.5, 0], v: [10, 4, 0] });
	assert.equal(m.grenades[a.id + ':gren2'], undefined, 'no grenades left');
	// Exploding too early is refused.
	say(match, a, { t: 'boom', id: 'gren1', p: [10, 0.5, 0] });
	assert.equal(enemy.hp, 100);
	// A valid blast 2.5 s later: enemy hurt by distance, teammate untouched.
	me.nades = 1;
	say(match, a, { t: 'throw', id: 'gren3', o: [0, 1.5, 0], v: [10, 4, 0] });
	m.grenades[a.id + ':gren3'].at -= 2500;
	say(match, a, { t: 'boom', id: 'gren3', p: [10, 1, 0] });
	assert.equal(b.ws.last('boom').id, 'gren3');
	assert.equal(enemy.hp, 0, 'point-blank grenade kills');
	assert.equal(ally.hp, 100, 'no friendly fire');
	assert.equal(me.kills, 1);
	// Too far from the throw: refused.
	me.nades = 1;
	say(match, a, { t: 'throw', id: 'gren4', o: [0, 1.5, 0], v: [10, 4, 0] });
	m.grenades[a.id + ':gren4'].at -= 2500;
	say(match, a, { t: 'boom', id: 'gren4', p: [80, 1, 0] });
	assert.notEqual(b.ws.last('boom').id, 'gren4');
	// Own grenade hurts the thrower but never counts as a kill.
	me.nades = 1;
	me.hp = 30;
	say(match, a, { t: 'throw', id: 'gren5', o: [0, 1.5, 0], v: [1, 1, 0] });
	m.grenades[a.id + ':gren5'].at -= 2000;
	say(match, a, { t: 'boom', id: 'gren5', p: [0, 1, 0] });
	assert.equal(me.dead, true);
	assert.equal(me.kills, 1, 'self kill not counted');
});

test('public elimination room: no timer, everyone confirms ready, the first player starts', async () => {
	const match = room();
	const joinPublic = async (name) => {
		const url = `https://internal/join?room=PUB1&name=${name}&account=acc${++accountSeq}&xp=0`;
		const response = await match.fetch(new Request(url, { headers: { Upgrade: 'websocket' } }));
		assert.equal(response.status, 101);
		const ws = [...match.sessions.values()].at(-1);
		return { ws, id: ws.deserializeAttachment().id };
	};
	const first = await joinPublic('Primeiro');
	const second = await joinPublic('Segundo');
	const third = await joinPublic('Terceiro');
	const lobby = third.ws.last('party');
	assert.equal(lobby.party, false);
	assert.equal(lobby.leader, first.id);
	assert.equal(lobby.capacity, 8);
	assert.deepEqual(lobby.players.map((p) => p.ready), [true, false, false]); // leader counts as ready
	await match.alarm(); // no countdown: nothing starts by itself
	assert.equal(match.match.phase, 'waiting');
	say(match, second, { t: 'start' }); // only the leader can start
	assert.equal(match.match.phase, 'waiting');
	say(match, second, { t: 'ready' });
	say(match, first, { t: 'start' });
	assert.equal(match.match.phase, 'waiting');
	assert.match(first.ws.last('party_note').message, /Terceiro/);
	say(match, third, { t: 'ready' });
	say(match, third, { t: 'ready', ready: false }); // can take it back
	assert.equal(first.ws.last('party').allReady, false);
	say(match, third, { t: 'ready' });
	say(match, first, { t: 'start' });
	assert.equal(match.match.phase, 'running');
	assert.equal(first.ws.last('start').roster.length, 8); // bots fill the free slots
	// Leader leaving before the start passes the room to the next player.
	const other = room();
	const a = await (async () => {
		const response = await other.fetch(new Request(`https://internal/join?room=PUB2&name=A&account=acc${++accountSeq}&xp=0`, { headers: { Upgrade: 'websocket' } }));
		assert.equal(response.status, 101);
		return [...other.sessions.values()].at(-1);
	})();
	await other.fetch(new Request(`https://internal/join?room=PUB2&name=B&account=acc${++accountSeq}&xp=0`, { headers: { Upgrade: 'websocket' } }));
	const b = [...other.sessions.values()].at(-1);
	other.webSocketClose(a);
	assert.equal(b.last('party').leader, b.deserializeAttachment().id);
});

test('invited friend joins a public elimination waiting room, but not an empty/gone or started one', async () => {
	const match = room();
	const open = (params) => match.fetch(new Request(`https://internal/join?${params}&name=X&account=acc${++accountSeq}&xp=0`, { headers: { Upgrade: 'websocket' } }));
	// Sala que não existe (ninguém dentro): o convite não cria uma sala órfã.
	assert.equal((await open('invite=1&room=abc123')).status, 404);
	assert.equal((await open('room=abc123')).status, 101); // quem abriu pelo matchmaker
	assert.equal((await open('invite=1&room=abc123')).status, 101, 'friend enters by the invite');
	assert.equal(Object.keys(match.match.players).length, 2);
	const leader = [...match.sessions.values()][0];
	match.webSocketMessage([...match.sessions.values()][1], JSON.stringify({ t: 'ready' }));
	match.webSocketMessage(leader, JSON.stringify({ t: 'start' }));
	assert.equal(match.match.phase, 'running');
	assert.equal((await open('invite=1&room=abc123')).status, 409, 'started: refused');
});

test('a code in use cannot be created again; started rooms refuse new players', async () => {
	const match = room();
	const a = await join(match, { create: true });
	assert.equal((await join(match, { create: true })).status, 409);
	say(match, a, { t: 'start' });
	const late = await join(match);
	assert.equal(late.status, 409);
	assert.match(late.text, /já começou/);
});

test('spawn building is random: the first player is not always in the same house', async () => {
	const counts = new Map();
	for (let i = 0; i < 400; i++) {
		const match = room();
		const response = await match.fetch(new Request(`https://internal/join?room=R${i}&name=P&account=spawn${i}&xp=0`, { headers: { Upgrade: 'websocket' } }));
		assert.equal(response.status, 101);
		match.start();
		const human = Object.values(match.match.players).find((p) => !p.bot);
		counts.set(human.spawn, (counts.get(human.spawn) || 0) + 1);
	}
	assert.equal(counts.size, 8, 'all 8 buildings used');
	for (const [building, count] of counts) assert.ok(count > 20 && count < 90, `building ${building} picked ${count}/400`);
	// Team rooms: the side of the map also varies.
	const sides = new Set();
	for (let i = 0; i < 40; i++) {
		const match = room();
		const a = await join(match, { create: true, code: 'SIDE' + (i % 10) });
		say(match, a, { t: 'start' });
		sides.add(match.match.players[a.id].spawn);
	}
	assert.ok(sides.size >= 3, 'team spawns vary between buildings and sides');
});
