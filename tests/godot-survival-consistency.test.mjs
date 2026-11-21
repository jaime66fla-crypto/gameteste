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

const {carriedWeight} = await import('../src/godot-survival.js');
test('loaded rounds survive reconnect, firing, and still count toward carried weight', async()=>{
 const {room}=makeWorld();let p=await join(room,{account:'ammo-audit'});
 p.me().inv={w_pistol:1,a_9mm:15};const weight=carriedWeight(p.me());
 say(room,p,{t:'consume',ammo:'a_9mm',n:15,w:'pistol'});
 assert.equal(p.me().magazines?.pistol,15,'reload must retain rounds in server-owned magazine');
 assert.equal(p.me().inv.a_9mm||0,0);assert.equal(carriedWeight(p.me()),weight);
 say(room,p,{t:'shot',w:'pistol',o:p.me().p,e:[p.me().p[0]+10,p.me().p[1],p.me().p[2]]});
 assert.equal(p.me().magazines.pistol,14,'one emitted shot spends one round');
 room.drop_(p.ws);p=await join(room,{account:'ammo-audit'});
 assert.equal(p.me().magazines.pistol,14);assert.equal(p.ws.sent.find(m=>m.t==='start').you.magazines.pistol,14);
});
test('invalid magazine requests do not consume ammunition and old arrow messages still work',async()=>{
 const {room}=makeWorld();const p=await join(room);p.me().inv={w_pistol:1,a_9mm:30,a_12g:4,stone_arrow:3};
 say(room,p,{t:'consume',ammo:'a_12g',n:4,w:'pistol'});assert.equal(p.me().inv.a_12g,4,'wrong calibre rejected');
 say(room,p,{t:'consume',ammo:'a_9mm',n:30,w:'pistol'});assert.equal(p.me().magazines?.pistol||0,15,'magazine cannot exceed capacity');
 assert.equal(p.me().inv.a_9mm,15);
 say(room,p,{t:'consume',ammo:'a_9mm',n:1,w:'smg'});assert.equal(p.me().inv.a_9mm,15,'unowned weapon rejected');
 say(room,p,{t:'consume',ammo:'stone_arrow',n:1});assert.equal(p.me().inv.stone_arrow,2);
});
test('loaded ammunition is recoverable when a weapon is dropped, stored, or its owner dies',async()=>{
 const {room}=makeWorld();const p=await join(room);p.me().inv={w_pistol:1};p.me().magazines={pistol:7};
 say(room,p,{t:'drop',item:'w_pistol'});
 let bag=Object.values(room.state.bags).at(-1);assert.equal(bag.items.a_9mm,7,'dropped gun retains ammunition in its bag');
 assert.equal(p.me().magazines.pistol||0,0);
 p.me().inv={w_pistol:1};p.me().magazines={pistol:6};
 room.grid.add({id:'audit-chest',kind:'chest',p:[...p.me().p],hp:200,items:{}});
 say(room,p,{t:'store',k:'audit-chest',item:'w_pistol'});
 assert.equal(p.me().inv.a_9mm,6,'storing last gun unloads rounds into player inventory');
 assert.equal(p.me().magazines.pistol||0,0);
 p.me().inv={w_pistol:1};p.me().magazines={pistol:5};
 room.kill(p.me());bag=Object.values(room.state.bags).at(-1);assert.ok(bag.items.a_9mm>=5);
 assert.deepEqual(p.me().magazines,{});
});
test('crafting rejects output that increases weight beyond capacity without consuming ingredients',async()=>{
 const {room}=makeWorld();const p=await join(room);p.me().p=[0,0,0];
 const stone=Math.floor((carryLimit('')-1.16)/0.6);
 const fiber=Math.round((carryLimit('')-0.04-1.16-stone*0.6)/0.05);
 p.me().inv={wood:1,nails:8,stone,fiber};
 room.grid.add({id:'bench',kind:'workbench',p:[0,0,0],hp:250});const before=structuredClone(p.me().inv);
 say(room,p,{t:'craft',recipe:'nail_bat'});assert.deepEqual(p.me().inv,before);assert.match(p.ws.last('note').message,/peso|Peso/);
 delete p.me().inv.stone;say(room,p,{t:'craft',recipe:'nail_bat'});assert.equal(p.me().inv.nail_bat,1);
});
test('legacy saved characters without magazines continue to load safely',async()=>{
 const {room}=makeWorld();const p=await join(room);room.drop_(p.ws);delete room.state.chars[p.ws.deserializeAttachment().account]?.magazines;
 const restored=room.restore({p:[0,0.2,0],hp:100,hunger:85,thirst:85,inv:{w_pistol:1}});
 assert.deepEqual(restored.magazines,{});
 const corrupt=room.restore({p:[0,0.2,0],hp:100,hunger:85,thirst:85,inv:{w_pistol:1},magazines:{pistol:999,smg:25,bow:3}});
 assert.deepEqual(corrupt.magazines,{pistol:15});
});
test('carrying capacity increases to 20 kg while preserving both backpack upgrades',()=>{
 assert.equal(carryLimit(''),20);assert.equal(carryLimit('sack_bag'),30);assert.equal(carryLimit('hide_bag'),42);
});
test('pistol and SMG share loose 9 mm but retain separate loaded magazines across reconnect',async()=>{
 const {room}=makeWorld();let p=await join(room,{account:'shared-ammo'});
 p.me().inv={w_pistol:1,w_smg:1,a_9mm:30};
 say(room,p,{t:'consume',ammo:'a_9mm',n:15,w:'pistol'});
 say(room,p,{t:'consume',ammo:'a_9mm',n:15,w:'smg'});
 assert.deepEqual(p.me().magazines,{pistol:15,smg:15});assert.equal(p.me().inv.a_9mm||0,0);
 for(const w of ['pistol','smg']) say(room,p,{t:'shot',w,o:p.me().p,e:[p.me().p[0]+10,p.me().p[1],p.me().p[2]]});
 assert.deepEqual(p.me().magazines,{pistol:14,smg:14});
 room.drop_(p.ws);p=await join(room,{account:'shared-ammo'});
 assert.deepEqual(p.me().magazines,{pistol:14,smg:14});
 say(room,p,{t:'drop',item:'w_pistol'});
 assert.deepEqual(p.me().magazines,{smg:14});assert.equal(Object.values(room.state.bags).at(-1).items.a_9mm,14);
});
test('a pre-existing overweight save can still craft an item that reduces its weight',async()=>{
 const {room}=makeWorld();const p=await join(room);p.me().inv={stone:35,herb:3,fiber:1};
 const before=carriedWeight(p.me());assert.ok(before>carryLimit(''));
 say(room,p,{t:'craft',recipe:'herbal_cure'});
 assert.equal(p.me().inv.herbal_cure,1);assert.ok(carriedWeight(p.me())<before);
});
