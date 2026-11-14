const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
function server(){
 let clock=10000;const sockets=[];class Socket{constructor(){this.messages=[]}send(s){this.messages.push(JSON.parse(s))}serializeAttachment(m){assert.ok(require('node:v8').serialize(m).length<=2048,'Cloudflare attachment exceeds 2048 bytes');this.meta=structuredClone(m)}deserializeAttachment(){return this.meta}}
 const c={crypto:require('node:crypto').webcrypto,Response:class{constructor(body,opts){Object.assign(this,opts);this.body=body}},URL,Date:class extends Date{static now(){return clock}},TextDecoder,WebSocketPair:class{constructor(){this[0]=new Socket();this[1]=new Socket()}},console};vm.createContext(c);
 vm.runInContext(fs.readFileSync('public/tactical-rules.js','utf8'),c);vm.runInContext(fs.readFileSync('src/tactical-room.js','utf8'),c);
 vm.runInContext(fs.readFileSync('src/worker.js','utf8').replace(/^import .*;\n/gm,'').replace('export default','const worker =').replace('export class GameRoom','class GameRoom')+'\nglobalThis.Room=GameRoom;',c);
 const pending=[],stored=new Map();let ready=Promise.resolve();const ctx={getWebSockets:()=>sockets,acceptWebSocket:s=>sockets.push(s),waitUntil:p=>pending.push(p),blockConcurrencyWhile:fn=>{ready=Promise.resolve(fn());return ready},storage:{setAlarm:()=>Promise.resolve(),put:async(k,v)=>stored.set(k,structuredClone(v)),get:async k=>structuredClone(stored.get(k))}};let room=new c.Room(ctx,{});
 async function connect(action){await ready;const response=await room.fetch({headers:{get:()=> 'websocket'},url:'https://game.test/ws?room=FLR-ABCDE&mode=3d&action='+action});return {response,ws:sockets.at(-1)}}
 return {get room(){return room},connect,sockets,advance:ms=>clock+=ms,rules:c.TacticalRules,settle:async()=>{await ready;while(pending.length)await Promise.all(pending.splice(0))},hibernate:()=>{room=new c.Room(ctx,{});return ready}};
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


test('server grants finite equipment, explodes grenades authoritatively and persists live gear across hibernation',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 for(const [ws,x]of[[a,0],[b,8]])s.room.webSocketMessage(ws,JSON.stringify({type:'state3d',x,y:0,z:0,angle:0,weapon:'pistol',grenades:999}));
 s.room.webSocketMessage(a,JSON.stringify({type:'gear3d',kind:'grenade',direction:{x:0,y:-.6,z:-.8}}));
 const thrown=b.messages.find(m=>m.type==='grenade3d');assert(thrown,'A real grenade must be broadcast');assert.equal(s.room.players.get(a.meta.id).grenades,2);
 const predicted=structuredClone(thrown.grenade);s.rules.advance(predicted,2.8,s.rules.mapBoxes());
 s.room.webSocketMessage(b,JSON.stringify({type:'state3d',x:predicted.position.x,y:0,z:predicted.position.z+1,angle:0,weapon:'pistol'}));
 await s.settle();await s.hibernate();s.advance(2801);await s.room.alarm();assert(b.messages.some(m=>m.type==='explosion3d'));assert(s.room.players.get(b.meta.id).health<100,'Server evaluates blast damage');
 const health=s.room.players.get(b.meta.id).health;await s.room.alarm();assert.equal(s.room.players.get(b.meta.id).health,health,'Alarm retries cannot replay a grenade');
 s.room.webSocketMessage(a,JSON.stringify({type:'state3d',x:0,y:0,z:0,angle:0,weapon:'pistol',grenades:999}));assert.equal(s.room.players.get(a.meta.id).grenades,2,'Client cannot forge charges');
});

test('ice is shared with late joiners, stops forged bullet hits, takes damage and expires',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 for(const [ws,z]of[[a,0],[b,-6]])s.room.webSocketMessage(ws,JSON.stringify({type:'state3d',x:0,y:0,z,angle:0,weapon:'pistol'}));
 s.room.webSocketMessage(a,JSON.stringify({type:'gear3d',kind:'ice',direction:{x:0,y:0,z:-1}}));const event=b.messages.find(m=>m.type==='icewall3d');assert(event,'Instant ice must be shared');assert.equal(s.room.players.get(a.meta.id).iceCharges,2);
 const late=(await s.connect('join')).ws;assert.equal(late.messages[0].tactical.walls.length,1);
 for(let i=0;i<9;i++){
  s.advance(200);s.room.webSocketMessage(a,JSON.stringify({type:'shot3d',shotId:'ice-'+i,weapon:'pistol',origin:{x:0,y:1.3,z:0},rays:[{x:0,y:0,z:-1}]}));s.room.webSocketMessage(a,JSON.stringify({type:'hit3d',shotId:'ice-'+i,pellet:0,targetId:b.meta.id}));
 }
 assert.equal(s.room.players.get(b.meta.id).health,100,'Even the ice-breaking bullet cannot pass through');assert(b.messages.some(m=>m.type==='icewall-remove3d'&&m.destroyed));
 s.advance(500);s.room.webSocketMessage(a,JSON.stringify({type:'gear3d',kind:'ice',direction:{x:0,y:0,z:-1}}));await s.settle();await s.hibernate();s.advance(25001);await s.room.alarm();assert.equal(s.room.tactical.walls.size,0);
});

test('posture and jetpack survive broadcast, late join and hibernation with bounded inputs',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 const state={type:'state3d',x:0,y:0,z:0,angle:0,weapon:'rifle',grounded:true,crouching:true,crouchBlend:.75,prone:1,proneSlope:.2,proneRoll:-.1,speed:1.15,jetpack:true,jetpackActive:true};
 s.room.webSocketMessage(a,JSON.stringify(state));
 const replicated=b.messages.filter(m=>m.id===a.meta.id&&m.type==='state3d').at(-1);
 for(const key of ['crouchBlend','prone','proneSlope','proneRoll','speed','jetpack','jetpackActive'])assert.equal(replicated[key],state[key],key);
 await s.settle();await s.hibernate();const late=(await s.connect('join')).ws;
 assert.equal(late.messages[0].players.find(p=>p.id===a.meta.id).prone,1);
 assert.equal(s.room.players.get(a.meta.id).jetpack,true);
 s.room.webSocketMessage(a,JSON.stringify({...state,prone:9,proneSlope:900,proneRoll:-900,speed:999,jetpack:false}));
 const safe=s.room.players.get(a.meta.id);assert.equal(safe.prone,0);assert.equal(safe.proneSlope,0);assert.equal(safe.proneRoll,0);assert.equal(safe.speed,0);assert.equal(safe.jetpackActive,false);
});

test('server rejects shots over a prone body and accepts torso hits in every posture',async()=>{
 const s=server(),a=(await s.connect('create')).ws,b=(await s.connect('join')).ws;
 const state=(z,extra={})=>({type:'state3d',x:0,y:0,z,angle:0,weapon:'pistol',...extra});
 s.room.webSocketMessage(a,JSON.stringify(state(0)));let sequence=0;
 const fire=(height)=>{s.advance(200);const shotId='posture-'+sequence++;s.room.webSocketMessage(a,JSON.stringify({type:'shot3d',weapon:'pistol',shotId,origin:{x:0,y:height,z:0},rays:[{x:0,y:0,z:1}]}));s.room.webSocketMessage(a,JSON.stringify({type:'hit3d',shotId,pellet:0,targetId:b.meta.id}));};
 for(const [pose,height,expectedHealth]of[[{prone:1,crouching:true},.3,77],[{crouching:true},.85,64],[{},1.4,70]]){
  s.room.webSocketMessage(b,JSON.stringify(state(6,pose)));
  s.room.players.get(b.meta.id).health=100;
  if(pose.prone){fire(1.5);assert.equal(s.room.players.get(b.meta.id).health,100,'empty air above crawling target');}
  if(pose.crouching&&!pose.prone){fire(1.65);assert.equal(s.room.players.get(b.meta.id).health,100,'empty air above crouched target');}
  fire(height);assert.equal(s.room.players.get(b.meta.id).health,expectedHealth,'damage must reflect the struck body zone and posture');
 }
});
