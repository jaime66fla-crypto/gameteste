// Construção da Sobrevivência: grade (src/godot-building.js) e regras no
// Durable Object (src/godot-survival.js), com um runtime falso.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

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
	}
	get status() {
		return this.upgraded ? 101 : super.status;
	}
};

const { GodotSurvival } = await import('../src/godot-survival.js');
const { BuildGrid } = await import('../src/godot-building.js');
const world = JSON.parse(readFileSync(new URL('../godot/data/survival_world.json', import.meta.url), 'utf8'));
const catalog = JSON.parse(readFileSync(new URL('../godot/data/survival_items.json', import.meta.url), 'utf8'));
const RULES = catalog.build_rules;
const S = RULES.cell;

function makeWorld(store = new Map()) {
	const ctx = {
		storage: {
			get: async (k) => store.get(k),
			put: async (k, v) => store.set(k, structuredClone(v)),
			delete: async (k) => store.delete(k),
			list: async ({ prefix }) => new Map([...store].filter(([k]) => k.startsWith(prefix))),
			getAlarm: async () => null,
			setAlarm: async () => {},
		},
		blockConcurrencyWhile: (fn) => fn(),
		acceptWebSocket: () => {},
		getWebSockets: () => [],
		waitUntil: () => {},
	};
	const env = { GODOT_ACCOUNTS: { idFromName: () => 'a', get: () => ({ fetch: async () => new RealResponse('{}') }) } };
	return { room: new GodotSurvival(ctx, env), store };
}

let seq = 0;
async function join(room, { account = 'acc' + ++seq, name = 'P' + seq } = {}) {
	const url = `https://internal/join?world=world:1&name=${name}&account=${account}&xp=0`;
	await room.fetch(new Request(url, { headers: { Upgrade: 'websocket' } }));
	const ws = [...room.sessions.values()].at(-1);
	const id = ws.deserializeAttachment().id;
	return { ws, id, me: () => room.state.players[id] };
}
const say = (room, player, data) => room.webSocketMessage(player.ws, JSON.stringify(data));
const at = (player, p) => (player.me().p = [...p]);
const rich = (player) => (player.me().inv = { wood: 200, stone: 100, fiber: 100, rope: 20 });

/** Um canto livre do mapa (sem árvore, rocha, arbusto nem lago) de 5 x 5 células. */
function clearSpot() {
	for (let i = -70; i < 70; i++) {
		for (let j = -70; j < 70; j++) {
			const box = [(i - 1) * S, (j - 1) * S, (i + 4) * S, (j + 4) * S];
			const blocked = world.resources.some((r) => ['tree', 'rock', 'bush'].includes(r.kind) && r.p[0] > box[0] - 2 && r.p[0] < box[2] + 2 && r.p[2] > box[1] - 2 && r.p[2] < box[3] + 2)
				|| world.ponds.some((p) => Math.hypot(p.x - (box[0] + box[2]) / 2, p.z - (box[1] + box[3]) / 2) < p.r + 20)
				|| Math.abs(box[0]) > world.half_size - 20 || Math.abs(box[3]) > world.half_size - 20;
			if (!blocked) return { i, j };
		}
	}
	throw new Error('no clear spot');
}
const SPOT = clearSpot();
/** Fica ao lado da célula (a, b) do canto livre, fora dela. */
const near = (a, b) => [(SPOT.i + a) * S - 1.2, 0, (SPOT.j + b) * S + 1.5];

test('grid: walls need a foundation, floors need walls, removing a foundation drops what it held', () => {
	const g = new BuildGrid(RULES, catalog.builds);
	let n = 0;
	const put = (p) => {
		const err = g.check(p);
		if (!err) g.add({ id: 'p' + ++n, ...p });
		return err;
	};
	assert.match(put({ kind: 'wall', i: 0, j: 0, k: 0, o: 'h' }), /fundação/);
	assert.equal(put({ kind: 'foundation', i: 0, j: 0, k: 0 }), '');
	assert.match(put({ kind: 'foundation', i: 0, j: 0, k: 0 }), /Já tem/);
	assert.equal(put({ kind: 'wall', i: 0, j: 0, k: 0, o: 'h' }), '', 'wall on the foundation edge');
	assert.equal(put({ kind: 'wall', i: 0, j: 1, k: 0, o: 'h' }), '', 'the opposite edge also touches the cell');
	assert.match(put({ kind: 'wall', i: 0, j: 2, k: 0, o: 'h' }), /Precisa/, 'one cell away there is nothing');
	assert.equal(put({ kind: 'floor', i: 0, j: 0, k: 1 }), '', 'ceiling over the walls');
	assert.equal(put({ kind: 'floor', i: 1, j: 0, k: 1 }), '', 'one cell of balcony from a wall-supported floor');
	assert.match(put({ kind: 'floor', i: 2, j: 0, k: 1 }), /Precisa/, 'but not two');
	assert.equal(put({ kind: 'wall', i: 0, j: 0, k: 1, o: 'h' }), '', 'second storey wall over the first');
	assert.match(put({ kind: 'door', i: 0, j: 0, k: 0, o: 'h' }), /parede com porta/);
	const before = g.pieces.size;
	const gone = g.remove('p1'); // a fundação
	assert.equal(gone.length, before, 'everything rested on the single foundation');
	assert.equal(g.pieces.size, 0);
	assert.equal(g.slots.size, 0);
});

test('grid: stairs and floors do not overlap; a roof caps the walls', () => {
	const g = new BuildGrid(RULES, catalog.builds);
	let n = 0;
	const put = (p) => {
		const err = g.check(p);
		if (!err) g.add({ id: 'p' + ++n, ...p });
		return err;
	};
	put({ kind: 'foundation', i: 0, j: 0, k: 0 });
	for (const [o, i, j] of BuildGrid.cellEdges(0, 0)) assert.equal(put({ kind: 'wall', i, j, k: 0, o }), '');
	assert.equal(put({ kind: 'stairs', i: 0, j: 0, k: 0, r: 1 }), '');
	assert.match(put({ kind: 'floor', i: 0, j: 0, k: 1 }), /escada/);
	assert.equal(put({ kind: 'roof', i: 1, j: 0, k: 1, r: 0 }), '', 'roof hangs over the wall like a floor');
	assert.match(put({ kind: 'wall', i: 2, j: 0, k: 1, o: 'v' }), /telhado|Precisa/);
});

test('placing costs materials, needs reach and support, and is seen by everyone', async () => {
	const { room, store } = makeWorld();
	const a = await join(room);
	const b = await join(room);
	at(a, near(0, 0));
	at(b, near(0, 0));
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	assert.match(a.ws.last('note').message, /Falta/, 'no materials');
	rich(a);
	at(a, [0, 0, 0]);
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	assert.match(a.ws.last('note').message, /Longe/);
	at(a, near(0, 0));
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	const placed = b.ws.last('bp').b;
	assert.equal(placed.kind, 'foundation');
	assert.equal(placed.ow, a.me().tag);
	assert.equal(a.me().inv.wood, 200 - catalog.builds.foundation.cost.wood);
	room.flushSave();
	assert.ok(store.get('b:' + placed.id), 'each piece is saved under its own key');
	// O mundo recarregado volta com a peça.
	const { room: again } = makeWorld(store);
	await new Promise(setImmediate);
	assert.equal(again.grid.pieces.size, 1);
	const c = await join(again);
	assert.equal(c.ws.last('start').builds.length, 1);
});

test('no building over trees or someone standing there, nor next to another base', async () => {
	const { room } = makeWorld();
	const a = await join(room);
	const b = await join(room);
	rich(a);
	rich(b);
	const tree = world.resources.find((r) => r.kind === 'tree');
	at(a, [tree.p[0] + 2, 0, tree.p[2]]);
	say(room, a, { t: 'build', kind: 'foundation', i: Math.floor(tree.p[0] / S), j: Math.floor(tree.p[2] / S), k: 0 });
	assert.match(a.ws.last('note').message, /árvore/i);
	at(a, near(0, 0));
	at(b, [(SPOT.i + 0.5) * S, 0, (SPOT.j + 0.5) * S]);
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	assert.match(a.ws.last('note').message, /alguém/);
	at(b, near(3, 3));
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	say(room, b, { t: 'build', kind: 'foundation', i: SPOT.i + 1, j: SPOT.j + 1, k: 0 });
	assert.match(b.ws.last('note').message, /outro jogador/);
	// Liberado pelo dono, constrói junto.
	at(b, a.me().p);
	say(room, a, { t: 'auth_add' });
	assert.deepEqual(a.ws.last('auth').l.map((x) => x.tag), [b.me().tag]);
	assert.deepEqual(b.ws.last('allowed').l, [a.me().tag]);
	say(room, b, { t: 'build', kind: 'wall', i: SPOT.i, j: SPOT.j, k: 0, o: 'v' });
	assert.equal(room.grid.pieces.size, 2);
});

test('players and zombies break pieces; a broken wall drops what it held; the owner repairs after a pause', async () => {
	const { room } = makeWorld();
	const host = await join(room);
	const raider = await join(room);
	rich(host);
	at(host, near(0, 0));
	for (const p of [
		{ kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 },
		{ kind: 'wall', i: SPOT.i, j: SPOT.j, k: 0, o: 'v' },
		{ kind: 'wall', i: SPOT.i, j: SPOT.j, k: 0, o: 'h' },
	]) say(room, host, { t: 'build', ...p });
	const wall = [...room.grid.pieces.values()].find((p) => p.kind === 'wall' && p.j === SPOT.j && p.o === 'v');
	assert.ok(wall, host.ws.last('note')?.message);
	// Jogador com machado de pedra.
	raider.me().inv = { stone_axe: 1 };
	at(raider, [SPOT.i * S - 1, 0, (SPOT.j + 0.5) * S]);
	say(room, raider, { t: 'bhit', b: wall.id, item: 'stone_axe' });
	const hp = catalog.builds.wall.hp - catalog.items.stone_axe.melee * RULES.axe_factor;
	assert.equal(wall.hp, hp);
	assert.equal(host.ws.last('bhp').hp, hp);
	// Zumbi relatado pelo anfitrião: precisa estar encostado.
	room.state.zombies.z1 = { id: 'z1', kind: 'brute', hp: 150, p: [SPOT.i * S - 8, 0, (SPOT.j + 0.5) * S] };
	say(room, host, { t: 'zbhit', z: 'z1', b: wall.id });
	assert.equal(wall.hp, hp, 'too far away');
	room.state.zombies.z1.p = [SPOT.i * S - 0.8, 0, (SPOT.j + 0.5) * S];
	say(room, host, { t: 'zbhit', z: 'z1', b: wall.id });
	assert.equal(wall.hp, hp - 16 * RULES.zombie_factor);
	// Conserto só depois da pausa.
	say(room, host, { t: 'brep', b: wall.id });
	assert.match(host.ws.last('note').message, /Sob ataque/);
	wall.hitAt -= RULES.repair_wait * 1000;
	const wood = host.me().inv.wood;
	say(room, host, { t: 'brep', b: wall.id });
	assert.equal(wall.hp, catalog.builds.wall.hp);
	assert.ok(host.me().inv.wood < wood);
	// Destruir a fundação derruba as paredes.
	const foundation = [...room.grid.pieces.values()].find((p) => p.kind === 'foundation');
	room.damageBuild(foundation, 99999, raider.id);
	assert.equal(room.grid.pieces.size, 0);
	assert.equal(raider.ws.last('bgone').l.length, 3);
});

test('doors open only for the owner and friends; chests store and spill when destroyed', async () => {
	const { room } = makeWorld();
	const a = await join(room);
	const b = await join(room);
	rich(a);
	at(a, near(0, 0));
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	say(room, a, { t: 'build', kind: 'doorway', i: SPOT.i, j: SPOT.j, k: 0, o: 'v' });
	say(room, a, { t: 'build', kind: 'door', i: SPOT.i, j: SPOT.j, k: 0, o: 'v' });
	const door = [...room.grid.pieces.values()].find((p) => p.kind === 'door');
	assert.ok(door, a.ws.last('note')?.message);
	at(b, a.me().p);
	b.me().p[2] += 4; // fora do alcance do "liberar" (6 m) não: ainda perto da porta
	say(room, b, { t: 'door', b: door.id });
	assert.match(b.ws.last('note').message, /trancada/);
	say(room, a, { t: 'door', b: door.id });
	assert.equal(b.ws.last('bp').b.open, true);
	// Baú em cima da fundação.
	const top = RULES.base;
	const chestAt = [(SPOT.i + 0.5) * S, top, (SPOT.j + 0.5) * S];
	say(room, a, { t: 'build', kind: 'chest', p: chestAt, y: 0 });
	const chest = [...room.grid.pieces.values()].find((p) => p.kind === 'chest');
	assert.ok(chest, a.ws.last('note')?.message);
	at(a, [chestAt[0] + 1, top, chestAt[2]]);
	say(room, a, { t: 'store', k: chest.id, item: 'stone', n: 10 });
	assert.equal(a.ws.last('container').items.stone, 10);
	a.me().inv = {}; // bolsos vazios para caber o que vai sair do baú
	say(room, a, { t: 'take', k: chest.id, item: 'stone', n: 4 });
	assert.equal(a.me().inv.stone, 4);
	assert.equal(chest.items.stone, 6);
	// Sem a fundação o baú cai e o que tinha vira mochila no chão.
	room.damageBuild([...room.grid.pieces.values()].find((p) => p.kind === 'foundation'), 99999, b.id);
	assert.equal(room.grid.pieces.size, 0);
	assert.ok(Object.values(room.state.bags).some((bag) => bag.items.stone === 6));
});

test('the bed is a respawn point with a cooldown; only one bed each', async () => {
	const { room } = makeWorld();
	const a = await join(room);
	rich(a);
	at(a, near(0, 0));
	const spot = [(SPOT.i - 1) * S, 0, (SPOT.j + 0.5) * S];
	say(room, a, { t: 'build', kind: 'bed', p: spot, y: 0 });
	assert.equal(room.grid.pieces.size, 1, a.ws.last('note')?.message);
	say(room, a, { t: 'build', kind: 'bed', p: [spot[0], 0, spot[2] + 3], y: 0 });
	assert.match(a.ws.last('note').message, /já tem uma cama/);
	room.damagePlayer(a.me(), 500, 'x', 'zombie');
	a.me().respawnAt = 0;
	say(room, a, { t: 'respawn', bed: true });
	assert.equal(a.me().dead, false);
	assert.ok(Math.hypot(a.me().p[0] - spot[0], a.me().p[2] - spot[2]) < 0.5, 'woke up at the bed');
	room.damagePlayer(a.me(), 500, 'x', 'zombie');
	a.me().respawnAt = 0;
	say(room, a, { t: 'respawn', bed: true });
	assert.equal(a.me().dead, true);
	assert.match(a.ws.last('note').message, /não está pronta/);
	say(room, a, { t: 'respawn' });
	assert.equal(a.me().dead, false, 'a clearing still works');
});

test('only the owner demolishes, getting part of the material back', async () => {
	const { room } = makeWorld();
	const a = await join(room);
	const b = await join(room);
	rich(a);
	at(a, near(0, 0));
	at(b, near(0, 0));
	say(room, a, { t: 'build', kind: 'foundation', i: SPOT.i, j: SPOT.j, k: 0 });
	const id = [...room.grid.pieces.keys()][0];
	say(room, b, { t: 'bdel', b: id });
	assert.match(b.ws.last('note').message, /dono/);
	a.me().inv = {}; // bolsos vazios: o material devolvido cabe
	say(room, a, { t: 'bdel', b: id });
	assert.equal(room.grid.pieces.size, 0);
	assert.equal(a.me().inv.wood, Math.floor(catalog.builds.foundation.cost.wood * RULES.refund));
});
