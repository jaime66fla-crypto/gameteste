export default {
 async fetch(request, env) {
  const url = new URL(request.url);
  if (url.pathname === "/ws") {
   const room = (url.searchParams.get("room") || "cidade-1").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 24) || "cidade-1";
   const id = env.GAME_ROOMS.idFromName(room);
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
  for (const ws of ctx.getWebSockets()) {
   const data = ws.deserializeAttachment();
   if (data?.id) this.sessions.set(data.id, ws);
  }
 }
 async fetch(request) {
  if (request.headers.get("Upgrade") !== "websocket") return new Response("WebSocket required", {status: 426});
  const pair = new WebSocketPair();
  const client = pair[0], server = pair[1];
  const id = crypto.randomUUID().slice(0, 8);
  this.ctx.acceptWebSocket(server);
  server.serializeAttachment({id});
  this.sessions.set(id, server);
  server.send(JSON.stringify({type:"welcome", id}));
  return new Response(null, {status:101, webSocket:client});
 }
 webSocketMessage(ws, message) {
  const meta = ws.deserializeAttachment();
  if (!meta?.id) return;
  let data;
  try { data = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message)); } catch { return; }
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
  this.sessions.delete(meta.id);this.players.delete(meta.id);this.broadcastRanking();
  const out = JSON.stringify({type:"leave", id:meta.id});
  for (const peer of this.sessions.values()) { try { peer.send(out); } catch {} }
 }
}