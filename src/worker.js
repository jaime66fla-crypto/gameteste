import '../public/tactical-rules.js';
import './tactical-room.js';
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
  if(url.pathname==='/api/rooms'){
   if(request.method!=='GET')return json({error:'Método não permitido.'},405);
   try{
    const directory=env.GAME_ROOMS.get(env.GAME_ROOMS.idFromName('public-room-directory'));
    return await directory.fetch(new Request('https://internal/internal/public-rooms'+url.search));
   }catch{return json({error:'Não foi possível carregar as salas. Tente atualizar.'},503);}
  }
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
  this.env = env;
  this.sessions = new Map();
  this.players = new Map();
  this.shots3D = new Map();
  for (const ws of ctx.getWebSockets()) {
   const data = ws.deserializeAttachment();
   if (data?.id){this.sessions.set(data.id,ws);if(data.state)this.players.set(data.id,data.state);for(const shot of data.shots||[])if(Date.now()-shot.at<2000)this.shots3D.set(data.id+":"+shot.shotId,shot)}
  }
  // Battle Royale state is copied into WebSocket attachments for hibernation recovery.
  const previous=[...this.sessions.values()][0]?.deserializeAttachment()?.battle;
  this.battle=previous?{...previous,roster:[...previous.roster]}:{enabled:false,phase:'waiting',roster:[],winnerId:null,deadline:0,bots:[]};
  for(const bot of this.battle.bots||[])this.players.set(bot.id,{...bot,type:'state3d',weapon:'rifle',attachments:{},gear:'none',grounded:bot.grounded!==false,moving:!!bot.moving,running:false,lastShot:0});
  this.tactical=new globalThis.TacticalRoom(this,ctx);
 }
 async fetch(request) {
  const url=new URL(request.url);
  // These paths are called only by other Durable Objects, never forwarded from the public Worker.
  if(url.pathname==='/internal/room-info'){
   const meta=this.sessions.values().next().value?.deserializeAttachment();
   return json({public:meta?.publicRoom===true,players:this.sessions.size,capacity:8,phase:this.battle.phase});
  }
  if(url.pathname==='/internal/public-rooms'){
   if(request.method==='POST'){
    const {code}=await request.json();
    if(!/^flr-[a-z0-9]{5}$/.test(String(code)))return json({error:'Código inválido.'},400);
    await this.ctx.storage.put('room:'+code,{code,token:crypto.randomUUID()});return json({ok:true});
   }
   if(request.method!=='GET')return json({error:'Método não permitido.'},405);
   const cursor=url.searchParams.get('cursor')||'';
   if(cursor&&!/^room:flr-[a-z0-9]{5}$/.test(cursor))return json({error:'Página inválida.'},400);
   const entries=[...await this.ctx.storage.list({prefix:'room:',limit:41,...(cursor?{startAfter:cursor}:{})})];
   const page=entries.slice(0,40),nextCursor=entries.length>40?page.at(-1)[0]:null;
   const rooms=(await Promise.all(page.map(async([key,entry])=>{
    const code=typeof entry==='string'?entry:entry.code,token=entry?.token;
    try{
     const room=this.env.GAME_ROOMS.get(this.env.GAME_ROOMS.idFromName('3d:'+code));
     const response=await room.fetch(new Request('https://internal/internal/room-info'));
     if(!response.ok)return null;
     const info=await response.json();
     if(!info.public||info.players<1){
      await this.ctx.storage.transaction(async tx=>{const current=await tx.get(key);if(current&&(typeof current==='string'?current===entry:current.token===token))await tx.delete(key);});
      return null;
     }
     return {code:code.toUpperCase(),players:info.players,capacity:8};
    }catch{return null;}
   }))).filter(Boolean);
   rooms.sort((a,b)=>(a.players===8)-(b.players===8)||b.players-a.players||a.code.localeCompare(b.code));
   return json({rooms,cursor:nextCursor});
  }
  if (request.headers.get("Upgrade") !== "websocket") return new Response("WebSocket required", {status: 426});
  const query=new URL(request.url).searchParams;
  if(query.get('mode')==='3d'){
   const action=query.get('action');
   if(action==='join'&&!this.sessions.size)return new Response('Sala não encontrada ou encerrada', {status:404});
   if(this.battle.enabled&&this.battle.phase!=='waiting')return new Response('Partida em andamento ou encerrada', {status:409});
   if(this.sessions.size&&this.battle.enabled!==(query.get('battle')==='1'))return new Response('Modo de sala incompatível',{status:409});
   if(action==='create'&&this.sessions.size)return new Response('Código já em uso', {status:409});
   if(this.sessions.size>=8)return new Response('Sala cheia', {status:409});
  }
  const pair = new WebSocketPair();
  const client = pair[0], server = pair[1];
  const id = crypto.randomUUID().slice(0, 8);
  this.ctx.acceptWebSocket(server);
  const mode=new URL(request.url).searchParams.get("mode")==="3d"?"3d":"2d";
  const first=this.sessions.values().next().value?.deserializeAttachment();
  const publicRoom=mode==='3d'&&(first?first.publicRoom===true:query.get('visibility')==='public');
  const battle=mode==='3d'&&(this.battle.enabled||query.get('battle')==='1');
  if(battle&&!this.battle.enabled&&this.sessions.size===0)this.battle={enabled:true,phase:'waiting',roster:[],winnerId:null,deadline:Date.now()+20000,bots:[]};
  const name=String(query.get('name')||'Operador').slice(0,16);
  server.serializeAttachment({id,mode,publicRoom,battle:{...this.battle,roster:[...this.battle.roster]}});
  this.sessions.set(id, server);
  if(this.battle.enabled&&mode==='3d'){
   this.players.set(id,{type:'state3d',id,name,health:100,dead:false,x:0,y:0,z:0,angle:0,kills:0,weapon:'none',gear:'none',attachments:{},grounded:true,moving:false,running:false,aiming:false,lastShot:0});
   this.battle.roster.push(id);
   this.save3D(id);
  }
  if(publicRoom&&query.get('action')==='create'){
   const code=(query.get('room')||'').toLowerCase().replace(/[^a-z0-9-]/g,'').slice(0,24);
   const directory=this.env.GAME_ROOMS.get(this.env.GAME_ROOMS.idFromName('public-room-directory'));
   this.ctx.waitUntil(directory.fetch(new Request('https://internal/internal/public-rooms',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({code})})).catch(error=>console.error('Room directory registration failed',error)));
  }
  server.send(JSON.stringify(mode==="3d"?{type:"welcome3d",id,players:[...this.players.values()],tactical:this.tactical.snapshot(),battle:this.battle.enabled}:{type:"welcome",id}));
  if(this.battle.enabled&&mode==='3d'){
   if(this.battle.phase==='waiting'&&this.sessions.size===8){
    this.startBattle();
   }else{
    this.syncBattleAttachments();
    this.broadcastBattleStatus();this.scheduleRespawns();
   }
  }
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
 startBattle(){
  if(!this.battle.enabled||this.battle.phase!=='waiting')return;
  const missing=Math.max(0,8-this.sessions.size);this.battle.bots=[];
  for(let n=0;n<missing;n++){
   const id='bot-'+n,angle=2*Math.PI*n/Math.max(1,missing);
   const bot={type:'state3d',id,name:'BOT '+String(n+1).padStart(2,'0'),bot:true,
    x:-90,y:110,z:0,angle:Math.PI/2,
    health:100,dead:false,deadUntil:0,kills:0,weapon:'rifle',attachments:{},gear:'none',
    moving:false,running:false,grounded:false,aiming:false,lastShot:0,lastBotAttack:0,
    dropPhase:'plane',dropAt:Date.now()+4000+n*2700,landingX:Math.cos(angle)*(25+n*5),landingZ:Math.sin(angle)*(25+n*5),jumpX:0,jumpAt:0};
   this.players.set(id,bot);this.battle.roster.push(id);this.battle.bots.push({...bot});
  }
  this.battle.phase='running';
  const now=Date.now();this.battle.startedAt=now;
  this.battle.zone={phase:0,centerX:0,centerZ:0,radius:115,fromX:0,fromZ:0,fromRadius:115,
   toX:0,toZ:0,toRadius:115,stage:'hidden',stageStarted:now,stageEnds:now+60000,lastDamageAt:now};
  this.syncBattleAttachments();
  this.broadcast3D({type:'battle-start',total:8,alive:8,bots:this.battle.bots,players:[...this.players.values()]});
  this.broadcastBattleStatus();this.scheduleRespawns();
 }
 advanceSafeZone(now){
  const zone=this.battle.zone;
  if(!zone||this.battle.phase!=='running')return;
  if(zone.stage==='hidden'){
   if(now<zone.stageEnds)return;
   zone.stage='waiting';zone.stageStarted=now;zone.stageEnds=now+30000;zone.lastDamageAt=now;
   this.broadcastZone();return;
  }
  if(zone.stage==='waiting'&&now>=zone.stageEnds){
   const radii=[72,42,22,10,5],target=radii[Math.min(zone.phase,radii.length-1)];
   const theta=Math.random()*Math.PI*2;
   const distance=Math.sqrt(Math.random())*Math.max(0,zone.radius-target)*.85;
   zone.fromX=zone.centerX;zone.fromZ=zone.centerZ;zone.fromRadius=zone.radius;
   zone.toX=zone.centerX+Math.cos(theta)*distance;
   zone.toZ=zone.centerZ+Math.sin(theta)*distance;
   zone.toRadius=target;
   zone.stage='shrinking';zone.stageStarted=now;zone.stageEnds=now+45000;
  }
  if(zone.stage==='shrinking'){
   const t=Math.max(0,Math.min(1,(now-zone.stageStarted)/(zone.stageEnds-zone.stageStarted)));
   zone.centerX=zone.fromX+(zone.toX-zone.fromX)*t;
   zone.centerZ=zone.fromZ+(zone.toZ-zone.fromZ)*t;
   zone.radius=zone.fromRadius+(zone.toRadius-zone.fromRadius)*t;
   if(t>=1){zone.phase++;zone.stage='waiting';zone.stageStarted=now;zone.stageEnds=now+(zone.phase>=5?15000:20000);}
  }
  if(now-zone.lastDamageAt>=1000){
   const seconds=Math.min(3,Math.floor((now-zone.lastDamageAt)/1000));
   zone.lastDamageAt+=seconds*1000;
   const damage=Math.min(24,6+zone.phase*3)*seconds;
   for(const id of this.battle.roster){
    const p=this.players.get(id);if(!p||p.dead||p.y>12)continue;
    if(Math.hypot(p.x-zone.centerX,p.z-zone.centerZ)<=zone.radius)continue;
    p.health=Math.max(0,p.health-damage);
    const killed=p.health===0;
    if(killed){p.dead=true;p.deadUntil=0;p.moving=false;}
    this.broadcast3D({type:'hit3d',attackerId:'safezone',targetId:id,health:p.health,damage,killed,respawnIn:0,shotId:'zone-'+now+'-'+id});
    if(killed){this.broadcast3D(p);this.checkBattleEnd();}
    if(this.sessions.has(id))this.save3D(id);
    if(this.battle.phase!=='running')break;
   }
  }
  this.broadcastZone();
 }
 broadcastZone(){
  const z=this.battle.zone;if(!z||this.battle.phase!=='running'||z.stage==='hidden')return;
  this.broadcast3D({type:'safezone3d',x:z.centerX,z:z.centerZ,radius:z.radius,
   phase:z.phase+1,stage:z.stage,seconds:Math.max(0,Math.ceil((z.stageEnds-Date.now())/1000)),
   damagePerSecond:Math.min(24,6+z.phase*3)});
 }
 tickBattleBots(now){
  if(!this.battle.enabled||this.battle.phase!=='running')return;
  for(const id of this.battle.roster){
   const bot=this.players.get(id);if(!bot?.bot||bot.dead)continue;
   // Server-controlled flight, staggered jumps, parachutes and individual landing points.
   if(bot.dropPhase&&bot.dropPhase!=='landed'){
    if(bot.dropPhase==='plane'){
     bot.x=Math.min(90,-90+17*(now-(this.battle.startedAt||now))/1000);
     bot.y=110;bot.z=0;bot.grounded=false;bot.moving=false;
     if(now>=bot.dropAt){bot.dropPhase='freefall';bot.jumpAt=now;bot.jumpX=bot.x;}
    }else{
     const seconds=(now-bot.jumpAt)/1000;
     if(seconds>=3.5&&bot.dropPhase==='freefall')bot.dropPhase='glide';
     const fraction=Math.min(1,seconds/11);
     bot.y=Math.max(0,bot.dropPhase==='freefall'?110-23*seconds:29-(seconds-3.5)*3.9);
     bot.x=bot.jumpX+(bot.landingX-bot.jumpX)*fraction;
     bot.z=bot.landingZ*fraction;
     bot.angle=Math.atan2(bot.landingX-bot.x,bot.landingZ-bot.z);
     bot.grounded=false;bot.moving=true;
     if(bot.y<=0){bot.y=globalThis.TacticalRules.terrain(bot.landingX,bot.landingZ);bot.x=bot.landingX;bot.z=bot.landingZ;bot.dropPhase='landed';bot.grounded=true;bot.moving=false;}
    }
    this.broadcast3D(bot);continue;
   }
   const candidates=this.battle.roster.map(pid=>this.players.get(pid)).filter(p=>p&&!p.dead&&p.id!==id&&p.y<12);
   if(!candidates.length)continue;
   candidates.sort((a,b)=>Math.hypot(a.x-bot.x,a.z-bot.z)-Math.hypot(b.x-bot.x,b.z-bot.z));
   const target=candidates[0],dx=target.x-bot.x,dz=target.z-bot.z,dist=Math.hypot(dx,dz);
   const zone=this.battle.zone;
   const outside=zone&&zone.stage!=='hidden'&&Math.hypot(bot.x-zone.centerX,bot.z-zone.centerZ)>Math.max(3,zone.radius-4);
   const mx=outside?zone.centerX-bot.x:dx,mz=outside?zone.centerZ-bot.z:dz,md=Math.hypot(mx,mz)||1;
   bot.angle=Math.atan2(mx,mz);bot.moving=outside||dist>7;
   if(outside||(dist>7&&dist<90)){
    const step=Math.min(outside?4:2.5,outside?md:Math.max(0,dist-7));
    bot.x+=mx/md*step;bot.z+=mz/md*step;
   }
   this.broadcast3D(bot);
   if(dist<27&&now-(bot.lastBotAttack||0)>1800){
    bot.lastBotAttack=now;
    // Replicate shot FX and sound to every human client, regardless of hit chance.
    const ox=bot.x,oy=bot.y+1.3,oz=bot.z;
    const vx=target.x-ox,vy=target.y+1.3-oy,vz=target.z-oz;
    const len=Math.hypot(vx,vy,vz)||1;
    this.broadcast3D({type:'shot3d',ownerId:id,weapon:'rifle',origin:{x:ox,y:oy,z:oz},rays:[{x:vx/len,y:vy/len,z:vz/len}],attachments:{},at:now});
    if(Math.random()<.45){
     target.health=Math.max(0,target.health-11);const killed=target.health===0;
     if(killed){target.dead=true;target.deadUntil=0;bot.kills++;target.moving=false;}
     this.broadcast3D({type:'hit3d',attackerId:id,targetId:target.id,damage:11,health:target.health,killed,respawnIn:0,shotId:'bot-'+now+'-'+id});
     if(killed){this.broadcast3D(target);this.checkBattleEnd();}
     if(this.sessions.has(target.id))this.save3D(target.id);
    }
   }
  }
  this.battle.bots=this.battle.roster.map(id=>this.players.get(id)).filter(p=>p?.bot).map(p=>({...p}));
  this.syncBattleAttachments();
 }
 syncBattleAttachments(){
  for(const peer of this.sessions.values()){
   const attachment=peer.deserializeAttachment();
   if(attachment?.mode==='3d'){
    const bots=(this.battle.bots||[]).map(b=>({id:b.id,name:b.name,x:b.x,y:b.y,z:b.z,angle:b.angle,health:b.health,dead:b.dead,kills:b.kills,lastBotAttack:b.lastBotAttack,bot:true,weapon:'rifle'}));
    peer.serializeAttachment({...attachment,battle:{enabled:this.battle.enabled,phase:this.battle.phase,roster:[...this.battle.roster],winnerId:this.battle.winnerId,deadline:this.battle.deadline,startedAt:this.battle.startedAt,zone:this.battle.zone,bots}});
   }
  }
 }
 broadcastBattleStatus(){
  if(!this.battle.enabled)return;
  const alive=this.battle.roster.filter(id=>this.players.has(id)&&!this.players.get(id)?.dead);
  this.broadcast3D({type:'battle-status',phase:this.battle.phase,connected:this.sessions.size,capacity:8,alive:alive.length,winnerId:this.battle.winnerId,remainingSeconds:this.battle.phase==='waiting'?Math.max(0,Math.ceil((this.battle.deadline-Date.now())/1000)):0});
 }
 checkBattleEnd(){
  if(!this.battle.enabled||this.battle.phase!=='running')return;
  const alive=this.battle.roster.filter(id=>this.players.has(id)&&!this.players.get(id)?.dead);
  if(alive.length<=1){
   this.battle.phase='finished';this.battle.winnerId=alive[0]||null;
   this.syncBattleAttachments();
   this.broadcast3D({type:'battle-end',winnerId:this.battle.winnerId,winnerName:this.players.get(this.battle.winnerId)?.name||'Sem vencedor',alive:alive.length});
  }else this.broadcastBattleStatus();
 }
 handle3D(ws,meta,data){
  const finite=(v,min,max)=>typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max;
  const weapons={pistol:{damage:30,range:65,delay:60/340*1000,pellets:1},smg:{damage:18,range:45,delay:95,pellets:1},rifle:{damage:28,range:85,delay:140,pellets:1},shotgun:{damage:11,range:28,delay:850,pellets:6},sniper:{damage:95,range:220,delay:1050,pellets:1}};
  const now=Date.now();for(const [id,shot]of this.shots3D)if(now-shot.at>2000)this.shots3D.delete(id);
  if(this.battle.enabled&&this.battle.phase!=='running'&&data.type!=='state3d')return;
  if(data.type==='state3d'){
   if(!finite(data.x,-160,160)||!finite(data.y,-25,150)||!finite(data.z,-160,160)||!finite(data.angle,-1000,1000))return;
   const prev=this.players.get(meta.id);
   if(this.battle.enabled&&this.battle.phase!=='running')return;
   if(prev?.dead){this.broadcast3D(prev);return;}
   const state={type:'state3d',id:meta.id,name:String(data.name||'Jogador').slice(0,18),x:data.x,y:data.y,z:data.z,angle:data.angle,
    moving:!!data.moving,running:!!data.running,climbing:!!data.climbing,aiming:!!data.aiming,firing:!!data.firing,reload:finite(data.reload,0,1)?data.reload:0,inCar:!!data.inCar,
    grounded:data.grounded!==false,crouching:!!data.crouching,crouchBlend:finite(data.crouchBlend,0,1)?data.crouchBlend:(data.crouching?1:0),
    prone:data.grounded!==false&&finite(data.prone,0,1)?data.prone:0,proneSlope:finite(data.proneSlope,-.25,.25)?data.proneSlope:0,proneRoll:finite(data.proneRoll,-.16,.16)?data.proneRoll:0,
    speed:finite(data.speed,0,20)?data.speed:0,jetpack:data.jetpack===true,jetpackActive:data.jetpack===true&&data.jetpackActive===true,verticalVelocity:finite(data.verticalVelocity,-100,100)?data.verticalVelocity:0,weapon:data.weapon==='none'?'none':weapons[data.weapon]?data.weapon:'pistol',pitch:finite(data.pitch,-1.5,1.5)?data.pitch:0,
    attachments:(()=>{const src=data.attachments&&typeof data.attachments==='object'?data.attachments:{};const out={};for(const key of ['optic','suppressor','extended','grip','stock'])if(src[key]===true)out[key]=true;return out;})(),
    soldierSkin:['original','arctic','desert','shadow'].includes(data.soldierSkin)?data.soldierSkin:'original',weaponSkin:['original','sand','blue','ember'].includes(data.weaponSkin)?data.weaponSkin:'original',dead:false,deadUntil:0,health:prev?.health??100,kills:prev?.kills??0,lastShot:prev?.lastShot??0,grenades:prev?.grenades??3,iceCharges:prev?.iceCharges??3,lastGearAt:prev?.lastGearAt??0,gear:data.gear==='grenade'?'grenade':'none'};
   this.players.set(meta.id,state);this.save3D(meta.id);this.broadcast3D(state);if(!prev)this.broadcastRanking();return;
  }
  const shooter=this.players.get(meta.id);if(!shooter||shooter.dead)return;
  if(data.type==='gear3d'){this.tactical.use(ws,shooter,data);return;}
  if(data.type==='shot3d'){
   const spec=weapons[data.weapon];if(!spec||now-shooter.lastShot<spec.delay*.72)return;
   if(!/^[a-z0-9-]{1,32}$/.test(String(data.shotId||'')))return;
   const origin=data.origin;if(!origin||![origin.x,origin.y,origin.z].every(Number.isFinite))return;
   if(Math.hypot(origin.x-shooter.x,origin.y-shooter.y-1.3,origin.z-shooter.z)>3||this.tactical.originBlocked(shooter,origin))return;
   if(!Array.isArray(data.rays)||data.rays.length!==spec.pellets)return;
   const rays=[];for(const ray of data.rays){
    if(!ray||![ray.x,ray.y,ray.z].every(Number.isFinite))return;
    const length=Math.hypot(ray.x,ray.y,ray.z);if(length<.5||length>1.5)return;
    rays.push({x:ray.x/length,y:ray.y/length,z:ray.z/length});
   }
   const key=meta.id+':'+data.shotId;if(this.shots3D.has(key))return;
   shooter.lastShot=now;
   const shot={type:'shot3d',ownerId:meta.id,shotId:String(data.shotId),weapon:data.weapon,attachments:{...(shooter.attachments||{})},origin,rays,at:now,used:{}};
   shot.stops=this.tactical.shoot(shot,spec);
   this.shots3D.set(key,shot);this.save3D(meta.id);this.broadcast3D(shot);return;
  }
  if(data.type==='hit3d'){
   const shot=this.shots3D.get(meta.id+':'+String(data.shotId));
   const pellet=data.pellet,target=this.players.get(String(data.targetId));
   if(!shot||!Number.isInteger(pellet)||!shot.rays[pellet]||shot.used[pellet]||!target||target.dead||target.id===meta.id)return;
   const ray=shot.rays[pellet],spec=weapons[shot.weapon];
   const distance=globalThis.TacticalRules.bodyHitDistance(shot.origin,ray,target,spec.range);
   if(distance===null)return;
   if(shot.stops?.[pellet]!=null&&distance>shot.stops[pellet]+.05)return;
   shot.used[pellet]=true;const point={x:shot.origin.x+ray.x*distance,y:shot.origin.y+ray.y*distance,z:shot.origin.z+ray.z*distance}; const zone=globalThis.TacticalRules.damageZoneAt(point,target);const damage=Math.round(globalThis.TacticalRules.damageForZone(spec.damage,zone));target.health=Math.max(0,target.health-damage); const killed=target.health===0;
   if(killed){shooter.kills++;target.dead=true;target.deadUntil=this.battle.enabled?0:now+5000;target.moving=false;target.running=false;target.aiming=false;target.jetpack=false;target.jetpackActive=false;}
   this.broadcast3D({type:'hit3d',shotId:shot.shotId,attackerId:meta.id,targetId:target.id,health:target.health,damage,zone,killed,respawnIn:killed?(this.battle.enabled?0:5):0,kills:shooter.kills});
   if(killed){
    this.broadcast3D(target);if(this.battle.enabled)this.checkBattleEnd();else this.scheduleRespawns();this.broadcastRanking();
   }
   this.save3D(meta.id);this.save3D(target.id);
  }
 }

 scheduleRespawns(){
  const deadlines=[...this.players.values()].filter(p=>p.dead&&p.deadUntil>0).map(p=>p.deadUntil);
  const tacticalDeadline=this.tactical.nextAlarm(Date.now());if(tacticalDeadline!==null)deadlines.push(tacticalDeadline);
  if(this.battle.enabled&&this.battle.phase==='waiting'&&this.sessions.size)deadlines.push(Math.min(this.battle.deadline,Date.now()+1000));
  if(this.battle.enabled&&this.battle.phase==='running'&&this.sessions.size)deadlines.push(Date.now()+500);
  if(deadlines.length)this.ctx.waitUntil(this.ctx.storage.setAlarm(Math.max(Date.now()+20,Math.min(...deadlines))));
 }
 async alarm(){
  const now=Date.now();await this.tactical.tick(now);
  if(this.battle.enabled&&this.battle.phase==='waiting'&&this.sessions.size){
   if(now>=this.battle.deadline)this.startBattle();else this.broadcastBattleStatus();
  }
  if(this.battle.enabled&&this.battle.phase==='running'){this.tickBattleBots(now);this.advanceSafeZone(now);}
  for(const target of this.players.values())if(!this.battle.enabled&&target.dead&&target.deadUntil<=now){
   Object.assign(target,{dead:false,deadUntil:0,health:100,x:4,y:0,z:8,moving:false,running:false,aiming:false,grounded:true,crouching:false,crouchBlend:0,prone:0,proneSlope:0,proneRoll:0,speed:0,jetpack:false,jetpackActive:false,verticalVelocity:0,lastShot:0,grenades:3,iceCharges:3,lastGearAt:0,gear:'none'});
   this.tactical.inventory(target);this.save3D(target.id);this.broadcast3D({type:'respawn3d',id:target.id,x:4,y:0,z:8,health:100,dead:false});this.broadcast3D(target);
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
  this.sessions.delete(meta.id);this.players.delete(meta.id);
  if(this.battle.enabled&&this.battle.phase==='waiting')this.battle.roster=this.battle.roster.filter(id=>id!==meta.id);for(const [key,shot]of this.shots3D)if(shot.ownerId===meta.id)this.shots3D.delete(key);this.broadcastRanking();
  if(this.battle.enabled){this.checkBattleEnd();if(this.sessions.size===0){this.battle={enabled:false,phase:'waiting',roster:[],winnerId:null,deadline:0,bots:[]};for(const [id,p]of this.players)if(p.bot)this.players.delete(id);}this.syncBattleAttachments();this.broadcastBattleStatus();}
  const out = JSON.stringify({type:"leave", id:meta.id});
  for (const peer of this.sessions.values()) { try { peer.send(out); } catch {} }
 }
}
