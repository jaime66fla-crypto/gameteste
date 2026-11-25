// Modo Sobrevivência (src/godot-survival.js) com um runtime falso de Durable Object.
// Mundo de floresta: nada para saquear, tudo é coletado e fabricado; zumbis só à noite.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { terrainHeight } from '../src/godot-terrain.js';

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

test('animals lose satiety and hydration over time, including legacy animals, without instant hibernation starvation',async()=>{
 const {room}=makeWorld();const p=await join(room);const now=Date.now();
 room.state.animals={a:{id:'a',kind:'deer',hp:80,p:[...p.me().p],hunger:70,thirst:75,needsAt:now-3000}};
 assert.equal(typeof room.tickAnimalNeeds,'function');room.tickAnimalNeeds(now);
 assert.ok(room.state.animals.a.hunger<70&&room.state.animals.a.thirst<75);
 const before=room.state.animals.a.hunger;room.tickAnimalNeeds(now);assert.equal(room.state.animals.a.hunger,before,'same tick is not charged twice');
 room.state.animals.a.needsAt=now-3600000;room.tickAnimalNeeds(now+3000);assert.ok(room.state.animals.a.hunger>60,'long unloaded intervals are capped');
 assert.ok(p.ws.last('aneeds').l.length>0);
});
test('a hungry deer grazes real grass after the action time; a satisfied deer cannot keep eating',async()=>{
 const {room}=makeWorld();const p=await join(room);const patch=world.grass[0];
 room.state.animals={a:{id:'a',kind:'deer',hp:80,p:[patch.x,terrainHeight(patch.x,patch.z)+0.3,patch.z],hunger:30,thirst:80}};
 assert.equal(typeof room.animalForage,'function');
 say(room,p,{t:'aforage',a:'a',source:'grass:0',phase:'start'});
 say(room,p,{t:'aforage',a:'a',source:'grass:0',phase:'finish'});assert.equal(room.state.animals.a.hunger,30,'cannot finish instantly');
 room.state.animals.a.forageAt-=3100;
 say(room,p,{t:'aforage',a:'a',source:'grass:0',phase:'finish'});assert.ok(room.state.animals.a.hunger>30);
 assert.equal(room.state.animals.a.thirst,80,'food does not silently refill thirst');
 room.state.animals.a.hunger=90;say(room,p,{t:'aforage',a:'a',source:'grass:0',phase:'start'});assert.equal(room.state.animals.a.forageSource,'');
});
test('thirsty animals drink at actual lake shores and reject far away water',async()=>{
 const {room}=makeWorld();const p=await join(room);const pond=world.ponds[0];
 room.state.animals={a:{id:'a',kind:'rabbit',hp:15,p:[pond.x+pond.r+.5,0.3,pond.z],hunger:80,thirst:20}};
 assert.equal(typeof room.animalForage,'function');
 say(room,p,{t:'aforage',a:'a',source:'water:0',phase:'start'});room.state.animals.a.forageAt-=2100;
 say(room,p,{t:'aforage',a:'a',source:'water:0',phase:'finish'});assert.ok(room.state.animals.a.thirst>20);
 room.state.animals.a.thirst=20;room.state.animals.a.p=[0,0,0];
 say(room,p,{t:'aforage',a:'a',source:'water:0',phase:'start'});assert.equal(room.state.animals.a.forageSource,'');
});
test('different fruits serve different species and only one animal consumes a fallen fruit',async()=>{
 const {room}=makeWorld();const p=await join(room);
 room.state.fruits={apple:{id:'apple',kind:'apple',tree:'test',p:[0,.1,0],expires:Date.now()+99999}};
 room.state.animals={r1:{id:'r1',kind:'rabbit',hp:15,p:[0,.3,0],hunger:20,thirst:80},r2:{id:'r2',kind:'rabbit',hp:15,p:[0,.3,0],hunger:20,thirst:80},b:{id:'b',kind:'boar',hp:110,p:[0,.3,0],hunger:20,thirst:80}};
 assert.equal(typeof room.animalForage,'function');
 say(room,p,{t:'aforage',a:'b',source:'apple',phase:'start'});assert.ok(!room.state.animals.b.forageSource,'boar cannot substitute apples for acorns');
 for(const a of ['r1','r2']){say(room,p,{t:'aforage',a,source:'apple',phase:'start'});room.state.animals[a].forageAt-=3100;}
 say(room,p,{t:'aforage',a:'r1',source:'apple',phase:'finish'});say(room,p,{t:'aforage',a:'r2',source:'apple',phase:'finish'});
 assert.ok(!room.state.fruits.apple);assert.ok(room.state.animals.r1.hunger>20);assert.equal(room.state.animals.r2.hunger,20);
 assert.equal(p.ws.last('fruit_gone').id,'apple');
});
test('fruit drops are bounded, expire, and stop on cut trees',async()=>{
 const {room}=makeWorld();const p=await join(room);const now=Date.now();
 assert.equal(typeof room.dropTreeFruit,'function');
 const tree=world.resources.find(r=>r.kind==='tree'&&Number(r.id.slice(1))%5===2&&Number(r.id.slice(1))%11!==7);
 p.me().p=[...tree.p];room.state.fruitNext={[tree.id]:now-1};room.dropTreeFruit(now);
 const fruit=Object.values(room.state.fruits).find(f=>f.tree===tree.id);assert.ok(fruit&&fruit.kind==='acorn');
 assert.ok(room.startPacket(p.me()).fruits.some(f=>f.id===fruit.id),'late join receives fallen fruit');
 delete room.state.fruits[fruit.id];room.state.fruitNext[tree.id]=now-1;room.state.depleted[tree.id]=now+600000;room.dropTreeFruit(now);assert.ok(!room.state.fruits[fruit.id]);
 room.state.fruits.expired={id:'expired',kind:'apple',p:tree.p,expires:now-1};room.dropTreeFruit(now);assert.ok(!room.state.fruits.expired);
 assert.ok(Object.keys(room.state.fruits).length<=96);
});
test('only hungry predators feed through a kill and only the host can forage',async()=>{
 const {room}=makeWorld();const p=await join(room);const guest=await join(room);
 room.state.animals={w:{id:'w',kind:'wolf',hp:70,p:[0,.3,0],hunger:90,thirst:80},r:{id:'r',kind:'rabbit',hp:15,p:[1,.3,0],hunger:70,thirst:75}};
 say(room,p,{t:'ahit',a:'w',target:'r'});assert.equal(room.state.animals.r.hp,15,'satisfied wolves do not hunt for food');
 const patch=world.grass[0];room.state.animals.d={id:'d',kind:'deer',hp:80,p:[patch.x,.3,patch.z],hunger:20,thirst:80};
 say(room,guest,{t:'aforage',a:'d',source:'grass:0',phase:'start'});assert.ok(!room.state.animals.d.forageSource);
});
test('legacy needs default safely and saved needs remain visible to late joiners',async()=>{
 const {room}=makeWorld();const p=await join(room);
 room.state.animals={old:{id:'old',kind:'deer',hp:80,p:[...p.me().p]},saved:{id:'saved',kind:'boar',hp:110,p:[...p.me().p],hunger:22,thirst:31}};
 const packet=room.startPacket(p.me());
 assert.equal(packet.animals.find(a=>a.id==='old').hunger,70);
 assert.equal(packet.animals.find(a=>a.id==='old').thirst,75);
 assert.equal(packet.animals.find(a=>a.id==='saved').hunger,22);
 assert.equal(packet.animals.find(a=>a.id==='saved').thirst,31);
});
test('death from unmet needs never creates free player loot or XP',async()=>{
 const {room}=makeWorld();const p=await join(room);const now=Date.now();
 room.state.animals={a:{id:'a',kind:'rabbit',hp:.1,p:[...p.me().p],hunger:0,thirst:0,needsAt:now-3000}};
 room.tickAnimalNeeds(now);
 assert.ok(!room.state.animals.a);assert.equal(Object.keys(room.state.bags).length,0);
 assert.equal(p.me().xpGain||0,0);assert.equal(p.ws.last('adead').by,'nature');
});
