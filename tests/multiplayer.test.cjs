const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
function server(){
 let clock=10000;const sockets=[];class Socket{constructor(){this.messages=[]}send(s){this.messages.push(JSON.parse(s))}serializeAttachment(m){assert.ok(require('node:v8').serialize(m).length<=2048,'Cloudflare attachment exceeds 2048 bytes');this.meta=structuredClone(m)}deserializeAttachment(){return this.meta}}
 const c={crypto:require('node:crypto').webcrypto,Response:class{constructor(body,opts){Object.assign(this,opts);this.body=body}},URL,Date:class extends Date{static now(){return clock}},TextDecoder,WebSocketPair:class{constructor(){this[0]=new Socket();this[1]=new Socket()}},console};vm.createContext(c);
 vm.runInContext(fs.readFileSync('src/worker.js','utf8').replace('export default','const worker =').replace('export class GameRoom','class GameRoom')+'\nglobalThis.Room=GameRoom;',c);
 const ctx={getWebSockets:()=>sockets,acceptWebSocket:s=>sockets.push(s),waitUntil(){},storage:{setAlarm:()=>Promise.resolve()}};let room=new c.Room(ctx,{});
 async function connect(action){const response=await room.fetch({headers:{get:()=> 'websocket'},url:'https://game.test/ws?room=FLR-ABCDE&mode=3d&action='+action});return {response,ws:sockets.at(-1)}}
 return {get room(){return room},connect,sockets,advance:ms=>clock+=ms,hibernate:()=>{room=new c.Room(ctx,{})}};
}
test('join missing room and duplicate create do not report success',async()=>{
 const s=server();let r=await s.connect('join');assert.equal(r.response.status,404);assert.equal(s.sockets.length,0);
 r=await s.connect('create');assert.equal(r.response.status,101);assert.equal(r.ws.messages[0].type,'welcome3d');
 assert.equal((await s.connect('create')).response.status,409);assert.equal((await s.connect('join')).response.status,101);
});
test('room broadcasts real state, supports map edges, unarmed and sniper, and removes departed player',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 s.room.webSocketMessage(a,JSON.stringify({type:'state3d',name:'Teste A',x:140,y:0,z:-140,angle:0,weapon:'none',grounded:false,crouching:true}));
 let msg=b.messages.find(m=>m.type==='state3d');assert.ok(msg);assert.equal(msg.weapon,'none');assert.equal(msg.grounded,false);assert.equal(msg.crouching,true);
 s.room.webSocketMessage(b,JSON.stringify({type:'state3d',name:'Teste B',x:0,y:0,z:8,angle:0,weapon:'sniper'}));assert.equal(s.room.players.get(b.meta.id).weapon,'sniper');
 s.room.webSocketClose(a);assert.equal(b.messages.at(-1).type,'leave');assert.equal(s.room.players.has(a.meta.id),false);
});
test('client only starts after welcome, propagates movement and handles disconnect',()=>{
 const file='public/multiplayer-client.js';assert.ok(fs.existsSync(file),'multiplayer transport must exist');
 const sockets=[],status=[],ready=[],messages=[];class WS{constructor(url){this.url=url;this.readyState=0;this.sent=[];sockets.push(this)}send(s){this.sent.push(JSON.parse(s))}close(){this.readyState=3}}
 const c={window:{},WebSocket:WS,location:{host:'game.test',protocol:'https:'},URL,console,setTimeout:()=>1,clearTimeout(){}};vm.createContext(c);vm.runInContext(fs.readFileSync(file,'utf8'),c);
 const client=new c.window.MultiplayerClient({onStatus:s=>status.push(s),onReady:s=>ready.push(s),onMessage:m=>messages.push(m)});
 assert.equal(client.connect('join','','Teste'),false);assert.equal(sockets.length,0);
 client.connect('create','FLR-ABCDE','Teste');const ws=sockets[0];assert.match(ws.url,/wss:/);assert.equal(ready.length,0);ws.readyState=1;ws.onopen();assert.equal(ready.length,0);
 ws.onmessage({data:JSON.stringify({type:'welcome3d',id:'a',players:[]})});assert.equal(ready.length,1);assert.equal(client.active,true);
 client.sendState({x:4,y:0,z:8,angle:0});assert.equal(ws.sent.at(-1).name,'Teste');assert.equal(ws.sent.at(-1).type,'state3d');
 ws.onmessage({data:JSON.stringify({type:'state3d',id:'b',x:6})});assert.equal(messages.at(-1).id,'b');ws.onclose();assert.equal(client.active,false);assert.match(status.at(-1),/conexão/i);
 client.connect('join','FLR-FGHIJ','Outro');const next=sockets[1];ws.onmessage({data:JSON.stringify({type:'welcome3d',id:'stale'})});assert.equal(ready.length,1,'stale socket cannot enter an obsolete room');next.onerror();assert.equal(client.active,false);
});

test('full SMG magazine stays within hibernation attachment limit and damage is not replayed',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 for(const [ws,z] of [[a,0],[b,8]])s.room.webSocketMessage(ws,JSON.stringify({type:'state3d',x:0,y:0,z,angle:0,weapon:'smg'}));
 for(let i=0;i<24;i++){
  s.advance(95);s.room.webSocketMessage(a,JSON.stringify({type:'shot3d',shotId:'burst-'+i,weapon:'smg',origin:{x:.123456789,y:1.3,z:.123456789},rays:[{x:.000123456789,y:.00023456789,z:.9999999}]}));
 }
 assert.equal(b.messages.filter(m=>m.type==='shot3d').length,24);
 const hit={type:'hit3d',shotId:'burst-23',pellet:0,targetId:b.meta.id};s.room.webSocketMessage(a,JSON.stringify(hit));assert.equal(s.room.players.get(b.meta.id).health,82);
 s.room.webSocketMessage(a,JSON.stringify(hit));assert.equal(s.room.players.get(b.meta.id).health,82);
});

test('death keeps corpse position, blocks actions and respawns only after five seconds',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 for(const [ws,z]of[[a,0],[b,8]])s.room.webSocketMessage(ws,JSON.stringify({type:'state3d',x:0,y:0,z,angle:0,weapon:'sniper'}));
 for(let i=0;i<2;i++){s.advance(1050);s.room.webSocketMessage(a,JSON.stringify({type:'shot3d',shotId:'kill-'+i,weapon:'sniper',origin:{x:0,y:1.3,z:0},rays:[{x:0,y:0,z:1}]}));s.room.webSocketMessage(a,JSON.stringify({type:'hit3d',shotId:'kill-'+i,pellet:0,targetId:b.meta.id}));}
 let victim=s.room.players.get(b.meta.id);assert.equal(victim.health,0);assert.equal(victim.dead,true);assert.equal(victim.z,8);assert(!b.messages.some(m=>m.type==='respawn3d'));
 s.room.webSocketMessage(b,JSON.stringify({type:'state3d',x:90,y:0,z:90,angle:2,weapon:'sniper'}));assert.equal(s.room.players.get(b.meta.id).z,8,'dead client cannot move corpse');
 s.hibernate();victim=s.room.players.get(b.meta.id);assert(victim.dead,"Death deadline must survive hibernation");s.advance(4999);await s.room.alarm();assert.equal(victim.health,0);s.advance(1);await s.room.alarm();assert.equal(victim.health,100);assert.equal(victim.dead,false);assert.equal(b.messages.filter(m=>m.type==='respawn3d').length,1);
});
