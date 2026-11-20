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
/** One round: `killer` takes out every living player of `team`; then the break ends (alarm). */
async function winRound(match, killerId, team) {
	const nextRound = async () => {
		if (match.match.phase !== 'between') return;
		match.match.nextRoundAt = 0;
		await match.alarm();
	};
	await nextRound(); // still in the break after a round won by hand
	const m = match.match;
	for (const p of Object.values(m.players)) if (p.team === team && !p.dead) match.damage(m.players[killerId], p, 999, 'rifle', 'chest');
	await nextRound();
}

test('punches deal damage up close, not from afar, not too fast and never to a teammate', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'team', team: 0 }); // A e B na mesma equipe
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	const bot = Object.values(m.players).find((p) => p.bot && p.team === 1);
	m.players[a.id].p = [0, 0, 0];
	m.players[b.id].p = [1, 0, 0];
	bot.p = [1.5, 0, 0];
	say(match, a, { t: 'melee', target: bot.id, zone: 'chest' });
	assert.equal(bot.hp, 85, 'punch: 15 damage');
	say(match, a, { t: 'melee', target: bot.id, zone: 'chest' });
	assert.equal(bot.hp, 85, 'too fast: ignored');
	m.players[a.id].lastPunch = 0;
	say(match, a, { t: 'melee', target: bot.id, zone: 'head' });
	assert.equal(bot.hp, 62.5, 'head: x1.5');
	m.players[a.id].lastPunch = 0;
	bot.p = [10, 0, 0];
	say(match, a, { t: 'melee', target: bot.id, zone: 'chest' });
	assert.equal(bot.hp, 62.5, 'too far');
	m.players[a.id].lastPunch = 0;
	say(match, a, { t: 'melee', target: b.id, zone: 'chest' });
	assert.equal(m.players[b.id].hp, 100, 'no friendly fire');
});

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
	// Wipe out Bravo's bots: Alfa takes round 1, the match goes on.
	const bots = start.roster.filter((r) => r.team === 1).map((r) => r.id);
	for (const bot of bots) for (let i = 0; i < 4; i++) say(match, a, { t: 'hit', target: bot, zone: 'chest', w: 'rifle' });
	const roundEnd = b.ws.last('round_end');
	assert.deepEqual([roundEnd.round, roundEnd.team, roundEnd.score, roundEnd.last], [1, 0, [1, 0], false]);
	assert.equal(b.ws.last('end'), undefined, 'one round is not the match');
	assert.equal(m.phase, 'between');
	// Two more rounds for Alfa: 3 x 0 ends the best of 5.
	await winRound(match, a.id, 1);
	assert.deepEqual(b.ws.last('round').score, [2, 0]);
	await winRound(match, a.id, 1);
	await winRound(match, a.id, 1);
	const end = b.ws.last('end');
	assert.ok(end, 'match ended');
	assert.equal(end.team, 0);
	assert.equal(end.name, 'Equipe Alfa');
	assert.deepEqual(end.rounds, [3, 0]);
	assert.equal(end.round, 3);
	assert.equal(m.phase, 'finished');
});

test('rounds: best of 5 with score, break, everyone back at base, survivors keep gear, shop reopens', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'ready' }); // A on Alfa, B on Bravo, each with a bot
	say(match, a, { t: 'start' });
	const start = a.ws.last('start');
	assert.deepEqual(start.rounds, { round: 1, total: 5, toWin: 3, score: [0, 0], length: 150000 });
	assert.equal(start.duration, 150000, 'the timer is one round');
	const m = match.match;
	const me = m.players[a.id];
	me.inv = { rifle: true };
	const spawnBefore = me.p;
	// Round 1: Alfa wins.
	for (const p of Object.values(m.players)) if (p.team === 1) match.damage(me, p, 999, 'rifle', 'chest');
	assert.equal(m.phase, 'between');
	const credits = b.ws.last('credits');
	assert.deepEqual([credits.amount, credits.round], [800, true], 'losers get more credits');
	assert.equal(a.ws.last('credits').amount, 500);
	// During the break nothing counts.
	say(match, b, { t: 'hit', target: a.id, zone: 'head', w: 'rifle' });
	assert.equal(me.hp, 100);
	m.nextRoundAt = 0;
	await match.alarm();
	const round = b.ws.last('round');
	assert.deepEqual([round.round, round.total, round.score], [2, 5, [1, 0]]);
	assert.equal(round.buy, 30000);
	assert.equal(m.phase, 'running');
	assert.ok(Object.values(m.players).every((p) => !p.dead && p.hp === 100), 'everyone back');
	assert.deepEqual(me.inv, { rifle: true }, 'survivor keeps the rifle');
	assert.ok(round.roster.find((r) => r.id === b.id).revived, 'B came back');
	assert.ok(round.roster.every((r) => Array.isArray(r.sp)));
	assert.ok(spawnBefore, 'had a spawn');
	assert.ok(m.players[b.id].buyUntil > Date.now(), 'shop reopens');
	// Rounds 2-3 for Bravo, 4 for Alfa: 2 x 2, the 5th decides.
	await winRound(match, b.id, 0);
	await winRound(match, b.id, 0);
	await winRound(match, a.id, 1);
	assert.deepEqual(m.roundWins, [2, 2]);
	assert.equal(match.match.round, 5);
	await winRound(match, b.id, 0);
	const end = a.ws.last('end');
	assert.deepEqual([end.team, end.rounds, end.round, end.reason], [1, [2, 3], 5, 'rounds']);
	// Back in the room afterwards.
	assert.equal(match.match.phase, 'waiting');
});

test('bot hits deal the same damage as player weapons (weapon × zone), only with a weapon the bot has', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'team', team: 0 });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	const bot = Object.values(m.players).find((p) => p.bot && p.team === 1);
	bot.inv = { sniper: true };
	say(match, a, { t: 'hit', bot: bot.id, target: b.id, zone: 'chest', w: 'rifle' });
	assert.equal(m.players[b.id].hp, 100, 'weapon the bot does not have');
	say(match, a, { t: 'hit', bot: bot.id, target: b.id, zone: 'leg', w: 'sniper' });
	assert.equal(m.players[b.id].hp, 100 - 95 * 0.7);
	bot.inv = { pistol: true };
	m.players[a.id].hp = 100;
	say(match, a, { t: 'hit', bot: bot.id, target: a.id, zone: 'head', w: 'pistol' });
	assert.equal(m.players[a.id].hp, 100 - 22 * 2);
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
	// Alfa (A) wipes out Bravo (B + 3 bots) three rounds in a row.
	for (let round = 0; round < 3; round++) await winRound(match, a.id, 1);
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

test('no loot crates; medkits are bought, stack, and F (heal) uses one', async () => {
	const match = room();
	const a = await join(match, { create: true });
	const b = await join(match);
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const start = a.ws.last('start');
	assert.deepEqual(start.crates, [], 'no crates in team matches');
	const m = match.match;
	const me = m.players[a.id];
	// Buy two kits at full health: they go to the inventory.
	say(match, a, { t: 'buy', item: 'medkit' });
	say(match, a, { t: 'buy', item: 'medkit' });
	assert.equal(me.medkits, 2);
	assert.equal(me.credits, 200);
	assert.equal(me.hp, 100);
	assert.equal(b.ws.last('medkits').count, 2);
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
	// Dying loses the carried kits; nothing drops on the ground.
	me.medkits = 3;
	const bot = Object.values(m.players).find((p) => p.bot && p.team !== me.team);
	match.damage(bot, me, 999, 'rifle', 'chest');
	assert.equal(me.medkits, 0);
	assert.equal(b.ws.last('crate'), undefined, 'no drop crate');
});

test('shop: buy within the window, with credits, one of each weapon, carry limits', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	const me = m.players[a.id];
	const start = a.ws.last('start');
	assert.equal(start.shop.credits, 800);
	assert.equal(start.shop.window, 120000);
	assert.equal(start.shop.prices.rifle, 2200);
	assert.deepEqual(me.inv, {}, 'team rooms start unarmed');
	say(match, a, { t: 'buy', item: 'rifle' });
	assert.equal(a.ws.last('buy_denied').message, 'Créditos insuficientes');
	say(match, a, { t: 'buy', item: 'pistol' });
	assert.ok(me.inv.pistol);
	assert.equal(me.credits, 600);
	const bought = b.ws.last('bought');
	assert.deepEqual([bought.by, bought.item, bought.ammo], [a.id, 'pistol', 90], 'everyone hears about it');
	say(match, a, { t: 'buy', item: 'pistol' });
	assert.equal(a.ws.last('buy_denied').message, 'Você já tem essa arma');
	say(match, a, { t: 'buy', item: 'bazooka' });
	assert.equal(a.ws.last('buy_denied').message, 'Item inválido');
	me.credits = 5000;
	for (let i = 0; i < 4; i++) say(match, a, { t: 'buy', item: 'grenade' });
	assert.equal(me.nades, 3);
	assert.equal(a.ws.last('buy_denied').message, 'Limite de granadas');
	// Bought weapons can deal damage; a weapon you do not have cannot.
	const bot = Object.values(m.players).find((p) => p.bot && p.team !== me.team);
	me.p = [0, 0, 0];
	bot.p = [5, 0, 0];
	say(match, a, { t: 'hit', target: bot.id, zone: 'chest', w: 'sniper', pt: [5, 1.3, 0] });
	assert.equal(bot.hp, 100);
	say(match, a, { t: 'hit', target: bot.id, zone: 'chest', w: 'pistol', pt: [5, 1.3, 0] });
	assert.ok(bot.hp < 100);
	// After 2 minutes the shop closes.
	me.buyUntil = Date.now() - 1;
	say(match, a, { t: 'buy', item: 'smg' });
	assert.equal(a.ws.last('buy_denied').message, 'Tempo de compra encerrado');
	assert.equal(me.inv.smg, undefined);
});

test('team rooms: bots buy with the same credits; kills earn credits (player 400, bot 200, +100 head)', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	const start = a.ws.last('start');
	for (const entry of start.roster.filter((r) => r.bot)) {
		assert.ok(entry.w && m.players[entry.id].inv[entry.w], 'roster tells clients the bot weapon');
		assert.equal(entry.w, 'pistol', '800 credits only buy a pistol');
		assert.equal(entry.medkits, 1);
		assert.equal(m.players[entry.id].credits, 800 - 200 - 300, 'pistol + medkit paid from the bot credits');
	}
	const me = m.players[a.id];
	const enemyBot = Object.values(m.players).find((p) => p.bot && p.team !== me.team);
	match.damage(me, enemyBot, 999, 'pistol', 'head');
	assert.equal(me.credits, 1100);
	assert.deepEqual([a.ws.last('credits').amount, a.ws.last('credits').head], [300, true]);
	if (m.players[b.id].team !== me.team) {
		match.damage(me, m.players[b.id], 999, 'pistol', 'chest');
		assert.equal(me.credits, 1500 + 500, 'kill (400) + round won (500): Bravo is out');
	}
});

test('grenades: bought, thrown, server-checked blast with falloff, no team damage, self damage without kill credit', async () => {
	const match = room();
	const a = await join(match, { create: true, name: 'A' });
	const b = await join(match, { name: 'B' });
	say(match, b, { t: 'ready' });
	say(match, a, { t: 'start' });
	const m = match.match;
	const me = m.players[a.id];
	say(match, a, { t: 'buy', item: 'grenade' });
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
