function json(data,status=200){return new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}})}

function deepMotionConfig(env){
 const host=String(env.DEEPMOTION_API_HOST||'').replace(/\/$/,'');
 const clientId=String(env.DEEPMOTION_CLIENT_ID||'');
 const clientSecret=String(env.DEEPMOTION_CLIENT_SECRET||'');
 return {host,clientId,clientSecret,configured:!!(host&&clientId&&clientSecret)};
}

async function deepMotionSession(env){
 const cfg=deepMotionConfig(env);
 if(!cfg.configured)throw new Error('DEEPMOTION_NOT_CONFIGURED');
 const basic=btoa(cfg.clientId+':'+cfg.clientSecret);
 const res=await fetch(cfg.host+'/session/auth',{method:'GET',headers:{Authorization:'Basic '+basic}});
 if(!res.ok)throw new Error('DEEPMOTION_AUTH_'+res.status);
 const cookie=res.headers.get('set-cookie');
 if(!cookie)throw new Error('DEEPMOTION_NO_SESSION_COOKIE');
 return {cfg,cookie:cookie.split(';')[0]};
}

async function handleDeepMotion(request,env,url){
 const cfg=deepMotionConfig(env);
 if(url.pathname==='/api/deepmotion/status'){
  return json({configured:cfg.configured,hostConfigured:!!cfg.host,credentialsConfigured:!!(cfg.clientId&&cfg.clientSecret)});
 }
 if(!cfg.configured)return json({error:'DeepMotion API ainda não configurada no Worker.'},503);
 if(request.method!=='GET'&&request.method!=='POST')return json({error:'Método não permitido.'},405);
 try{
  const {cfg:active,cookie}=await deepMotionSession(env);
  if(url.pathname==='/api/deepmotion/upload-url'&&request.method==='GET'){
   const name=(url.searchParams.get('name')||'motion.mp4').replace(/[^a-zA-Z0-9._-]/g,'_').slice(0,120);
   const upstream=await fetch(active.host+'/upload?resumable=0&name='+encodeURIComponent(name),{headers:{cookie}});
   const body=await upstream.text();
   return new Response(body,{status:upstream.status,headers:{'content-type':upstream.headers.get('content-type')||'application/json','cache-control':'no-store'}});
  }
  if(url.pathname==='/api/deepmotion/process'&&request.method==='POST'){
   const body=await request.json();
   const uploadUrl=String(body?.url||'');
   const modelId=String(body?.modelId||'').trim();
   if(!/^https:\/\//i.test(uploadUrl))return json({error:'URL de upload inválida.'},400);
   const params=['config=configDefault','formats=fbx,bvh','sim=1','footLockingMode=1','rootAtOrigin=1'];
   if(modelId)params.push('model='+modelId.replace(/[^a-zA-Z0-9._-]/g,'').slice(0,120));
   const upstream=await fetch(active.host+'/process',{method:'POST',headers:{cookie,'content-type':'application/json'},body:JSON.stringify({url:uploadUrl,processor:'video2anim',params})});
   const out=await upstream.text();
   return new Response(out,{status:upstream.status,headers:{'content-type':upstream.headers.get('content-type')||'application/json','cache-control':'no-store'}});
  }
  if(url.pathname.startsWith('/api/deepmotion/status/')&&request.method==='GET'){
   const rid=url.pathname.split('/').pop().replace(/[^a-zA-Z0-9._-]/g,'');
   if(!rid)return json({error:'RID inválido.'},400);
   const upstream=await fetch(active.host+'/status/'+encodeURIComponent(rid),{headers:{cookie}});
   const out=await upstream.text();
   return new Response(out,{status:upstream.status,headers:{'content-type':upstream.headers.get('content-type')||'application/json','cache-control':'no-store'}});
  }
  return json({error:'Rota DeepMotion não encontrada.'},404);
 }catch(error){
  const msg=String(error?.message||error);
  if(msg==='DEEPMOTION_NOT_CONFIGURED')return json({error:'DeepMotion API não configurada.'},503);
  return json({error:'Falha ao comunicar com DeepMotion.',detail:msg},502);
 }
}

export default {
 async fetch(request, env) {
  const url = new URL(request.url);
  if (url.pathname === "/ws") {
   const room = (url.searchParams.get("room") || "cidade-1").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 24) || "cidade-1";
   const id = env.GAME_ROOMS.idFromName((url.searchParams.get("mode")==="3d"?"3d:":"")+room);
   return env.GAME_ROOMS.get(id).fetch(request);
  }
  if(url.pathname.startsWith('/api/deepmotion/'))return handleDeepMotion(request,env,url);
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
  const query=new URL(request.url).searchParams;
  if(query.get('mode')==='3d'){
   const action=query.get('action');
   if(action==='join'&&!this.sessions.size)return new Response('Sala não encontrada ou encerrada', {status:404});
   if(action==='create'&&this.sessions.size)return new Response('Código já em uso', {status:409});
   if(this.sessions.size>=8)return new Response('Sala cheia', {status:409});
  }
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
  // Keep only the latest ordered shot across hibernation (attachments are 2 KiB).
  // The active room retains the full short-lived cache in memory.
  const shots=[...this.shots3D.values()].filter(s=>s.ownerId===id&&Date.now()-s.at<2000).slice(-1);
  ws.serializeAttachment({...meta,state:this.players.get(id),shots});
 }
 handle3D(ws,meta,data){
  const finite=(v,min,max)=>typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max;
  const weapons={pistol:{damage:30,range:65,delay:60/340*1000,pellets:1},smg:{damage:18,range:45,delay:95,pellets:1},rifle:{damage:28,range:85,delay:140,pellets:1},shotgun:{damage:11,range:28,delay:850,pellets:6},sniper:{damage:95,range:220,delay:1050,pellets:1}};
  const now=Date.now();for(const [id,shot]of this.shots3D)if(now-shot.at>2000)this.shots3D.delete(id);
  if(data.type==='state3d'){
   if(!finite(data.x,-160,160)||!finite(data.y,-25,150)||!finite(data.z,-160,160)||!finite(data.angle,-1000,1000))return;
   const prev=this.players.get(meta.id);
   if(prev?.dead){this.broadcast3D(prev);return;}
   const state={type:'state3d',id:meta.id,name:String(data.name||'Jogador').slice(0,18),x:data.x,y:data.y,z:data.z,angle:data.angle,
    moving:!!data.moving,running:!!data.running,climbing:!!data.climbing,aiming:!!data.aiming,inCar:!!data.inCar,
    grounded:data.grounded!==false,crouching:!!data.crouching,verticalVelocity:finite(data.verticalVelocity,-100,100)?data.verticalVelocity:0,weapon:data.weapon==='none'?'none':weapons[data.weapon]?data.weapon:'pistol',pitch:finite(data.pitch,-1.5,1.5)?data.pitch:0,
    dead:false,deadUntil:0,health:prev?.health??100,kills:prev?.kills??0,lastShot:prev?.lastShot??0};
   this.players.set(meta.id,state);this.save3D(meta.id);this.broadcast3D(state);if(!prev)this.broadcastRanking();return;
  }
  const shooter=this.players.get(meta.id);if(!shooter||shooter.dead)return;
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
   if(!shot||!Number.isInteger(pellet)||!shot.rays[pellet]||shot.used[pellet]||!target||target.dead||target.id===meta.id)return;
   const ray=shot.rays[pellet],spec=weapons[shot.weapon];
   const dx=target.x-shot.origin.x,dy=target.y+1.5-shot.origin.y,dz=target.z-shot.origin.z;
   const along=dx*ray.x+dy*ray.y+dz*ray.z;
   if(along<-.25||along>spec.range+2||Math.hypot(dx-along*ray.x,dy-along*ray.y,dz-along*ray.z)>1.6)return;
   shot.used[pellet]=true;target.health=Math.max(0,target.health-spec.damage);
   const killed=target.health===0;
   if(killed){shooter.kills++;target.dead=true;target.deadUntil=now+5000;target.moving=false;target.running=false;target.aiming=false;}
   this.broadcast3D({type:'hit3d',shotId:shot.shotId,attackerId:meta.id,targetId:target.id,health:target.health,damage:spec.damage,killed,respawnIn:killed?5:0,kills:shooter.kills});
   if(killed){
    this.broadcast3D(target);this.scheduleRespawns();this.broadcastRanking();
   }
   this.save3D(meta.id);this.save3D(target.id);
  }
 }

 scheduleRespawns(){
  const deadlines=[...this.players.values()].filter(p=>p.dead).map(p=>p.deadUntil);
  if(deadlines.length)this.ctx.waitUntil(this.ctx.storage.setAlarm(Math.min(...deadlines)));
 }
 async alarm(){
  const now=Date.now();
  for(const target of this.players.values())if(target.dead&&target.deadUntil<=now){
   Object.assign(target,{dead:false,deadUntil:0,health:100,x:4,y:0,z:8,moving:false,running:false,aiming:false,grounded:true,verticalVelocity:0,lastShot:0});
   this.save3D(target.id);this.broadcast3D({type:'respawn3d',id:target.id,x:4,y:0,z:8,health:100,dead:false});this.broadcast3D(target);
  }
  this.scheduleRespawns();
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
