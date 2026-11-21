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

const { terrainHeight } = await import('../src/godot-terrain.js');
test('natural animal groups spawn above the actual terrain at each member position',async()=>{
 const {room}=makeWorld();await join(room);
 const m=world.mountains.find(m=>m.h>10&&m.r>20);
 assert.ok(m,'mountain fixture exists');
 room.animalSpot=()=>[m.x,terrainHeight(m.x,m.z)+0.3,m.z];
 room.spawnAnimals();
 const animals=Object.values(room.state.animals);
 assert.ok(animals.length>0);
 for(const animal of animals){
  const floor=terrainHeight(animal.p[0],animal.p[2]);
  assert.ok(animal.p[1]>=floor+0.19,`${animal.kind} spawned at ${animal.p[1]} under terrain ${floor}`);
  assert.ok(animal.p[1]<=floor+0.41,'spawn stays close to terrain, not floating');
 }
 assert.ok(room.startPacket([...Object.values(room.state.players)][0]).animals.length>0,'joining client receives animals');
});
test('flatland groups still spawn close to the ground and reach clients through aspawn',async()=>{
 const {room}=makeWorld();const p=await join(room);
 room.animalSpot=()=>[0,0.3,0];room.spawnAnimals();
 const packet=p.ws.last('aspawn');assert.ok(packet?.l.length>0);
 for(const animal of packet.l){assert.ok(animal.p[1]>=0.2);assert.ok(animal.p[1]<0.5);}
});
test('an old saved animal below a mountain is removed and replaced above terrain',async()=>{
 const {room}=makeWorld();const p=await join(room);
 const m=world.mountains[0];p.me().p=[m.x,terrainHeight(m.x,m.z)+0.3,m.z];
 room.state.animals={hidden:{id:'hidden',kind:'deer',hp:80,p:[m.x,0.2,m.z]}};
 room.animalSpot=()=>[m.x,terrainHeight(m.x,m.z)+0.3,m.z];
 room.spawnAnimals();assert.ok(!room.state.animals.hidden,'invalid old saved spawn is removed');
 assert.ok(p.ws.last('agone').l.includes('hidden'));
 assert.ok(Object.values(room.state.animals).every(a=>a.p[1]>terrainHeight(a.p[0],a.p[2])));
});
