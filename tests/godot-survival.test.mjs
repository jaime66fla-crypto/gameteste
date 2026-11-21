// Modo Sobrevivência (src/godot-survival.js) com um runtime falso de Durable Object.
// Mundo de floresta: nada para saquear, tudo é coletado e fabricado; zumbis só à noite.
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

const { GodotSurvival, CAPACITY, WORLD_VERSION, carryLimit, inventoryWeight } = await import('../src/godot-survival.js');
const world = JSON.parse(readFileSync(new URL('../godot/data/survival_world.json', import.meta.url), 'utf8'));
const catalog = JSON.parse(readFileSync(new URL('../godot/data/survival_items.json', import.meta.url), 'utf8'));
const DAY_MS = 24 * 60 * 1000;

function makeWorld(saved) {
	const store = new Map();
	if (saved) store.set('world', saved);
	const ctx = {
		storage: {
			get: async (k) => store.get(k),
			put: async (k, v) => store.set(k, structuredClone(v)),
			getAlarm: async () => null,
			setAlarm: async () => {},
			deleteAll: async () => store.clear(),
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
	const response = await room.fetch(new Request(url, { headers: { Upgrade: 'websocket' } }));
	if (response.status !== 101) return { status: response.status };
	const ws = [...room.sessions.values()].at(-1);
	const id = ws.deserializeAttachment().id;
	return { status: 101, ws, id, me: () => room.state.players[id] };
}
const say = (room, player, data) => room.webSocketMessage(player.ws, JSON.stringify(data));
const at = (player, p) => (player.me().p = [...p]);
/** Hora do jogo: o dia começa às 6h (createdAt = 6h). */
const setHour = (room, hour) => (room.state.createdAt = Date.now() - (((hour - 6 + 24) % 24) / 24) * DAY_MS);

test('living trees drop collectible branches naturally, without tools or unlimited piles', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const tree = world.resources.find((r) => r.kind === 'tree');
	at(p, tree.p);
	assert.equal(typeof room.dropTreeBranches, 'function');
	const now = Date.now();
	room.state.branchNext = { [tree.id]: now - 1 };
	room.dropTreeBranches(now);
	const branch = Object.values(room.state.branches).find((r) => r.tree === tree.id);
	assert.ok(branch, 'a branch fell beside the tree');
	assert.equal(branch.kind, 'stick');
	assert.ok(Math.hypot(branch.p[0] - tree.p[0], branch.p[2] - tree.p[2]) > 1);
	const count = Object.values(room.state.branches).filter((r) => r.tree === tree.id).length;
	room.dropTreeBranches(now + 5000);
	assert.equal(Object.values(room.state.branches).filter((r) => r.tree === tree.id).length, count, 'one branch per tree');
	assert.ok(room.startPacket(p.me()).branches.some((r) => r.id === branch.id), 'late join receives fallen branches');
	at(p, branch.p);
	gather(room, p, branch);
	assert.ok(p.me().inv.stick > 0, 'empty hands can collect the branch');
	assert.ok(!room.state.branches[branch.id], 'collected branch is removed');
	assert.ok(p.ws.sent.some((m) => m.t === 'branch_gone' && m.id === branch.id));
	room.dropTreeBranches(now + 160000);
	assert.ok(room.state.branches[branch.id], 'another branch falls after the natural interval');
});

test('cut trees do not shed branches; natural drops expire and have a global cap', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const tree = world.resources.find((r) => r.kind === 'tree');
	at(p, tree.p);
	assert.equal(typeof room.dropTreeBranches, 'function');
	const now = Date.now();
	room.state.branchNext = { [tree.id]: now - 1 };
	room.state.depleted[tree.id] = now + 600000;
	room.dropTreeBranches(now);
	assert.ok(!Object.values(room.state.branches).some((r) => r.tree === tree.id));
	room.state.branches.expired = { id: 'expired', tree: tree.id, p: tree.p, expires: now - 1 };
	room.dropTreeBranches(now);
	assert.ok(!room.state.branches.expired);
	room.state.branches = {};
	for (let i = 0; i < 64; i++) room.state.branches['cap' + i] = { id: 'cap' + i, p: tree.p, expires: now + 999999 };
	delete room.state.depleted[tree.id];
	room.dropTreeBranches(now);
	assert.equal(Object.keys(room.state.branches).length, 64);
});

test('branch placement respects foundation corners and free furniture footprints', () => {
	const { room } = makeWorld();
	room.grid.add({ id: 'base', kind: 'foundation', i: 0, j: 0, k: 0 });
	assert.equal(typeof room.branchBlocked, 'function');
	assert.equal(room.branchBlocked([2.95, 0.025, 2.95]), true);
	assert.equal(room.branchBlocked([8, 0.025, 8]), false);
	room.grid.add({ id: 'chest', kind: 'chest', p: [8, 0, 8] });
	assert.equal(room.branchBlocked([8, 0.025, 8]), true);
});

test('refill notifies players that an emptied map container is available again', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const spot = world.containers[0];
	room.state.containers[spot.id] = { items: {}, refillAt: Date.now() - 1 };
	assert.equal(typeof room.refreshContainers, 'function');
	room.refreshContainers(Date.now());
	assert.ok(!room.state.containers[spot.id], 'search will roll fresh loot');
	assert.ok(p.ws.sent.some((m) => m.t === 'refilled' && m.k === spot.id));
});
/** Segura E no recurso pelo tempo da regra e solta. */
function gather(room, p, res) {
	say(room, p, { t: 'gather_start', r: res.id });
	p.me().gatherAt -= catalog.resources[res.kind].time * 1000;
	say(room, p, { t: 'gather', r: res.id });
}

test('world data: nature plus three abandoned cities; every resource kind has a rule, recipes use known items', () => {
	assert.equal(world.spawns.length, 16);
	assert.equal(world.towns.length, 3);
	for (const key of ['containers', 'buildings', 'roads']) assert.ok(world[key].length > 0, key);
	for (const c of world.containers) assert.ok(catalog.loot[c.type], `loot table ${c.type}`);
	for (const table of Object.values(catalog.loot)) for (const [item] of table.table) assert.ok(catalog.items[item] && !catalog.items[item].soon, `loot ${item}`);
	for (const v of world.vehicles) assert.ok(catalog.vehicles[v.kind], v.kind);
	// Cidades nas pontas da área original; as montanhas ampliam a borda do mundo.
	for (const t of world.towns) {
		assert.ok(Math.hypot(...t.center) > (world.core_half_size ?? world.half_size) * 0.6, `${t.name} far from the middle`);
		for (const [x, z] of world.spawns) assert.ok(Math.hypot(x - t.center[0], z - t.center[1]) > 50, `spawn away from ${t.name}`);
	}
	assert.ok(world.resources.filter((r) => r.kind === 'car').length > world.vehicles.length * 10, 'wrecks far outnumber working cars');
	for (const r of world.resources) assert.ok(catalog.resources[r.kind], r.kind);
	for (const kind of ['tree', 'rock', 'bush', 'stick', 'pebble', 'fiber', 'herb', 'pond']) {
		assert.ok(world.resources.some((r) => r.kind === kind), `map has ${kind}`);
	}
	for (const recipe of catalog.recipes) {
		for (const item of Object.keys(recipe.needs)) assert.ok(catalog.items[item], item);
		assert.ok(catalog.items[recipe.gives[0]], recipe.gives[0]);
	}
	for (const rule of Object.values(catalog.resources)) if (rule.gives) assert.ok(catalog.items[rule.gives], rule.gives);
	// Toda ferramenta exigida pode ser fabricada só com o que se acha no chão.
	for (const rule of Object.values(catalog.resources)) {
		if (!rule.needs) continue;
		const tool = Object.entries(catalog.items).find(([, item]) => item.tool === rule.needs)[0];
		assert.ok(catalog.recipes.some((r) => r.gives[0] === tool), `recipe for ${tool}`);
	}
	// Cada nascimento fica perto de um lago.
	for (const [x, z] of world.spawns) {
		assert.ok(world.ponds.some((p) => Math.hypot(p.x - x, p.z - z) < p.r + 40), `water near spawn ${x},${z}`);
	}
});

test('joining spawns at once with empty hands; 16 players fill a world', async () => {
	const { room } = makeWorld();
	const first = await join(room);
	assert.equal(first.status, 101);
	const start = first.ws.last('start');
	assert.equal(start.survival, true);
	assert.equal(start.host, first.id);
	assert.deepEqual(start.you.inv, {});
	assert.equal(start.vehicles.length, world.vehicles.length, 'the rare working cars are sent');
	assert.equal(world.vehicles.length, world.towns.length, 'one working car per city');
	for (let i = 1; i < CAPACITY; i++) assert.equal((await join(room)).status, 101);
	assert.equal((await join(room)).status, 409);
});

test('a world saved by the old version (city, loot, cars) starts over as the forest', async () => {
	const old = { name: 'world:1', createdAt: 1, players: {}, chars: { velho: { p: [1, 0, 1], inv: { w_rifle: 1 }, savedAt: Date.now() } }, host: null, zombies: {}, zSeq: 0, containers: {}, bags: {}, bagSeq: 0, depleted: {}, vehicles: { v0: {} } };
	const { room } = makeWorld(old);
	await new Promise(setImmediate); // o construtor carrega o mundo salvo de forma assíncrona
	assert.equal(room.state.version, WORLD_VERSION);
	assert.deepEqual(room.state.chars, {});
	const p = await join(room, { account: 'velho' });
	assert.deepEqual(p.me().inv, {}, 'old character with guns is gone');
	const { room: kept } = makeWorld(structuredClone(room.state));
	await new Promise(setImmediate);
	assert.equal(kept.state.name, 'world:1', 'a world of this version is kept');
	assert.ok(kept.state.players[p.id]);
});

test('safe start: joining clears nearby zombies (unless someone else is fighting them); bites need contact', async () => {
	const { room } = makeWorld();
	const host = await join(room);
	at(host, [200, 0, 200]);
	room.state.zombies.zn = { id: 'zn', kind: 'walker', hp: 60, p: [201, 0, 200] }; // brigando com o host
	const p = await join(room);
	const sp = p.me().p;
	room.state.zombies.zc = { id: 'zc', kind: 'walker', hp: 60, p: [sp[0] + 5, 0, sp[2]] };
	room.clearZombiesNear(sp, p.id);
	assert.equal(room.state.zombies.zc, undefined, 'zombie next to the spawn is gone');
	assert.ok(room.state.zombies.zn, 'zombie fighting another player stays');
	at(p, [0, 0, 0]);
	room.state.zombies.zb = { id: 'zb', kind: 'walker', hp: 60, p: [3, 0, 0] };
	say(room, host, { t: 'zhit', z: 'zb', target: p.id });
	assert.equal(p.me().hp, 100, '3 m is out of reach');
	room.state.zombies.zb.p = [1.2, 0, 0];
	say(room, host, { t: 'zhit', z: 'zb', target: p.id });
	assert.ok(p.me().hp < 100, 'in contact it bites');
});

test('lying down (prone) reaches the other players, so they do not see you standing', async () => {
	const { room } = makeWorld();
	const a = await join(room);
	const b = await join(room);
	at(a, [0, 0, 0]);
	at(b, [3, 0, 0]);
	say(room, a, { t: 's', p: [0, 0, 0], y: 0, c: true, pr: true });
	assert.equal(b.ws.last('s').pr, true);
	say(room, a, { t: 's', p: [0, 0, 0], y: 0 });
	assert.equal(b.ws.last('s').pr, false);
});

test('weight limit: pockets only, the fiber bag raises it once equipped', async () => {
	assert.equal(carryLimit(''), catalog.carry_base);
	assert.equal(carryLimit('sack_bag'), catalog.carry_base + catalog.items.sack_bag.carry);
	assert.equal(inventoryWeight({ wood: 3, stone: 1 }), 3 + catalog.items.stone.weight);
	const { room } = makeWorld();
	const p = await join(room);
	const startingWood = catalog.carry_base - 1;
	p.me().inv = { sack_bag: 1, wood: startingWood };
	const tree = world.resources.find((r) => r.kind === 'tree');
	at(p, tree.p);
	p.me().inv.stone_axe = 1;
	gather(room, p, tree);
	assert.match(p.ws.last('note').message, /Peso demais/, 'pockets are full');
	say(room, p, { t: 'equip', item: 'sack_bag' });
	assert.equal(p.me().back, 'sack_bag');
	assert.equal(p.ws.last('inv').cap, catalog.carry_base + catalog.items.sack_bag.carry);
	const tree2 = world.resources.filter((r) => r.kind === 'tree')[1];
	at(p, tree2.p);
	gather(room, p, tree2);
	assert.ok(p.me().inv.wood > startingWood, 'more room with the bag on');
	room.damagePlayer(p.me(), 500, 'z1', 'zombie');
	assert.equal(Object.values(room.state.bags)[0].items.sack_bag, 1, 'equipped bag drops on death');
});

test('ground pickups need no tool; trees and rocks need the stone axe / pick', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const stick = world.resources.find((r) => r.kind === 'stick');
	at(p, stick.p);
	say(room, p, { t: 'gather', r: stick.id });
	assert.deepEqual(p.me().inv, {}, 'no instant gather');
	gather(room, p, stick);
	assert.ok(p.me().inv.stick >= 1);
	assert.ok(room.state.depleted[stick.id] > Date.now());
	gather(room, p, stick);
	assert.match(p.ws.last('note').message, /Já foi coletado/);

	const tree = world.resources.find((r) => r.kind === 'tree');
	at(p, tree.p);
	gather(room, p, tree);
	assert.match(p.ws.last('note').message, /machado de pedra/);
	assert.equal(p.me().inv.wood, undefined);
	assert.equal(room.state.depleted[tree.id], undefined, 'a failed chop does not use the tree');
	p.me().inv.stone_axe = 1;
	gather(room, p, tree);
	assert.ok(p.me().inv.wood >= 2);

	const rock = world.resources.find((r) => r.kind === 'rock');
	at(p, rock.p);
	gather(room, p, rock);
	assert.match(p.ws.last('note').message, /picareta de pedra/);
	p.me().inv.stone_pick = 1;
	gather(room, p, rock);
	assert.ok(p.me().inv.stone >= 3);

	const fiber = world.resources.find((r) => r.kind === 'fiber');
	at(p, fiber.p);
	gather(room, p, fiber);
	const plain = p.me().inv.fiber;
	assert.ok(plain >= 2 && plain <= 3);
	p.me().inv.stone_knife = 1;
	const fiber2 = world.resources.filter((r) => r.kind === 'fiber')[1];
	at(p, fiber2.p);
	gather(room, p, fiber2);
	assert.ok(p.me().inv.fiber - plain >= 4, 'the knife cuts more fiber');
});

test('a pond quenches thirst from its shore and never runs out', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const pond = world.resources.find((r) => r.kind === 'pond');
	at(p, [pond.p[0] + pond.r + 2, 0, pond.p[2]]);
	p.me().thirst = 20;
	gather(room, p, pond);
	assert.equal(p.me().thirst, 20 + catalog.resources.pond.drink);
	assert.equal(room.state.depleted[pond.id], undefined);
	gather(room, p, pond);
	assert.equal(p.me().thirst, 20 + 2 * catalog.resources.pond.drink);
	assert.ok(p.ws.last('stats'));
	at(p, [pond.p[0] + pond.r + 6, 0, pond.p[2]]);
	gather(room, p, pond);
	assert.equal(p.me().thirst, 20 + 2 * catalog.resources.pond.drink, 'too far from the water');
});

test('from nothing to a stone axe: sticks, pebbles and fiber are enough', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	say(room, p, { t: 'craft', recipe: 'stone_axe' });
	assert.match(p.ws.last('note').message, /Falta/);
	p.me().inv = { stick: 2, stone: 2, fiber: 4 };
	say(room, p, { t: 'craft', recipe: 'stone_axe' });
	assert.match(p.ws.last('note').message, /Falta Corda/);
	say(room, p, { t: 'craft', recipe: 'rope' });
	say(room, p, { t: 'craft', recipe: 'stone_axe' });
	assert.deepEqual(p.me().inv, { stone_axe: 1 });
});

test('manual catalog: eras, stations and "soon" entries are consistent', () => {
	const eraIds = catalog.eras.map((e) => e.id);
	for (const recipe of catalog.recipes) {
		assert.ok(eraIds.includes(recipe.era), `${recipe.id} has a known era`);
		if (recipe.station) assert.ok(catalog.builds[recipe.station]?.station, `${recipe.id} station ${recipe.station}`);
		// Receita que já vale no jogo não pode pedir nem dar coisa que ainda não existe.
		if (!recipe.soon && !catalog.builds[recipe.station]?.soon) {
			for (const item of [...Object.keys(recipe.needs), recipe.gives[0]]) assert.ok(!catalog.items[item].soon, `${recipe.id} uses soon item ${item}`);
		}
	}
	for (const [kind, def] of Object.entries(catalog.builds)) {
		for (const item of Object.keys(def.cost)) {
			assert.ok(catalog.items[item], `${kind} cost ${item}`);
			if (!def.soon) assert.ok(!catalog.items[item].soon, `${kind} costs soon item ${item}`);
		}
	}
	// Todo item que existe no jogo tem de onde vir (coleta, caça ou receita que já vale).
	const reachable = new Set();
	for (const rule of Object.values(catalog.resources)) {
		if (rule.gives) reachable.add(rule.gives);
		if (rule.extra) reachable.add(rule.extra[0]);
		for (const [item] of rule.extras || []) reachable.add(item);
	}
	for (const table of Object.values(catalog.loot)) for (const [item] of table.table) reachable.add(item);
	reachable.add('zombie_gland'); // cai dos zumbis
	for (const animal of Object.values(catalog.animals)) for (const item of Object.keys(animal.loot)) reachable.add(item);
	for (const recipe of catalog.recipes) if (!recipe.soon && !catalog.builds[recipe.station]?.soon) reachable.add(recipe.gives[0]);
	for (const [id, item] of Object.entries(catalog.items)) if (!item.soon) assert.ok(reachable.has(id), `${id} can be obtained`);
	for (const kind of ['ore', 'saltpeter']) assert.ok(world.resources.some((r) => r.kind === kind), `map has ${kind}`);
});

test('stations: workbench must be near, the forge must be lit; soon recipes and builds are refused', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [20, 0, 20]);
	p.me().inv = { hide: 6, rope: 4, iron_ore: 2, charcoal: 1, scrap: 3 };
	say(room, p, { t: 'craft', recipe: 'leather_vest' });
	assert.match(p.ws.last('note').message, /perto de uma bancada/);
	room.grid.add({ id: 'W1', kind: 'workbench', p: [21, 0, 20], y: 0, hp: 250, ow: 'x' });
	say(room, p, { t: 'craft', recipe: 'leather_vest' });
	assert.equal(p.me().inv.leather_vest, 1);

	say(room, p, { t: 'craft', recipe: 'iron_bar' });
	assert.match(p.ws.last('note').message, /forja acesa/);
	room.grid.add({ id: 'G1', kind: 'forge', p: [19, 0, 20], y: 0, hp: 400, ow: p.me().tag, on: false });
	say(room, p, { t: 'craft', recipe: 'iron_bar' });
	assert.match(p.ws.last('note').message, /forja acesa/, 'cold forge does not smelt');
	say(room, p, { t: 'fire', b: 'G1' });
	assert.equal(room.grid.pieces.get('G1').on, true, 'E lights the forge');
	assert.equal(room.buildPacket(room.grid.pieces.get('G1')).on, true);
	say(room, p, { t: 'craft', recipe: 'iron_bar' });
	assert.equal(p.me().inv.iron_bar, 1);

	p.me().inv.glass = 1;
	p.me().inv.gasoline = 1;
	p.me().inv.cloth = 1;
	p.me().inv.charcoal = 1;
	say(room, p, { t: 'craft', recipe: 'molotov' });
	assert.match(p.ws.last('note').message, /ainda não existe/);
	assert.equal(p.me().inv.glass, 1);
	say(room, p, { t: 'craft', recipe: 'scrap_iron' });
	assert.equal(p.me().inv.iron_bar, 2, 'scrap melts into iron at the forge');
});

test('cities: crowbar strips old cars into scrap and parts; containers hold city loot', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const car = world.resources.find((r) => r.kind === 'car');
	at(p, car.p);
	gather(room, p, car);
	assert.match(p.ws.last('note').message, /pé de cabra/);
	p.me().inv = { crowbar: 1 };
	gather(room, p, car);
	assert.ok(p.me().inv.scrap >= 2, 'scrap from the wreck');
	let parts = 0;
	for (const wreck of world.resources.filter((r) => r.kind === 'car').slice(1, 12)) {
		at(p, wreck.p);
		p.me().inv = { crowbar: 1 };
		gather(room, p, wreck);
		parts += Object.keys(p.me().inv).filter((k) => !['crowbar', 'scrap'].includes(k)).length;
	}
	assert.ok(parts > 0, 'wrecks also give parts, rubber, glass...');
	const box = world.containers.find((c) => c.type === 'gun_locker');
	assert.ok(box, 'a police station has a gun locker');
});

test('manual pages teach page recipes for good; without one the workshop refuses', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [20, 0, 20]);
	room.grid.add({ id: 'O1', kind: 'workshop', p: [21, 0, 20], y: 0, hp: 500, ow: 'x' });
	p.me().inv = { gunpowder: 4, scrap: 4 };
	say(room, p, { t: 'craft', recipe: 'ammo_9mm' });
	assert.match(p.ws.last('note').message, /página do manual/);
	const pages = catalog.recipes.filter((r) => r.page && !r.soon);
	p.me().inv.manual_page = pages.length + 1;
	for (let i = 0; i < pages.length; i++) say(room, p, { t: 'use', item: 'manual_page' });
	assert.deepEqual([...p.me().known].sort(), pages.map((r) => r.id).sort());
	assert.deepEqual(p.ws.last('inv').known.length, pages.length, 'the client learns what is known');
	say(room, p, { t: 'use', item: 'manual_page' });
	assert.match(p.ws.last('note').message, /já sabe tudo/);
	assert.equal(p.me().inv.manual_page, 1, 'a useless page is kept');
	say(room, p, { t: 'craft', recipe: 'ammo_9mm' });
	assert.equal(p.me().inv.a_9mm, 8);
	room.damagePlayer(p.me(), 500, 'z1', 'zombie');
	assert.equal(p.me().known.length, pages.length, 'knowledge survives death');
});

test('zombie kills sometimes leave a rotten gland; cities have zombies in daylight too', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [0, 0, 0]);
	p.me().inv = { machete: 1 };
	for (let i = 0; i < 40; i++) {
		room.state.zombies['zz' + i] = { id: 'zz' + i, kind: 'walker', hp: 1, p: [1, 0, 0] };
		room.hitLog.clear();
		say(room, p, { t: 'melee', target: 'zz' + i, item: 'machete' });
	}
	const glands = Object.values(room.state.bags).filter((b) => b.items.zombie_gland);
	assert.ok(glands.length > 0 && glands.length < 40, `some glands (${glands.length}/40)`);
	assert.equal(glands[0].title, 'Restos de zumbi');
	// Meio-dia: no mato não nasce zumbi; perto de uma cidade, sim.
	setHour(room, 12);
	room.state.zombies = {};
	room.state.bags = {};
	await room.alarm();
	assert.equal(Object.keys(room.state.zombies).length, 0, 'no zombies in the woods by day');
	const town = world.towns[0].center;
	at(p, [town[0], 0, town[1] + 60]);
	for (let i = 0; i < 6; i++) await room.alarm();
	assert.ok(Object.keys(room.state.zombies).length > 0, 'the city has zombies by day');
});

test('iron tools gather more than stone ones; iron veins need a pick', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const ore = world.resources.find((r) => r.kind === 'ore');
	at(p, ore.p);
	gather(room, p, ore);
	assert.match(p.ws.last('note').message, /picareta de pedra/);
	p.me().inv = { stone_pick: 1 };
	gather(room, p, ore);
	const got = p.me().inv.iron_ore;
	assert.ok(got >= 1 && got <= 2);
	const rocks = world.resources.filter((r) => r.kind === 'rock');
	p.me().inv = { iron_pick: 1 };
	let total = 0;
	for (const rock of rocks.slice(0, 5)) {
		at(p, rock.p);
		p.me().inv = { iron_pick: 1 }; // esvazia os bolsos (10 kg) a cada rocha
		gather(room, p, rock);
		total += p.me().inv.stone || 0;
	}
	assert.ok(total >= 5 * catalog.resources.rock.bonus[0], 'iron pick yields the bonus');
});

test('berries feed, bandages heal, the herbal cure needs its 2 s and an infection', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	Object.assign(p.me(), { hunger: 20, thirst: 20, hp: 40, inv: { berries: 2, bandage: 1, herbal_cure: 1 } });
	say(room, p, { t: 'use', item: 'berries' });
	assert.equal(p.me().hunger, 20 + catalog.items.berries.use.hunger);
	assert.equal(p.me().thirst, 20 + catalog.items.berries.use.thirst);
	say(room, p, { t: 'use', item: 'bandage' });
	assert.equal(p.me().hp, 40 + catalog.items.bandage.use.hp);
	say(room, p, { t: 'use_start', item: 'herbal_cure' });
	p.me().useAt -= 2000;
	say(room, p, { t: 'use', item: 'herbal_cure' });
	assert.match(p.ws.last('note').message, /não está infectado/);
	assert.equal(p.me().inv.herbal_cure, 1, 'not wasted when healthy');
});

test('a bite infects: 2 minutes to take the herbal cure, otherwise the player turns into a zombie', async () => {
	const { room } = makeWorld();
	const host = await join(room);
	const p = await join(room);
	at(host, [50, 0, 50]);
	at(p, [0, 0, 0]);
	room.state.zombies.z9 = { id: 'z9', kind: 'walker', hp: 60, p: [1, 0, 0] };
	say(room, host, { t: 'zhit', z: 'z9', target: p.id });
	assert.ok(p.me().infectedAt > 0);
	assert.equal(p.ws.last('infected').left, 120);
	p.me().inv.herbal_cure = 1;
	p.me().hp = 100;
	say(room, p, { t: 'use', item: 'herbal_cure' });
	assert.ok(p.me().infectedAt > 0, 'no instant cure');
	say(room, p, { t: 'use_start', item: 'herbal_cure' });
	p.me().useAt -= 2000;
	say(room, p, { t: 'use', item: 'herbal_cure' });
	assert.equal(p.me().infectedAt, 0, 'works even at full health');
	assert.equal(p.ws.last('infected').left, 0);
	room.state.zombies.z9.lastHit = 0;
	say(room, host, { t: 'zhit', z: 'z9', target: p.id });
	p.me().infectedAt -= 121000;
	setHour(room, 22);
	await room.alarm();
	assert.equal(p.me().dead, true);
	assert.equal(host.ws.last('hp').w, 'infection');
	assert.ok(Object.values(room.state.zombies).some((z) => z.from === p.me().name), 'a zombie rises where the player died');
});

test('zombie bites come only from the host, in reach, at most once a second', async () => {
	const { room } = makeWorld();
	const host = await join(room);
	const other = await join(room);
	at(host, [50, 0, 50]);
	at(other, [0, 0, 0]);
	room.state.zombies.z9 = { id: 'z9', kind: 'walker', hp: 60, p: [1, 0, 0] };
	say(room, other, { t: 'zhit', z: 'z9', target: other.id });
	assert.equal(other.me().hp, 100, 'non-host cannot report bites');
	say(room, host, { t: 'zhit', z: 'z9', target: other.id });
	say(room, host, { t: 'zhit', z: 'z9', target: other.id });
	assert.equal(other.me().hp, 91);
	room.state.zombies.z9.p = [20, 0, 0];
	room.state.zombies.z9.lastHit = 0;
	say(room, host, { t: 'zhit', z: 'z9', target: other.id });
	assert.equal(other.me().hp, 91, 'too far to bite');
});

test('primitive weapons: the club hits harder than fists; zombies die and give XP; no guns', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [0, 0, 0]);
	room.state.zombies.z1 = { id: 'z1', kind: 'walker', hp: 60, p: [2, 0, 0] };
	p.me().inv.w_rifle = 1;
	say(room, p, { t: 'hit', target: 'z1', w: 'rifle', zone: 'head' });
	assert.equal(room.state.zombies.z1.hp, 60 - 27 * 2, 'server still knows guns, but the map has none');
	room.state.zombies.z1.hp = 60;
	delete p.me().inv.w_rifle;
	say(room, p, { t: 'melee', target: 'z1', item: 'club' });
	assert.equal(room.state.zombies.z1.hp, 60 - 12, 'club not owned: punch');
	p.me().inv.club = 1;
	say(room, p, { t: 'melee', target: 'z1', item: 'club' });
	assert.equal(room.state.zombies.z1.hp, 60 - 12 - catalog.items.club.melee);
	say(room, p, { t: 'melee', target: 'z1', item: 'club' });
	assert.equal(room.state.zombies.z1, undefined);
	assert.equal(p.ws.last('zdead').id, 'z1');
	assert.equal(p.ws.last('xp').amount, 5);
});

test('zombies come only at night, away from players, and fade away at dawn', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [world.spawns[0][0], 0, world.spawns[0][1]]);
	setHour(room, 12);
	assert.equal(room.isNight(), false);
	await room.alarm();
	assert.ok(p.me().hunger < 85 && p.me().thirst < 85);
	assert.equal(Object.keys(room.state.zombies).length, 0, 'no zombies in daylight');
	assert.ok(p.ws.last('clock'));
	assert.ok(p.ws.last('stats'));
	setHour(room, 21);
	assert.equal(room.isNight(), true);
	await room.alarm();
	const zombies = Object.values(room.state.zombies);
	assert.ok(zombies.length > 0, 'night brings zombies');
	for (const z of zombies) assert.ok(Math.hypot(z.p[0] - p.me().p[0], z.p[2] - p.me().p[2]) >= 38);
	setHour(room, 7);
	for (let i = 0; i < 40 && Object.keys(room.state.zombies).length; i++) await room.alarm();
	assert.equal(Object.keys(room.state.zombies).length, 0, 'gone after sunrise');
	assert.ok(p.ws.last('zgone'));
});

test('ping is answered at once with the client clock (also while dead)', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	say(room, p, { t: 'ping', c: 123456 });
	assert.deepEqual(p.ws.last('pong'), { t: 'pong', c: 123456 });
	p.me().dead = true;
	say(room, p, { t: 'ping', c: 'x' });
	assert.deepEqual(p.ws.last('pong'), { t: 'pong', c: 0 }, 'junk clock becomes 0');
});

test('the world info route tells who is online and where the account has a character', async () => {
	const { room } = makeWorld();
	const p = await join(room, { account: 'mundo' });
	await join(room);
	let info = await (await room.fetch(new Request('https://internal/has?account=mundo'))).json();
	assert.equal(info.online, 2);
	assert.equal(info.savedAt, 0, 'playing now, not saved');
	room.webSocketClose(p.ws);
	info = await (await room.fetch(new Request('https://internal/has?account=mundo'))).json();
	assert.equal(info.online, 1);
	assert.ok(info.savedAt > 0);
});

test('death drops a bag with everything; respawn after the timer with empty hands', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [10, 0, 10]);
	p.me().inv = { stone_axe: 1, wood: 3 };
	room.damagePlayer(p.me(), 500, 'z1', 'zombie');
	assert.equal(p.me().dead, true);
	const bag = Object.values(room.state.bags)[0];
	assert.deepEqual(bag.items, { stone_axe: 1, wood: 3 });
	say(room, p, { t: 'respawn' });
	assert.equal(p.me().dead, true, 'waits for the timer');
	p.me().respawnAt = 0;
	say(room, p, { t: 'respawn' });
	assert.equal(p.me().dead, false);
	assert.deepEqual(p.me().inv, {});
	assert.ok(p.ws.last('respawned'));
});

test('leaving keeps the character for the next visit', async () => {
	const { room } = makeWorld();
	const p = await join(room, { account: 'volta' });
	at(p, [33, 0, -12]);
	p.me().inv = { wood: 4 };
	room.webSocketClose(p.ws);
	assert.equal(room.state.chars.volta.inv.wood, 4);
	const again = await join(room, { account: 'volta' });
	assert.deepEqual(again.me().p, [33, 0, -12]);
	assert.deepEqual(again.me().inv, { wood: 4 });
});

test('who leaves stays asleep where they were, seen by the others, and wakes on return', async () => {
	const { room } = makeWorld();
	const watcher = await join(room, { account: 'olha' });
	const p = await join(room, { account: 'dorme' });
	at(p, [40, 0, 8]);
	room.webSocketClose(p.ws);
	const slept = watcher.ws.last('sleep');
	assert.ok(slept, 'others are told about the sleeping body');
	assert.deepEqual(slept.p, [40, 0, 8]);
	assert.equal(slept.account, undefined, 'the account is not exposed');
	const late = await join(room, { account: 'chega' });
	assert.equal(late.ws.last('start').sleepers.length, 1, 'late joiners also see it');
	const back = await join(room, { account: 'dorme' });
	assert.equal(watcher.ws.last('wake').id, slept.id);
	assert.deepEqual(back.me().p, [40, 0, 8]);
	assert.equal(room.state.chars.dorme, undefined);
	const res = await room.fetch(new Request('https://internal/has?account=olha'));
	assert.equal((await res.json()).savedAt, 0);
});
