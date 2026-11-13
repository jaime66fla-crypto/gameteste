import assert from 'node:assert/strict';
import {GameRoom} from '../src/worker.js';
import worker from '../src/worker.js';
import {createMultiplayer3D} from '../public/multiplayer3d.js';
class Peer{constructor(id){this.attachment={id,mode:'3d'};this.messages=[]}deserializeAttachment(){return structuredClone(this.attachment)}serializeAttachment(data){this.attachment=structuredClone(data)}send(data){this.messages.push(JSON.parse(data))}}
const a=new Peer('alice'),b=new Peer('bob'),ctx={getWebSockets:()=>[a,b],waitUntil(){},storage:{setAlarm:async()=>{},put:async()=>{}}};let room=new GameRoom(ctx,{});
const message=(peer,data)=>room.webSocketMessage(peer,JSON.stringify(data));
const state=(x,z,name)=>({type:'state3d',x,y:0,z,angle:0,name,weapon:'rifle'});
message(a,state(0,0,'Alice'));message(b,state(0,10,'Bob'));
assert(a.messages.some(m=>m.type==='state3d'&&m.id==='bob'));
assert.equal(room.players.get('alice').health,100);
message(a,{...state(0,0,'Alice'),health:900,kills:100});assert.equal(room.players.get('alice').kills,0,'Client cannot forge scores');
message(a,{...state(0,0,'Alice'),x:1e9});assert.equal(room.players.get('alice').x,0);
// Restore hibernated sessions, including names, health, and score.
room=new GameRoom(ctx,{});assert.equal(room.players.get('bob').name,'Bob');
const fire=id=>message(a,{type:'shot3d',shotId:id,weapon:'rifle',origin:{x:0,y:1.5,z:0},rays:[{x:0,y:0,z:1}]});
fire('one');assert(b.messages.some(m=>m.type==='shot3d'&&m.ownerId==='alice'));
message(a,{type:'hit3d',shotId:'one',pellet:0,targetId:'bob'});assert.equal(room.players.get('bob').health,72);
message(a,{type:'hit3d',shotId:'one',pellet:0,targetId:'bob'});assert.equal(room.players.get('bob').health,72,'Duplicate pellet cannot damage twice');
message(b,{type:'hit3d',shotId:'one',pellet:0,targetId:'alice'});assert.equal(room.players.get('alice').health,100,'A player cannot claim another player’s shot');
for(let i=0;i<4;i++){room.players.get('alice').lastShot=0;fire('next-'+i);message(a,{type:'hit3d',shotId:'next-'+i,pellet:0,targetId:'bob'})}
assert.equal(room.players.get('alice').kills,1);assert.equal(room.players.get('bob').health,0);assert.equal(room.players.get('bob').dead,true);room.players.get('bob').deadUntil=Date.now()-1;await room.alarm();assert.equal(room.players.get('bob').health,100);assert(b.messages.some(m=>m.type==='respawn3d'&&m.id==='bob'));
room.drop(b);assert(!room.players.has('bob'));assert(a.messages.some(m=>m.type==='leave'&&m.id==='bob'));
const ids=[];const env={GAME_ROOMS:{idFromName:name=>{ids.push(name);return name},get:()=>({fetch:()=>new Response('ok')})}};
await worker.fetch(new Request('https://example.test/ws?mode=3d&room=teste'),env);await worker.fetch(new Request('https://example.test/ws?room=teste'),env);assert.deepEqual(ids,['3d:teste','teste']);
// Real client protocol exchanges with two independent transports.
const peers=[];
class Socket{constructor(url){this.url=url;this.readyState=1;this.sent=[];peers.push(this)}send(data){this.sent.push(JSON.parse(data))}close(){this.readyState=3;this.onclose?.()}receive(message){this.onmessage({data:JSON.stringify(message)})}}
const events=[];const client=createMultiplayer3D({Socket,url:room=>'wss://example.test/ws?room='+room,onState:s=>events.push(s),onHit:hit=>events.push(hit)});
client.connect('Alice','Teste');const transport=peers[0];transport.receive({type:'welcome3d',id:'alice',players:[{id:'bob',name:'Bob'}]});assert(client.connected&&events.some(e=>e.id==='bob'));
client.update(.1,state(1,2,'Alice'));assert.equal(transport.sent[0].type,'state3d');const id=client.shoot({weapon:'pistol',origin:{x:0,y:1,z:0},rays:[{x:0,y:0,z:1}]});assert(id);client.hit(id,0,'bob');assert.equal(transport.sent.at(-1).type,'hit3d');
client.disconnect();assert(!client.connected);
console.log('PASS: two peers; state broadcasts; hibernation; server-authoritative damage/scores; duplicate-hit rejection; death/respawn; leave; 2D/3D room isolation; client join/snapshot/shoot/hit/exit.');
