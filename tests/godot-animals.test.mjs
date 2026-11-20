// Animais da Sobrevivência (src/godot-survival.js): nascem perto dos jogadores,
// viram carcaça com carne e couro, lobo e javali atacam, carne crua faz mal e
// a fogueira acesa assa a carne.
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
const world = JSON.parse(readFileSync(new URL('../godot/data/survival_world.json', import.meta.url), 'utf8'));
const catalog = JSON.parse(readFileSync(new URL('../godot/data/survival_items.json', import.meta.url), 'utf8'));

function makeWorld() {
	const store = new Map();
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
	return new GodotSurvival(ctx, env);
}

let seq = 0;
async function join(room) {
	seq++;
	await room.fetch(new Request(`https://internal/join?world=world:1&name=A${seq}&account=an${seq}&xp=0`, { headers: { Upgrade: 'websocket' } }));
	const ws = [...room.sessions.values()].at(-1);
	const id = ws.deserializeAttachment().id;
	return { ws, id, me: () => room.state.players[id] };
}
const say = (room, player, data) => room.webSocketMessage(player.ws, JSON.stringify(data));

test('catalog: every animal drops known items and the new recipes use known items', () => {
	for (const [kind, rule] of Object.entries(catalog.animals)) {
		assert.ok(rule.hp > 0 && rule.name, kind);
		for (const item of Object.keys(rule.loot)) assert.ok(catalog.items[item], `${kind} loot ${item}`);
		if (rule.behavior !== 'flee') assert.ok(rule.damage > 0, `${kind} bites`);
	}
	assert.ok(catalog.recipes.find((r) => r.id === 'cooked_meat').station === 'campfire');
});

test('animals spawn around players, away from them and out of the ponds, and leave when nobody is near', async () => {
	const room = makeWorld();
	const p = await join(room);
	p.me().p = [0, 0, 0];
	for (let i = 0; i < 6; i++) room.spawnAnimals();
	const list = Object.values(room.state.animals);
	const rules = catalog.animal_rules;
	assert.ok(list.length > 0 && list.length <= rules.base + rules.per_player, `count ${list.length}`);
	for (const a of list) {
		const d = Math.hypot(a.p[0], a.p[2]);
		assert.ok(d > rules.spawn_min - 5 && d < rules.spawn_max + 5, `distance ${d}`);
		assert.ok(!world.ponds.some((pond) => Math.hypot(pond.x - a.p[0], pond.z - a.p[2]) < pond.r), 'not in a pond');
	}
	assert.ok(p.ws.last('aspawn'));
	p.me().p = [world.half_size - 10, 0, world.half_size - 10];
	room.state.animals = { far: { id: 'far', kind: 'deer', hp: 80, p: [-200, 0.2, -200] } };
	room.spawnAnimals();
	assert.equal(room.state.animals.far, undefined);
	assert.deepEqual(p.ws.last('agone').l, ['far']);
});

test('hunting: a killed animal becomes a carcass with meat and hide', async () => {
	const room = makeWorld();
	const p = await join(room);
	p.me().p = [10, 0, 10];
	p.me().inv = { stone_axe: 1 };
	room.state.animals = { a1: { id: 'a1', kind: 'deer', hp: 30, p: [11, 0.2, 10] } };
	say(room, p, { t: 'melee', target: 'a1', item: 'stone_axe', zone: 'chest' });
	assert.equal(room.state.animals.a1.hp, 30 - catalog.items.stone_axe.melee);
	assert.equal(p.ws.last('ahp').hp, 6);
	room.hitLog.clear();
	say(room, p, { t: 'melee', target: 'a1', item: 'stone_axe', zone: 'chest' });
	assert.equal(room.state.animals.a1, undefined);
	assert.equal(p.ws.last('adead').id, 'a1');
	const bag = Object.values(room.state.bags)[0];
	assert.match(bag.title, /Carcaça de cervo/);
	assert.ok(bag.items.raw_meat >= 3 && bag.items.hide >= 2);
	say(room, p, { t: 'search', k: bag.id });
	assert.match(p.ws.last('container').title, /Carcaça/);
});

test('wolves and boars bite (in reach, once per cooldown); deer never do', async () => {
	const room = makeWorld();
	const host = await join(room);
	host.me().p = [0, 0, 0];
	room.state.animals = {
		w: { id: 'w', kind: 'wolf', hp: 70, p: [5, 0.2, 0] },
		d: { id: 'd', kind: 'deer', hp: 80, p: [1, 0.2, 0] },
	};
	say(room, host, { t: 'ahit', a: 'w', target: host.id });
	assert.equal(host.me().hp, 100, 'too far');
	room.state.animals.w.p = [1.5, 0.2, 0];
	say(room, host, { t: 'ahit', a: 'w', target: host.id });
	assert.equal(host.me().hp, 100 - catalog.animals.wolf.damage);
	say(room, host, { t: 'ahit', a: 'w', target: host.id });
	assert.equal(host.me().hp, 100 - catalog.animals.wolf.damage, 'cooldown');
	say(room, host, { t: 'ahit', a: 'd', target: host.id });
	assert.equal(host.me().hp, 100 - catalog.animals.wolf.damage, 'deer do not bite');
	assert.equal(host.ws.last('hp').w, 'a_wolf');
	assert.equal(host.me().infectedAt, 0, 'animals do not infect');
});

test('raw meat hurts; cooking needs a lit campfire nearby', async () => {
	const room = makeWorld();
	const p = await join(room);
	p.me().p = [20, 0, 20];
	p.me().hunger = 40;
	p.me().inv = { raw_meat: 3 };
	say(room, p, { t: 'use', item: 'raw_meat' });
	assert.equal(p.me().hp, 100 + catalog.items.raw_meat.use.hp);
	assert.equal(p.me().hunger, 40 + catalog.items.raw_meat.use.hunger);
	say(room, p, { t: 'craft', recipe: 'cooked_meat' });
	assert.match(p.ws.last('note').message, /fogueira acesa/);
	room.grid.add({ id: 'F1', kind: 'campfire', p: [21, 0, 20], y: 0, hp: 120, ow: 'x', on: false });
	say(room, p, { t: 'craft', recipe: 'cooked_meat' });
	assert.match(p.ws.last('note').message, /fogueira acesa/, 'unlit fire does not cook');
	room.grid.pieces.get('F1').on = true;
	say(room, p, { t: 'craft', recipe: 'cooked_meat' });
	assert.equal(p.me().inv.cooked_meat, 1);
	assert.equal(p.me().inv.raw_meat, 1);
});
