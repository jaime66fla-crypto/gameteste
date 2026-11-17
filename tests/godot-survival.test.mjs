// Modo Sobrevivência (src/godot-survival.js) com um runtime falso de Durable Object.
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

const { GodotSurvival, CAPACITY, rollLoot, carryLimit, inventoryWeight } = await import('../src/godot-survival.js');
const world = JSON.parse(readFileSync(new URL('../godot/data/survival_world.json', import.meta.url), 'utf8'));
const catalog = JSON.parse(readFileSync(new URL('../godot/data/survival_items.json', import.meta.url), 'utf8'));

function makeWorld() {
	const store = new Map();
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

test('world data: every container type has a loot table and every resource kind a rule', () => {
	assert.equal(world.spawns.length, 16);
	for (const c of world.containers) assert.ok(catalog.loot[c.type], c.type);
	for (const r of world.resources) assert.ok(catalog.resources[r.kind], r.kind);
	for (const table of Object.values(catalog.loot)) for (const [item] of table.table) assert.ok(catalog.items[item], item);
	for (const recipe of catalog.recipes) {
		for (const item of Object.keys(recipe.needs)) assert.ok(catalog.items[item], item);
		assert.ok(catalog.items[recipe.gives[0]], recipe.gives[0]);
	}
});

test('joining spawns at once with the starter kit; 16 players fill a world', async () => {
	const { room } = makeWorld();
	const first = await join(room);
	assert.equal(first.status, 101);
	const start = first.ws.last('start');
	assert.equal(start.survival, true);
	assert.equal(start.host, first.id);
	assert.deepEqual(start.you.inv, catalog.starter_kit);
	for (let i = 1; i < CAPACITY; i++) assert.equal((await join(room)).status, 101);
	assert.equal((await join(room)).status, 409);
});

test('search rolls loot once, take moves items into the backpack', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const box = world.containers.find((c) => c.type === 'shelf');
	at(p, [box.p[0] + 30, 0, box.p[2]]);
	say(room, p, { t: 'search', k: box.id });
	assert.match(p.ws.last('note').message, /Longe/);
	at(p, box.p);
	say(room, p, { t: 'search', k: box.id });
	const first = p.ws.last('container');
	assert.equal(first.k, box.id);
	const [item, n] = Object.entries(first.items)[0];
	say(room, p, { t: 'search', k: box.id });
	assert.deepEqual(p.ws.last('container').items, first.items, 'same contents when searched again');
	const before = p.me().inv[item] || 0;
	say(room, p, { t: 'take', k: box.id, item });
	assert.equal(p.me().inv[item], before + n);
	assert.equal(room.state.containers[box.id].items[item], undefined);
	assert.ok(p.ws.last('inv'));
});

test('weight limit: a full backpack refuses more, a better backpack raises the limit', () => {
	assert.equal(carryLimit({}), catalog.carry_base);
	assert.equal(carryLimit({ school_bag: 1, backpack: 1 }), catalog.carry_base + catalog.items.backpack.carry);
	assert.equal(inventoryWeight({ wood: 3, stone: 1 }), 3.8);
});

test('take is capped by weight', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const box = world.containers.find((c) => c.type === 'toolbox');
	at(p, box.p);
	room.state.containers[box.id] = { items: { wood: 40 }, refillAt: Date.now() + 1e6 };
	p.me().inv = {};
	say(room, p, { t: 'take', k: box.id, item: 'wood' });
	assert.equal(p.me().inv.wood, catalog.carry_base);
	assert.equal(room.state.containers[box.id].items.wood, 40 - catalog.carry_base);
	assert.match(p.ws.last('note').message, /pesada/);
});

test('eating and drinking restore hunger/thirst; medkit needs its 3 s', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	Object.assign(p.me(), { hunger: 20, thirst: 20, hp: 40, inv: { canned_beans: 1, water_bottle: 1, medkit: 1 } });
	say(room, p, { t: 'use', item: 'canned_beans' });
	say(room, p, { t: 'use', item: 'water_bottle' });
	assert.equal(p.me().hunger, 55);
	assert.equal(p.me().thirst, 20 - 4 + 40);
	say(room, p, { t: 'use', item: 'medkit' });
	assert.equal(p.me().hp, 40, 'no instant medkit');
	say(room, p, { t: 'use_start', item: 'medkit' });
	p.me().useAt -= 3000;
	say(room, p, { t: 'use', item: 'medkit' });
	assert.equal(p.me().hp, 90);
	assert.deepEqual(p.me().inv, {});
});

test('crafting consumes the recipe and refuses without materials', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	p.me().inv = { wood: 2, stone: 2, cloth: 1 };
	say(room, p, { t: 'craft', recipe: 'improvised_axe' });
	assert.match(p.ws.last('note').message, /Falta Corda/);
	p.me().inv.rope = 1;
	say(room, p, { t: 'craft', recipe: 'improvised_axe' });
	assert.deepEqual(p.me().inv, { cloth: 1, improvised_axe: 1 });
});

test('gathering needs the hold time, pays more with the right tool and then regrows', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	const tree = world.resources.find((r) => r.kind === 'tree');
	at(p, tree.p);
	p.me().inv = {};
	say(room, p, { t: 'gather', r: tree.id });
	assert.deepEqual(p.me().inv, {}, 'no instant gather');
	say(room, p, { t: 'gather_start', r: tree.id });
	p.me().gatherAt -= 2500;
	say(room, p, { t: 'gather', r: tree.id });
	assert.equal(p.me().inv.wood, 1);
	assert.ok(room.state.depleted[tree.id] > Date.now());
	say(room, p, { t: 'gather_start', r: tree.id });
	p.me().gatherAt -= 2500;
	say(room, p, { t: 'gather', r: tree.id });
	assert.match(p.ws.last('note').message, /Já foi coletado/);
	const other = world.resources.filter((r) => r.kind === 'tree')[1];
	at(p, other.p);
	p.me().inv = { axe: 1 };
	say(room, p, { t: 'gather_start', r: other.id });
	p.me().gatherAt -= 2500;
	say(room, p, { t: 'gather', r: other.id });
	assert.ok(p.me().inv.wood >= 3);
});

test('guns need the weapon in the backpack; zombies die and give XP', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [0, 0, 0]);
	room.state.zombies.z1 = { id: 'z1', kind: 'walker', hp: 60, p: [5, 0, 0] };
	say(room, p, { t: 'hit', target: 'z1', w: 'rifle', zone: 'head' });
	assert.equal(room.state.zombies.z1.hp, 60, 'no rifle yet');
	p.me().inv.w_rifle = 1;
	say(room, p, { t: 'hit', target: 'z1', w: 'rifle', zone: 'head' });
	assert.equal(room.state.zombies.z1.hp, 6);
	say(room, p, { t: 'melee', target: 'z1' });
	assert.equal(room.state.zombies.z1, undefined);
	assert.equal(p.ws.last('zdead').id, 'z1');
	assert.equal(p.ws.last('xp').amount, 5);
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

test('death drops a bag with everything; respawn after the timer with the starter kit', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [10, 0, 10]);
	p.me().inv = { w_pistol: 1, a_9mm: 30 };
	room.damagePlayer(p.me(), 500, 'z1', 'zombie');
	assert.equal(p.me().dead, true);
	const bag = Object.values(room.state.bags)[0];
	assert.deepEqual(bag.items, { w_pistol: 1, a_9mm: 30 });
	say(room, p, { t: 'respawn' });
	assert.equal(p.me().dead, true, 'waits for the timer');
	p.me().respawnAt = 0;
	say(room, p, { t: 'respawn' });
	assert.equal(p.me().dead, false);
	assert.deepEqual(p.me().inv, catalog.starter_kit);
	assert.ok(p.ws.last('respawned'));
});

test('leaving keeps the character for the next visit', async () => {
	const { room } = makeWorld();
	const p = await join(room, { account: 'volta' });
	at(p, [33, 0, -12]);
	p.me().inv = { scrap: 4 };
	room.webSocketClose(p.ws);
	assert.equal(room.state.chars.volta.inv.scrap, 4);
	const again = await join(room, { account: 'volta' });
	assert.deepEqual(again.me().p, [33, 0, -12]);
	assert.deepEqual(again.me().inv, { scrap: 4 });
});

test('the tick drains hunger and thirst and spawns zombies away from players', async () => {
	const { room } = makeWorld();
	const p = await join(room);
	at(p, [world.spawns[0][0], 0, world.spawns[0][1]]);
	await room.alarm();
	assert.ok(p.me().hunger < 85 && p.me().thirst < 85);
	const zombies = Object.values(room.state.zombies);
	assert.ok(zombies.length > 0);
	for (const z of zombies) assert.ok(Math.hypot(z.p[0] - p.me().p[0], z.p[2] - p.me().p[2]) >= 38);
	assert.ok(p.ws.last('clock'));
	assert.ok(p.ws.last('stats'));
});

test('loot rolls only produce known items', () => {
	for (const type of Object.keys(catalog.loot)) {
		for (let i = 0; i < 50; i++) for (const item of Object.keys(rollLoot(type))) assert.ok(catalog.items[item], item);
	}
});
