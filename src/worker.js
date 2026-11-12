export default {
 async fetch(request, env) {
  const url = new URL(request.url);
  if (url.pathname === "/ws") {
   const room = (url.searchParams.get("room") || "cidade-1").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 24) || "cidade-1";
   const id = env.GAME_ROOMS.idFromName((url.searchParams.get("mode")==="3d"?"3d:":"")+room);
   return env.GAME_ROOMS.get(id).fetch(request);
  }
  return env.ASSETS.fetch(request);
 }
};

export class GameRoom {
 constructor(ctx, env) {
  this.ctx = ctx;
  this.sessions = new Map();
  this.players = new Map();
  this.shots3D = new Map();
  for (const ws of ctx.getWebSockets()) {
   const data = ws.deserializeAttachment();
   if (data?.id){this.sessions.set(data.id,ws);if(data.state)this.players.set(data.id,data.state);for(const shot of data.shots||[])if(Date.now()-shot.at<2000)this.shots3D.set(data.id+":"+shot.shotId,shot)}
  }
 }
 async fetch(request) {
  if (request.headers.get("Upgrade") !== "websocket") return new Response("WebSocket required", {status: 426});
  const pair = new WebSocketPair();
  const client = pair[0], server = pair[1];
  const id = crypto.randomUUID().slice(0, 8);
  this.ctx.acceptWebSocket(server);
  const mode=new URL(request.url).searchParams.get("mode")==="3d"?"3d":"2d";
  server.serializeAttachment({id,mode});
  this.sessions.set(id, server);
  server.send(JSON.stringify(mode==="3d"?{type:"welcome3d",id,players:[...this.players.values()]}:{type:"welcome",id}));
  return new Response(null, {status:101, webSocket:client});
 }
 webSocketMessage(ws, message) {
  const meta = ws.deserializeAttachment();
  if (!meta?.id) return;
  let data;
  try { data = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message)); } catch { return; }
  if(!data||typeof data!=="object")return;
  if(meta.mode==="3d"){this.handle3D(ws,meta,data);return}
  if (data.type === "kill") {
   const prev=this.players.get(meta.id)||{name:String(data.name||"Jogador").slice(0,18),kills:0};
   prev.kills=(prev.kills||0)+1;this.players.set(meta.id,prev);this.broadcastRanking();return;
  }
  if (data.type === "shot") {
   const safe={type:"shot",id:meta.id,weapon:String(data.weapon||"pistol").slice(0,12),
    x:Number(data.x)||0,y:Number(data.y)||0,vx:Number(data.vx)||0,vy:Number(data.vy)||0,
    t:Math.max(.05,Math.min(3,Number(data.t)||1)),damage:Math.max(1,Math.min(10,Number(data.damage)||1)),
    color:String(data.color||"#7ee8ff").slice(0,16),layer:data.layer===null?null:Number(data.layer)};
   const out=JSON.stringify(safe);for(const [id,peer] of this.sessions)if(id!==meta.id){try{peer.send(out)}catch{}}return;
  }
  if (data.type === "hit") {
   const targetId=String(data.targetId||"");if(!this.sessions.has(targetId))return;
   const out=JSON.stringify({type:"hit",targetId,attackerId:meta.id,damage:Math.max(1,Math.min(10,Number(data.damage)||1))});
   try{this.sessions.get(targetId).send(out)}catch{} return;
  }
  if (data.type === "killed") {
   const killerId=String(data.killerId||"");
   if(killerId&&this.players.has(killerId)){
    const kp=this.players.get(killerId);kp.kills=(kp.kills||0)+1;this.players.set(killerId,kp);this.broadcastRanking();
   }
   return;
  }
  if (data.type !== "state") return;
  const safe = {
   type:"state", id:meta.id,
   name:String(data.name || "Jogador").slice(0,18),
   x:Number(data.x)||0, y:Number(data.y)||0, angle:Number(data.angle)||0,
   inCar:!!data.inCar, shooting:!!data.shooting, kills:Number(data.kills)||0,
   health:Math.max(0,Math.min(100,Number(data.health)||0)),dead:!!data.dead,
   roof:data.roof===null?null:Number(data.roof)
  };
  const prev=this.players.get(meta.id)||{};this.players.set(meta.id,{...prev,name:safe.name,kills:prev.kills??safe.kills});
  safe.kills=(this.players.get(meta.id)?.kills)||0;
  const out = JSON.stringify(safe);
  for (const [id, peer] of this.sessions) if (id !== meta.id) {
   try { peer.send(out); } catch {}
  }
 }
 broadcast3D(data){const out=JSON.stringify(data);for(const peer of this.sessions.values()){try{peer.send(out)}catch{}}}
 save3D(id){
  const ws=this.sessions.get(id);if(!ws)return;
  const meta=ws.deserializeAttachment();
  const shots=[...this.shots3D.values()].filter(s=>s.ownerId===id&&Date.now()-s.at<2000);
  ws.serializeAttachment({...meta,state:this.players.get(id),shots});
 }
 handle3D(ws,meta,data){
  const finite=(v,min,max)=>typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max;
  const weapons={pistol:{damage:12,speed:42,delay:240,pellets:1},smg:{damage:7,speed:46,delay:85,pellets:1},rifle:{damage:20,speed:58,delay:190,pellets:1},shotgun:{damage:6,speed:38,delay:620,pellets:7}};
  const now=Date.now();for(const [id,shot]of this.shots3D)if(now-shot.at>2000)this.shots3D.delete(id);
  if(data.type==='state3d'){
   if(!finite(data.x,-100,100)||!finite(data.y,-2,25)||!finite(data.z,-100,100)||!finite(data.angle,-1000,1000))return;
   const prev=this.players.get(meta.id);
   const state={type:'state3d',id:meta.id,name:String(data.name||'Jogador').slice(0,18),x:data.x,y:data.y,z:data.z,angle:data.angle,
    moving:!!data.moving,running:!!data.running,climbing:!!data.climbing,aiming:!!data.aiming,inCar:!!data.inCar,
    weapon:weapons[data.weapon]?data.weapon:'pistol',pitch:finite(data.pitch,-1.5,1.5)?data.pitch:0,
    health:prev?.health??100,kills:prev?.kills??0,lastShot:prev?.lastShot??0};
   this.players.set(meta.id,state);this.save3D(meta.id);this.broadcast3D(state);if(!prev)this.broadcastRanking();return;
  }
  const shooter=this.players.get(meta.id);if(!shooter)return;
  if(data.type==='shot3d'){
   const spec=weapons[data.weapon];if(!spec||now-shooter.lastShot<spec.delay*.72)return;
   if(!/^[a-z0-9-]{1,32}$/.test(String(data.shotId||'')))return;
   const origin=data.origin;if(!origin||![origin.x,origin.y,origin.z].every(Number.isFinite))return;
   if(Math.hypot(origin.x-shooter.x,origin.y-shooter.y-1.3,origin.z-shooter.z)>3)return;
   if(!Array.isArray(data.rays)||data.rays.length!==spec.pellets)return;
   const rays=[];for(const ray of data.rays){
    if(!ray||![ray.x,ray.y,ray.z].every(Number.isFinite))return;
    const length=Math.hypot(ray.x,ray.y,ray.z);if(length<.5||length>1.5)return;
    rays.push({x:ray.x/length,y:ray.y/length,z:ray.z/length});
   }
   const key=meta.id+':'+data.shotId;if(this.shots3D.has(key))return;
   shooter.lastShot=now;
   const shot={type:'shot3d',ownerId:meta.id,shotId:String(data.shotId),weapon:data.weapon,origin,rays,at:now,used:{}};
   this.shots3D.set(key,shot);this.save3D(meta.id);this.broadcast3D(shot);return;
  }
  if(data.type==='hit3d'){
   const shot=this.shots3D.get(meta.id+':'+String(data.shotId));
   const pellet=data.pellet,target=this.players.get(String(data.targetId));
   if(!shot||!Number.isInteger(pellet)||!shot.rays[pellet]||shot.used[pellet]||!target||target.id===meta.id)return;
   const ray=shot.rays[pellet],spec=weapons[shot.weapon];
   const dx=target.x-shot.origin.x,dy=target.y+1.5-shot.origin.y,dz=target.z-shot.origin.z;
   const along=dx*ray.x+dy*ray.y+dz*ray.z;
   if(along<-.25||along>spec.speed*1.15+2||Math.hypot(dx-along*ray.x,dy-along*ray.y,dz-along*ray.z)>1.6)return;
   shot.used[pellet]=true;target.health=Math.max(0,target.health-spec.damage);
   const killed=target.health===0;
   if(killed)shooter.kills++;
   this.broadcast3D({type:'hit3d',attackerId:meta.id,targetId:target.id,health:target.health,damage:spec.damage,killed,kills:shooter.kills});
   if(killed){
    target.health=100;target.x=4;target.y=0;target.z=8;target.moving=false;
    this.broadcast3D({type:'respawn3d',id:target.id,x:4,y:0,z:8,health:100});this.broadcastRanking();
   }
   this.save3D(meta.id);this.save3D(target.id);
  }
 }

 broadcastRanking(){
  const players=[...this.players.entries()].map(([id,p])=>({id,name:p.name||"Jogador",kills:p.kills||0})).sort((a,b)=>b.kills-a.kills);
  const out=JSON.stringify({type:"ranking",players});
  for(const peer of this.sessions.values()){try{peer.send(out)}catch{}}
 }
 webSocketClose(ws) { this.drop(ws); }
 webSocketError(ws) { this.drop(ws); }
 drop(ws) {
  const meta = ws.deserializeAttachment();
  if (!meta?.id) return;
  this.sessions.delete(meta.id);this.players.delete(meta.id);for(const [key,shot]of this.shots3D)if(shot.ownerId===meta.id)this.shots3D.delete(key);this.broadcastRanking();
  const out = JSON.stringify({type:"leave", id:meta.id});
  for (const peer of this.sessions.values()) { try { peer.send(out); } catch {} }
 }
}