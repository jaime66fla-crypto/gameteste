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

test('wolves hunt prey, prey damage is authoritative, and only the host can report it',async()=>{
 const {room}=makeWorld();const host=await join(room);const guest=await join(room);
 room.state.animals={w:{id:'w',kind:'wolf',hp:70,hunger:30,thirst:80,p:[0,0.3,0]},d:{id:'d',kind:'deer',hp:80,p:[1,0.3,0]}};
 say(room,guest,{t:'ahit',a:'w',target:'d'});assert.equal(room.state.animals.d.hp,80);
 say(room,host,{t:'ahit',a:'w',target:'d'});assert.equal(room.state.animals.d.hp,69);
 say(room,host,{t:'ahit',a:'w',target:'d'});assert.equal(room.state.animals.d.hp,69,'cooldown enforced');
});
test('boars defend against their actual animal attacker but do not attack unrelated prey',async()=>{
 const {room}=makeWorld();const p=await join(room);
 room.state.animals={w:{id:'w',kind:'wolf',hp:70,hunger:30,thirst:80,p:[0,0.3,0]},b:{id:'b',kind:'boar',hp:110,p:[1,0.3,0]},r:{id:'r',kind:'rabbit',hp:15,p:[1,0.3,1]}};
 say(room,p,{t:'ahit',a:'b',target:'r'});assert.equal(room.state.animals.r.hp,15);
 say(room,p,{t:'ahit',a:'w',target:'b'});assert.equal(room.state.animals.b.hp,99);
 say(room,p,{t:'ahit',a:'b',target:'w'});assert.equal(room.state.animals.w.hp,56);
});
test('predators eat their kill, stop hunting while fed, and grant no player XP or free carcass loot',async()=>{
 const {room}=makeWorld();const p=await join(room);
 room.state.animals={w:{id:'w',kind:'wolf',hp:70,hunger:30,thirst:80,p:[0,0.3,0]},r:{id:'r',kind:'rabbit',hp:5,p:[1,0.3,0]},d:{id:'d',kind:'deer',hp:80,p:[1,0.3,1]}};
 say(room,p,{t:'ahit',a:'w',target:'r'});assert.ok(!room.state.animals.r);
 assert.equal(Object.keys(room.state.bags).length,0);assert.equal(p.me().xpGain||0,0);
 assert.ok(room.state.animals.w.fedUntil>Date.now());assert.ok(p.ws.last('afed').left>0);
 room.state.animals.w.lastHit=0;say(room,p,{t:'ahit',a:'w',target:'d'});assert.equal(room.state.animals.d.hp,80);
 assert.ok(room.startPacket(p.me()).animals.find(a=>a.id==='w').fed>0,'late join retains feeding state');
});
test('population replenishment prioritizes absent species and limits predators',async()=>{
 const {room}=makeWorld();await join(room);room.animalSpot=()=>[0,0.3,0];
 for(let i=0;i<4;i++)room.spawnAnimals();
 const animals=Object.values(room.state.animals);const kinds=new Set(animals.map(a=>a.kind));
 for(const kind of ['rabbit','deer','boar','wolf'])assert.ok(kinds.has(kind),`${kind} is present`);
 assert.ok(animals.filter(a=>a.kind==='wolf').length<=Math.max(1,Math.floor(animals.length*.25)));
});
test('animal attacks cannot cross large vertical separation',async()=>{
 const {room}=makeWorld();const p=await join(room);
 room.state.animals={w:{id:'w',kind:'wolf',hp:70,hunger:30,thirst:80,p:[0,0.3,0]},d:{id:'d',kind:'deer',hp:80,p:[1,12,0]}};
 say(room,p,{t:'ahit',a:'w',target:'d'});assert.equal(room.state.animals.d.hp,80);
});
test('saved full or almost-full single-species populations recover the missing food chain',async()=>{
 for(const count of [6,7]){
  const {room}=makeWorld();await join(room);room.animalSpot=()=>[0,0.3,0];
  room.state.animals={};
  for(let i=0;i<count;i++)room.state.animals['old'+i]={id:'old'+i,kind:'deer',hp:80,p:[0,0.3,0]};
  for(let i=0;i<4;i++)room.spawnAnimals();
  const list=Object.values(room.state.animals);
  for(const kind of ['rabbit','deer','boar','wolf'])assert.ok(list.some(a=>a.kind===kind),`${count}-animal save recovers ${kind}`);
  assert.ok(list.length<=7);
 }
});
