const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
function server(){
 const objects=new Map(),pending=[];
 class Socket{send(){}serializeAttachment(meta){this.meta=structuredClone(meta)}deserializeAttachment(){return this.meta}}
 class Reply{constructor(body,opts={}){this.body=body;this.status=opts.status||200;this.headers=new Headers(opts.headers);this.ok=this.status<400}async json(){return JSON.parse(this.body)}}
 const c={URL,Request,Response:Reply,crypto:require('node:crypto').webcrypto,console,Date,TextDecoder,WebSocketPair:class{constructor(){this[0]=new Socket();this[1]=new Socket()}}};vm.createContext(c);
 vm.runInContext(fs.readFileSync('public/tactical-rules.js','utf8'),c);vm.runInContext(fs.readFileSync('src/tactical-room.js','utf8'),c);
 vm.runInContext(fs.readFileSync('src/worker.js','utf8').replace(/^import .*;\n/gm,'').replace('export default','const worker =').replace('export class GameRoom','class GameRoom')+'\nglobalThis.api={worker,GameRoom};',c);
 const env={ASSETS:{fetch:()=>new Reply('asset',{status:404})},GAME_ROOMS:{idFromName:n=>n,get(id){if(!objects.has(id)){
  const sockets=[],data=new Map(),storage={async get(k){return data.get(k)},async put(k,v){data.set(k,v)},async delete(k){data.delete(k)},async list(options={}){return new Map([...data].filter(([k])=>(!options.prefix||k.startsWith(options.prefix))&&(!options.startAfter||k>options.startAfter)).sort(([a],[b])=>a.localeCompare(b)).slice(0,options.limit||1000))},async transaction(fn){return fn(storage)},async setAlarm(){}};
  const ctx={getWebSockets:()=>sockets,acceptWebSocket:s=>sockets.push(s),waitUntil:p=>pending.push(p),storage};
  const record={ctx,sockets};record.room=new c.api.GameRoom(ctx,env);objects.set(id,record);
 }return {fetch:async r=>{const request=typeof r==='string'?new Request(r):r,record=objects.get(id),response=await record.room.fetch(request);return request.url.includes('/internal/room-info')&&record.infoHook?record.infoHook(response):response}}}}};
 return {objects,env,async settle(){while(pending.length)await Promise.all(pending.splice(0));},async connect(code,action='create',visibility='public'){return c.api.worker.fetch(new Request('https://game.test/ws?mode=3d&room='+code+'&action='+action+'&visibility='+visibility,{headers:{Upgrade:'websocket'}}),env)},async list(cursor=''){return c.api.worker.fetch(new Request('https://game.test/api/rooms?cursor='+encodeURIComponent(cursor)),env)},hibernate(id){const o=objects.get(id);o.room=new c.api.GameRoom(o.ctx,env)}};
}
test('public room listing reflects real occupancy, survives hibernation, hides private and closed rooms',async()=>{
 const s=server();assert.equal((await s.list()).status,200,'Room directory endpoint must exist');assert.deepEqual((await (await s.list()).json()).rooms,[]);
 assert.equal((await s.connect('FLR-ABCDE')).status,101);await s.settle();
 await s.connect('FLR-PRIV1','create','private');await s.settle();s.hibernate('public-room-directory');
 let rooms=(await (await s.list()).json()).rooms;assert.equal(rooms.length,1);assert.equal(rooms[0].code,'FLR-ABCDE');assert.equal(rooms[0].players,1);assert.equal(rooms[0].capacity,8);
 await s.connect('FLR-ABCDE','join','private');s.hibernate('3d:flr-abcde');rooms=(await (await s.list()).json()).rooms;assert.equal(rooms[0].players,2,'Joiner cannot change visibility');
 for(let n=0;n<6;n++)await s.connect('FLR-ABCDE','join');assert.equal((await s.connect('FLR-ABCDE','join')).status,409);rooms=(await (await s.list()).json()).rooms;assert.equal(rooms[0].players,8);
 const record=s.objects.get('3d:flr-abcde');for(const socket of record.sockets)record.room.drop(socket);await s.settle();assert.deepEqual((await (await s.list()).json()).rooms,[]);
 assert.equal((await s.connect('FLR-PRIV1','join')).status,101,'Private rooms remain joinable by code');
});

test('transport sets room visibility explicitly',()=>{
 const urls=[],c={window:{},location:{protocol:'https:',host:'game.test'},setTimeout(){},clearTimeout(){},WebSocket:class{constructor(url){urls.push(url)}close(){}}};vm.createContext(c);vm.runInContext(fs.readFileSync('public/multiplayer-client.js','utf8'),c);
 const client=new c.window.MultiplayerClient();client.connect('create','FLR-ABCDE','Teste','private');assert.equal(new URL(urls[0]).searchParams.get('visibility'),'private');
 client.connect('create','FLR-FGHIJ','Teste','public');assert.equal(new URL(urls[1]).searchParams.get('visibility'),'public');
});


test('directory pagination exposes public rooms beyond the first forty',async()=>{
 const s=server();for(let n=0;n<42;n++)await s.connect('FLR-'+String(n).padStart(5,'0'));await s.settle();
 const first=await (await s.list()).json();assert.equal(first.rooms.length,40);assert(first.cursor,'Additional rooms need a continuation cursor');
 const second=await (await s.list(first.cursor)).json();assert.equal(second.rooms.length,2);assert.equal(new Set([...first.rooms,...second.rooms].map(r=>r.code)).size,42);assert(!second.cursor);
});

test('stale empty-room cleanup cannot delete a new registration for the same code',async()=>{
 const s=server();await s.connect('FLR-ABCDE');await s.settle();const record=s.objects.get('3d:flr-abcde');record.room.drop(record.sockets[0]);
 let release,started;const intercepted=new Promise(r=>started=r);record.infoHook=response=>{started();return new Promise(r=>release=()=>r(response))};
 const stale=s.list();await intercepted;await s.connect('FLR-ABCDE');await s.settle();record.infoHook=null;release();await stale;
 assert((await (await s.list()).json()).rooms.some(r=>r.code==='FLR-ABCDE'),'Recreated active room must remain discoverable');
});
