const canvas=document.getElementById("gameCanvas"),ctx=canvas.getContext("2d"),W=2800,H=1900;
const touchMove={x:0,y:0},touchAim={x:0,y:0};
// 2.5D visual projection: world physics remains in the original XY plane.
const VIEW_TILT=.78;
function screenToWorldY(y){return cam.y+(y-canvas.height*(1-VIEW_TILT)/2)/VIEW_TILT;}
function worldToScreenY(y){return (y-cam.y)*VIEW_TILT+canvas.height*(1-VIEW_TILT)/2;}
const keys={},cam={x:0,y:0},mouse={x:0,y:0,down:false};
const player={x:480,y:440,r:16,speed:190,inCar:false,angle:0,walk:0,ammo:12,reserve:72,maxAmmo:12,reloading:false,reloadT:0,shootCd:0,health:100,weapon:"pistol",carHitCd:0,hidden:false};
const weapons={
 pistol:{name:"PISTOLA",mag:12,reserve:72,fire:.16,speed:980,spread:.025,pellets:1,damage:1,color:"#ffe36e"},
 smg:{name:"SMG",mag:30,reserve:120,fire:.075,speed:930,spread:.07,pellets:1,damage:1,color:"#7ee8ff"},
 shotgun:{name:"ESCOPETA",mag:6,reserve:36,fire:.62,speed:820,spread:.34,pellets:7,damage:1,color:"#ffbd69"},
 rifle:{name:"RIFLE",mag:20,reserve:80,fire:.12,speed:1250,spread:.012,pellets:1,damage:2,color:"#b9ff7a"}
};
const car={x:590,y:440,angle:0,speed:0,acc:430,max:470,turn:2.5,health:100,nitro:100};
let started=false,paused=false,missionDone=false,flash=0,skids=[],sparks=[],bullets=[],shells=[],hitMarks=[],weaponPickups=[],pickupRespawns=[];
let socket=null,myId=null,netTimer=0,playerName="Jogador",roomCode="cidade-1",gameMode="solo",kills=0;
const remotePlayers=new Map();
const ranking=new Map();
const enemies=[];
const mission={x:2440,y:1560,r:48};
const buildings=[
{x:80,y:70,w:360,h:240},{x:700,y:70,w:300,h:250},{x:1280,y:60,w:300,h:270},{x:1840,y:80,w:270,h:235},{x:2380,y:70,w:320,h:250},
{x:80,y:570,w:350,h:250},{x:710,y:570,w:300,h:240},{x:1270,y:570,w:300,h:250},{x:1840,y:570,w:270,h:245},{x:2380,y:570,w:320,h:250},
{x:80,y:1070,w:350,h:230},{x:710,y:1070,w:300,h:230},{x:1270,y:1070,w:300,h:230},{x:1840,y:1070,w:270,h:230},{x:2380,y:1070,w:320,h:230},
{x:80,y:1580,w:350,h:230},{x:710,y:1580,w:300,h:230},{x:1270,y:1580,w:300,h:230},{x:1840,y:1580,w:270,h:230},{x:2380,y:1580,w:320,h:230}];
const traffic=[
{x:100,y:440,a:0,s:95,c:"#f06b6b"},{x:2500,y:950,a:Math.PI,s:115,c:"#69a7ff"},{x:1145,y:140,a:Math.PI/2,s:82,c:"#ffd35f"},{x:1705,y:1650,a:-Math.PI/2,s:90,c:"#d77cff"}];
const targets=[
{x:860,y:440,r:20,hp:3},{x:1420,y:950,r:20,hp:3},{x:2020,y:1450,r:20,hp:3},{x:2420,y:950,r:20,hp:3},{x:580,y:1450,r:20,hp:3}
];
const trees=[];for(let x=470;x<W;x+=250)for(let y=330;y<H;y+=330)trees.push({x:x+Math.random()*50,y:y+Math.random()*55});
const bushes=[];
for(let i=0;i<34;i++){
 let x,y,tries=0;
 do{x=110+Math.random()*(W-220);y=110+Math.random()*(H-220);tries++}while(collides(x,y,34)&&tries<80);
 bushes.push({x,y,r:34+Math.random()*12});
}
function randomOpenPoint(){let x=500,y=440,tries=0;do{x=90+Math.random()*(W-180);y=90+Math.random()*(H-180);tries++}while((collides(x,y,30)||Math.hypot(x-player.x,y-player.y)<180)&&tries<100);return{x,y}}
function spawnWeaponPickups(count=10){weaponPickups.length=0;const types=["smg","shotgun","rifle","pistol"];for(let i=0;i<count;i++){const p=randomOpenPoint();weaponPickups.push({x:p.x,y:p.y,type:types[Math.floor(Math.random()*types.length)],spin:Math.random()*6.28})}}
function equipWeapon(type){const w=weapons[type];if(!w)return;player.weapon=type;player.maxAmmo=w.mag;player.ammo=w.mag;player.reserve=w.reserve;player.reloading=false;flash=.18}
function updatePickups(dt){
 for(const p of weaponPickups){p.spin+=dt*2.2;if(!player.inCar&&Math.hypot(player.x-p.x,player.y-p.y)<34){equipWeapon(p.type);pickupRespawns.push({t:18,type:p.type});p.dead=true}}
 weaponPickups=weaponPickups.filter(p=>!p.dead);
 for(const r of pickupRespawns)r.t-=dt;
 const ready=pickupRespawns.filter(r=>r.t<=0);pickupRespawns=pickupRespawns.filter(r=>r.t>0);
 for(const r of ready){const p=randomOpenPoint();weaponPickups.push({x:p.x,y:p.y,type:r.type,spin:Math.random()*6.28})}
}
function updateBushState(){player.hidden=!player.inCar&&bushes.some(b=>Math.hypot(player.x-b.x,player.y-b.y)<b.r*.72)}

addEventListener("keydown",e=>{
 const k=e.key.toLowerCase();keys[k]=true;
 if(k==="e")toggleCar();if(k==="p")togglePause();if(k==="r")startReload();
 if([" ","arrowup","arrowdown","arrowleft","arrowright"].includes(k))e.preventDefault()
},{passive:false});
addEventListener("keyup",e=>keys[e.key.toLowerCase()]=false);
canvas.addEventListener("mousemove",e=>{const r=canvas.getBoundingClientRect();mouse.x=cam.x+(e.clientX-r.left)*canvas.width/r.width;mouse.y=screenToWorldY((e.clientY-r.top)*canvas.height/r.height)});
canvas.addEventListener("mousedown",e=>{if(e.button===0){mouse.down=true;shoot()}});
addEventListener("mouseup",e=>{if(e.button===0)mouse.down=false});
canvas.addEventListener("contextmenu",e=>e.preventDefault());
document.getElementById("soloModeBtn").onclick=()=>setGameMode("solo");
document.getElementById("multiModeBtn").onclick=()=>setGameMode("multi");
function setGameMode(mode){
 gameMode=mode;
 document.getElementById("soloModeBtn").classList.toggle("active",mode==="solo");
 document.getElementById("multiModeBtn").classList.toggle("active",mode==="multi");
 document.getElementById("roomCode").style.display=mode==="multi"?"block":"none";
 document.getElementById("startBtn").textContent=mode==="multi"?"Entrar na sala":"Jogar solo";
}
setGameMode("solo");
document.getElementById("startBtn").onclick=()=>{
 playerName=(document.getElementById("playerName")?.value||"Jogador").trim().slice(0,18)||"Jogador";
 roomCode=(document.getElementById("roomCode")?.value||"cidade-1").trim().toLowerCase().replace(/[^a-z0-9-]/g,"").slice(0,24)||"cidade-1";
 started=true;document.getElementById("startOverlay").classList.add("hidden");canvas.focus();spawnWeaponPickups();
 if(gameMode==="multi")connectMultiplayer(); else spawnEnemies();
};
document.getElementById("pauseBtn").onclick=togglePause;
document.getElementById("restartBtn").onclick=()=>location.reload();
document.getElementById("fullscreenBtn").onclick=()=>{const el=document.getElementById("gameWrap");document.fullscreenElement?document.exitFullscreen():el.requestFullscreen?.()};

function connectMultiplayer(){
 try{
  if(socket)socket.close();
  const proto=location.protocol==="https:"?"wss:":"ws:";
  socket=new WebSocket(proto+"//"+location.host+"/ws?room="+encodeURIComponent(roomCode));
  socket.onopen=()=>sendNetState(true);
  socket.onmessage=e=>{
   try{
    const m=JSON.parse(e.data);
    if(m.type==="welcome"){myId=m.id;return}
    if(m.type==="state"&&m.id!==myId){remotePlayers.set(m.id,{...m,seen:performance.now()});ranking.set(m.id,{name:m.name||"Jogador",kills:m.kills||0})}
    if(m.type==="ranking"){ranking.clear();for(const p of m.players||[])ranking.set(p.id,{name:p.name,kills:p.kills||0})}
    if(m.type==="leave"){remotePlayers.delete(m.id);ranking.delete(m.id)}
   }catch(_){}
  };
  socket.onclose=()=>{remotePlayers.clear();setTimeout(()=>{if(started)connectMultiplayer()},1800)};
 }catch(_){}
}
function sendNetState(force=false){
 if(gameMode!=="multi"||!socket||socket.readyState!==WebSocket.OPEN)return;
 const msg={type:"state",name:playerName,x:player.x,y:player.y,angle:player.angle,inCar:player.inCar,shooting:player.shootCd>.1,kills};
 socket.send(JSON.stringify(msg));
}
function togglePause(){if(!started)return;paused=!paused;document.getElementById("pauseBtn").textContent=paused?"Continuar":"Pausar"}
function toggleCar(){
 if(!started||paused)return;
 if(player.inCar){player.inCar=false;player.x=car.x+Math.cos(car.angle+Math.PI/2)*58;player.y=car.y+Math.sin(car.angle+Math.PI/2)*58}
 else if(Math.hypot(player.x-car.x,player.y-car.y)<82){player.inCar=true;player.x=car.x;player.y=car.y}
}
function collides(x,y,r=20){if(x-r<0||y-r<0||x+r>W||y+r>H)return true;return buildings.some(b=>x+r>b.x&&x-r<b.x+b.w&&y+r>b.y&&y-r<b.y+b.h)}
function startReload(){if(player.inCar||player.reloading||player.ammo===player.maxAmmo||player.reserve<=0)return;player.reloading=true;player.reloadT=player.weapon==="shotgun"?1.35:1.05}
function shoot(){
 if(!started||paused||player.inCar||player.reloading||player.shootCd>0)return;
 if(player.ammo<=0){startReload();return}
 const w=weapons[player.weapon];player.ammo--;player.shootCd=w.fire;
 for(let i=0;i<w.pellets;i++){
  const a=player.angle+(Math.random()-.5)*w.spread,ox=player.x+Math.cos(a)*28,oy=player.y+Math.sin(a)*28;
  bullets.push({x:ox,y:oy,vx:Math.cos(a)*w.speed,vy:Math.sin(a)*w.speed,t:player.weapon==="rifle"?1.15:.9,damage:w.damage,color:w.color});
 }
 shells.push({x:player.x,y:player.y,vx:Math.cos(player.angle+Math.PI/2)*(50+Math.random()*35),vy:Math.sin(player.angle+Math.PI/2)*(50+Math.random()*35),t:.5});
 if(player.ammo===0&&player.reserve>0)setTimeout(()=>{if(started&&!paused)startReload()},180);
}
function spawnEnemies(){
 enemies.length=0;
 const pts=[[900,440],[1400,950],[2050,1450],[2400,950],[600,1450],[1700,440],[1150,1450]];
 for(let i=0;i<pts.length;i++)enemies.push({x:pts[i][0],y:pts[i][1],r:16,hp:3,angle:0,speed:70,shootCd:Math.random()*1.5,alive:true});
}
function updateEnemies(dt){
 if(gameMode!=="solo")return;
 for(const e of enemies){
  if(!e.alive)continue;
  const dx=player.x-e.x,dy=player.y-e.y,d=Math.hypot(dx,dy)||1;e.angle=Math.atan2(dy,dx);
  const canSee=!player.hidden||d<125;
  if(canSee&&d>150){
   const nx=e.x+dx/d*e.speed*dt,ny=e.y+dy/d*e.speed*dt;
   if(!collides(nx,e.y,e.r))e.x=nx;if(!collides(e.x,ny,e.r))e.y=ny;
  }
  e.shootCd-=dt;
  if(canSee&&d<420&&e.shootCd<=0){e.shootCd=1.1+Math.random()*.8;if(!player.inCar){player.health=Math.max(0,player.health-8);flash=.35}}
 }
}
function drawEnemies(){
 if(gameMode!=="solo")return;
 for(const e of enemies){
  if(!e.alive)continue;
  ctx.save();ctx.translate(e.x,e.y);ctx.fillStyle="#0006";ctx.beginPath();ctx.ellipse(0,10,17,8,0,0,Math.PI*2);ctx.fill();ctx.rotate(e.angle);
  ctx.fillStyle="#7d2d2d";ctx.beginPath();ctx.ellipse(0,0,16,13,0,0,Math.PI*2);ctx.fill();
  ctx.fillStyle="#d7b08c";ctx.beginPath();ctx.arc(2,-5,9,0,Math.PI*2);ctx.fill();ctx.fillStyle="#20252c";ctx.fillRect(14,-4,20,8);ctx.restore();
  ctx.fillStyle="#111";ctx.fillRect(e.x-18,e.y-27,36,5);ctx.fillStyle="#ff5f5f";ctx.fillRect(e.x-18,e.y-27,36*(e.hp/3),5);
 }
}
function reportKill(){
 kills++;
 if(gameMode==="multi"&&socket?.readyState===WebSocket.OPEN)socket.send(JSON.stringify({type:"kill",name:playerName}));
}
function updateTraffic(dt){for(const t of traffic){
 t.x+=Math.cos(t.a)*t.s*dt;t.y+=Math.sin(t.a)*t.s*dt;
 if(!player.inCar&&player.carHitCd<=0&&Math.hypot(player.x-t.x,player.y-t.y)<42){
  const push=62+Math.min(90,t.s*.55),px=Math.cos(t.a)*push,py=Math.sin(t.a)*push;
  const nx=player.x+px,ny=player.y+py;if(!collides(nx,player.y,player.r))player.x=nx;if(!collides(player.x,ny,player.r))player.y=ny;
  player.health=Math.max(0,player.health-18);player.carHitCd=.85;flash=.8;
  for(let i=0;i<8;i++)sparks.push({x:player.x,y:player.y,vx:(Math.random()-.5)*150,vy:(Math.random()-.5)*150,t:.35});
 }
 if(t.a===0&&t.x>W+60)t.x=-60;if(t.a===Math.PI&&t.x<-60)t.x=W+60;if(t.a===Math.PI/2&&t.y>H+60)t.y=-60;if(t.a===-Math.PI/2&&t.y<-60)t.y=H+60
}}
function updateBullets(dt){
 for(const b of bullets){
  b.x+=b.vx*dt;b.y+=b.vy*dt;b.t-=dt;
  if(collides(b.x,b.y,3)){b.t=0;sparks.push({x:b.x,y:b.y,vx:(Math.random()-.5)*80,vy:(Math.random()-.5)*80,t:.25});continue}
  if(gameMode==="solo"){for(const e of enemies){if(e.alive&&Math.hypot(b.x-e.x,b.y-e.y)<e.r+4){e.hp-=b.damage||1;b.t=0;if(e.hp<=0){e.alive=false;reportKill()}hitMarks.push({x:e.x,y:e.y,t:.25});break}}}
  for(const t of targets){if(t.hp>0&&Math.hypot(b.x-t.x,b.y-t.y)<t.r+4){t.hp--;b.t=0;hitMarks.push({x:t.x,y:t.y,t:.25});for(let i=0;i<5;i++)sparks.push({x:b.x,y:b.y,vx:(Math.random()-.5)*120,vy:(Math.random()-.5)*120,t:.35});break}}
 }
 bullets=bullets.filter(b=>b.t>0);
 shells.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.vx*=.94;s.vy*=.94;s.t-=dt});shells=shells.filter(s=>s.t>0);
 hitMarks.forEach(h=>h.t-=dt);hitMarks=hitMarks.filter(h=>h.t>0);
}
function update(dt){
 if(!started||paused)return;
 player.carHitCd=Math.max(0,player.carHitCd-dt);updateTraffic(dt);updateBushState();updatePickups(dt);flash=Math.max(0,flash-dt*2);player.shootCd=Math.max(0,player.shootCd-dt);
 if(player.reloading){player.reloadT-=dt;if(player.reloadT<=0){const need=player.maxAmmo-player.ammo,take=Math.min(need,player.reserve);player.ammo+=take;player.reserve-=take;player.reloading=false}}
 if(player.inCar){
  const throttle=(keys.w||keys.arrowup?1:0)-(keys.s||keys.arrowdown?1:0)-touchMove.y;let boost=1;
  if(keys.shift&&car.nitro>0&&throttle>0){boost=1.42;car.nitro=Math.max(0,car.nitro-31*dt)}else car.nitro=Math.min(100,car.nitro+10*dt);
  car.speed+=throttle*car.acc*boost*dt;if(!throttle)car.speed*=Math.pow(.25,dt);car.speed=Math.max(-230,Math.min(car.max*boost,car.speed));
  const steer=(keys.d||keys.arrowright?1:0)-(keys.a||keys.arrowleft?1:0)+touchMove.x;if(Math.abs(car.speed)>8)car.angle+=steer*car.turn*dt*(car.speed/car.max)*(keys[" "]?1.55:1);
  if(keys[" "])car.speed*=Math.pow(.34,dt);
  const ox=car.x,oy=car.y;car.x+=Math.cos(car.angle)*car.speed*dt;car.y+=Math.sin(car.angle)*car.speed*dt;
  if(collides(car.x,car.y,27)){car.x=ox;car.y=oy;car.speed*=-.24;car.health=Math.max(0,car.health-7);flash=.5;for(let i=0;i<10;i++)sparks.push({x:car.x,y:car.y,vx:(Math.random()-.5)*190,vy:(Math.random()-.5)*190,t:.45})}
  if((keys[" "]||Math.abs(steer)>.25)&&Math.abs(car.speed)>125)skids.push({x:car.x-Math.cos(car.angle)*25,y:car.y-Math.sin(car.angle)*25,a:car.angle,t:1});
  player.x=car.x;player.y=car.y;
 }else{
  const dx=(keys.d||keys.arrowright?1:0)-(keys.a||keys.arrowleft?1:0)+touchMove.x,dy=(keys.s||keys.arrowdown?1:0)-(keys.w||keys.arrowup?1:0)+touchMove.y;
  const moving=dx!==0||dy!==0,m=Math.hypot(dx,dy)||1,run=keys.shift?1.55:1;
  const nx=player.x+dx/m*player.speed*run*dt,ny=player.y+dy/m*player.speed*run*dt;
  if(!collides(nx,player.y,player.r))player.x=nx;if(!collides(player.x,ny,player.r))player.y=ny;
  if(moving)player.walk+=dt*(run>1?13:9);
  if(Math.hypot(touchAim.x,touchAim.y)>.12){player.angle=Math.atan2(touchAim.y,touchAim.x);mouse.x=player.x+touchAim.x*200;mouse.y=player.y+touchAim.y*200;}
  else if(!matchMedia("(pointer:coarse)").matches)player.angle=Math.atan2(mouse.y-player.y,mouse.x-player.x);
  if(mouse.down||Math.hypot(touchAim.x,touchAim.y)>.32)shoot();
 }
 updateBushState();updateBullets(dt);updateEnemies(dt);
 if(!missionDone&&Math.hypot(player.x-mission.x,player.y-mission.y)<70){missionDone=true;flash=1}
 skids.forEach(s=>s.t-=dt*.34);skids=skids.filter(s=>s.t>0);sparks.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.t-=dt});sparks=sparks.filter(s=>s.t>0);
 const tx=player.x-canvas.width/2,ty=player.y-canvas.height/(2*VIEW_TILT);cam.x+=(Math.max(0,Math.min(W-canvas.width,tx))-cam.x)*Math.min(1,dt*5.5);cam.y+=(Math.max(0,Math.min(H-canvas.height/VIEW_TILT,ty))-cam.y)*Math.min(1,dt*5.5);netTimer+=dt;if(netTimer>=.067){netTimer=0;sendNetState()}
}
function road(){ctx.fillStyle="#263129";ctx.fillRect(0,0,W,H);ctx.fillStyle="#4b5255";for(const y of [390,900,1400])ctx.fillRect(0,y,W,100);for(const x of [535,1100,1660,2200])ctx.fillRect(x,0,90,H);ctx.strokeStyle="#d4c765";ctx.lineWidth=3;ctx.setLineDash([28,24]);ctx.beginPath();[440,950,1450].forEach(y=>{ctx.moveTo(0,y);ctx.lineTo(W,y)});[580,1145,1705,2245].forEach(x=>{ctx.moveTo(x,0);ctx.lineTo(x,H)});ctx.stroke();ctx.setLineDash([])}
function drawBuildings(){
 buildings.forEach((b,i)=>{
  const height=58+(i%4)*17, roofY=b.y-height, shift=height*.30;
  // Cast shadow, side facades, then elevated roof.
  ctx.fillStyle="#0007";ctx.fillRect(b.x+15,b.y+13,b.w,b.h);
  ctx.fillStyle="#18252e";ctx.beginPath();ctx.moveTo(b.x+b.w,b.y);ctx.lineTo(b.x+b.w+shift,roofY);ctx.lineTo(b.x+b.w+shift,b.y+b.h-height);ctx.lineTo(b.x+b.w,b.y+b.h);ctx.closePath();ctx.fill();
  ctx.fillStyle=i%2?"#344653":"#293b49";ctx.beginPath();ctx.moveTo(b.x,b.y+b.h);ctx.lineTo(b.x+shift,roofY+b.h);ctx.lineTo(b.x+b.w+shift,roofY+b.h);ctx.lineTo(b.x+b.w,b.y+b.h);ctx.closePath();ctx.fill();
  for(let x=b.x+35;x<b.x+b.w-20;x+=64){ctx.fillStyle="#8ab6c166";ctx.fillRect(x,b.y+b.h-height*.56,28,13);}
  ctx.fillStyle=i%3===0?"#52636d":i%3===1?"#465b66":"#405762";
  ctx.fillRect(b.x+shift,roofY,b.w,b.h);
  ctx.strokeStyle="#9ab2bd";ctx.lineWidth=3;ctx.strokeRect(b.x+shift,roofY,b.w,b.h);
  ctx.strokeStyle="#273a44";ctx.lineWidth=2;ctx.strokeRect(b.x+shift+15,roofY+15,b.w-30,b.h-30);
  ctx.fillStyle="#233741";ctx.fillRect(b.x+shift+32,roofY+28,52,28);
 });
}
function drawTrees(){trees.forEach(t=>{ctx.fillStyle="#342b20";ctx.fillRect(t.x-3,t.y,6,13);ctx.fillStyle="#315e3b";ctx.beginPath();ctx.arc(t.x,t.y-5,12,0,Math.PI*2);ctx.fill()})}
function drawBushes(base=true){for(const b of bushes){ctx.save();ctx.globalAlpha=base?.82:.92;ctx.fillStyle=base?"#244d31":"#367447";for(let i=0;i<6;i++){const a=i*Math.PI/3,r=b.r*.42;ctx.beginPath();ctx.arc(b.x+Math.cos(a)*r,b.y+Math.sin(a)*r,b.r*.48,0,Math.PI*2);ctx.fill()}ctx.fillStyle=base?"#2d613b":"#438955";ctx.beginPath();ctx.arc(b.x,b.y,b.r*.58,0,Math.PI*2);ctx.fill();ctx.restore()}}
function drawWeaponPickups(){for(const p of weaponPickups){const w=weapons[p.type];ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.spin*.18);ctx.fillStyle="#061018cc";ctx.beginPath();ctx.arc(0,0,22,0,Math.PI*2);ctx.fill();ctx.strokeStyle=w.color;ctx.lineWidth=3;ctx.beginPath();ctx.arc(0,0,18,0,Math.PI*2);ctx.stroke();ctx.rotate(-p.spin*.18);ctx.fillStyle=w.color;ctx.fillRect(-13,-4,26,8);ctx.fillRect(4,3,6,9);ctx.restore();ctx.fillStyle="#eaf4fa";ctx.font="800 9px system-ui";ctx.textAlign="center";ctx.fillText(w.name,p.x,p.y-27);ctx.textAlign="left"}}
function drawVehicle(x,y,a,c,w=62,h=32){ctx.save();ctx.translate(x,y);ctx.rotate(a);ctx.fillStyle=c;ctx.fillRect(-w/2,-h/2,w,h);ctx.fillStyle="#17252b";ctx.fillRect(-5,-h/2+4,23,h-8);ctx.fillStyle="#eaf7ff";ctx.fillRect(w/2-6,-10,4,7);ctx.fillRect(w/2-6,3,4,7);ctx.restore()}
function drawPlayer(){
 if(player.inCar)return;
 const moving=keys.w||keys.a||keys.s||keys.d||keys.arrowup||keys.arrowdown||keys.arrowleft||keys.arrowright,bob=moving?Math.sin(player.walk)*2:0,step=moving?Math.sin(player.walk)*5:0;
 ctx.save();ctx.translate(player.x,player.y);
 ctx.fillStyle="#0006";ctx.beginPath();ctx.ellipse(0,11,18,9,0,0,Math.PI*2);ctx.fill();
 ctx.save();ctx.rotate(player.angle);
 ctx.fillStyle="#1c2430";ctx.beginPath();ctx.ellipse(-6,8+step,6,11,0,0,Math.PI*2);ctx.ellipse(7,8-step,6,11,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#e23b43";ctx.beginPath();ctx.ellipse(0,bob,17,14,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#d7b08c";ctx.beginPath();ctx.arc(2,-5+bob,10,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#151a21";ctx.beginPath();ctx.arc(-1,-8+bob,10,Math.PI,Math.PI*2);ctx.fill();
 ctx.fillStyle="#d7b08c";ctx.fillRect(9,-8+bob,16,5);ctx.fillRect(9,4+bob,16,5);
 ctx.fillStyle="#252d33";ctx.fillRect(17,-4+bob,22,8);ctx.fillStyle="#88939c";ctx.fillRect(34,-2+bob,11,4);
 if(player.shootCd>.10){ctx.fillStyle="#ffd45c";ctx.beginPath();ctx.moveTo(46,bob);ctx.lineTo(58,-6+bob);ctx.lineTo(58,6+bob);ctx.closePath();ctx.fill()}
 ctx.restore();ctx.restore()
}
function drawRemotePlayers(){
 const now=performance.now();
 for(const [id,p] of remotePlayers){
  if(now-p.seen>6000){remotePlayers.delete(id);continue}
  if(p.inCar){drawVehicle(p.x,p.y,p.angle||0,"#42b9ff",58,30)}
  else{
   ctx.save();ctx.translate(p.x,p.y);ctx.fillStyle="#0006";ctx.beginPath();ctx.ellipse(0,11,18,9,0,0,Math.PI*2);ctx.fill();ctx.rotate(p.angle||0);
   ctx.fillStyle="#38a6ff";ctx.beginPath();ctx.ellipse(0,0,17,14,0,0,Math.PI*2);ctx.fill();
   ctx.fillStyle="#d7b08c";ctx.beginPath();ctx.arc(2,-5,10,0,Math.PI*2);ctx.fill();
   ctx.fillStyle="#151a21";ctx.beginPath();ctx.arc(-1,-8,10,Math.PI,Math.PI*2);ctx.fill();
   ctx.fillStyle="#d7b08c";ctx.fillRect(9,-8,16,5);ctx.fillRect(9,4,16,5);
   ctx.fillStyle="#252d33";ctx.fillRect(17,-4,22,8);
   if(p.shooting){ctx.fillStyle="#ffd45c";ctx.beginPath();ctx.moveTo(40,0);ctx.lineTo(52,-6);ctx.lineTo(52,6);ctx.closePath();ctx.fill()}
   ctx.restore();
  }
  ctx.save();ctx.font="700 11px system-ui";ctx.textAlign="center";ctx.fillStyle="#dff5ff";ctx.fillText(p.name||"Jogador",p.x,p.y-28);ctx.restore();
 }
}
function drawTargets(){targets.forEach(t=>{if(t.hp<=0)return;ctx.fillStyle="#0007";ctx.beginPath();ctx.ellipse(t.x,t.y+13,23,10,0,0,Math.PI*2);ctx.fill();ctx.fillStyle=t.hp===3?"#ff725f":t.hp===2?"#ffb24b":"#ffe765";ctx.beginPath();ctx.arc(t.x,t.y,t.r,0,Math.PI*2);ctx.fill();ctx.fillStyle="#341b1b";ctx.fillRect(t.x-5,t.y-11,10,22);ctx.fillRect(t.x-11,t.y-5,22,10)})}
function drawMission(){if(missionDone)return;const p=.5+.5*Math.sin(performance.now()/260);ctx.strokeStyle="rgba(101,255,139,"+(.45+p*.45)+")";ctx.lineWidth=4;ctx.beginPath();ctx.arc(mission.x,mission.y,mission.r+p*8,0,Math.PI*2);ctx.stroke();ctx.fillStyle="#65ff8b22";ctx.beginPath();ctx.arc(mission.x,mission.y,mission.r,0,Math.PI*2);ctx.fill()}
function drawCrosshair(){
 if(player.inCar||!started)return;const x=mouse.x-cam.x,y=worldToScreenY(mouse.y);ctx.strokeStyle="#ffffffdd";ctx.lineWidth=2;ctx.beginPath();ctx.arc(x,y,9,0,Math.PI*2);ctx.moveTo(x-15,y);ctx.lineTo(x-5,y);ctx.moveTo(x+5,y);ctx.lineTo(x+15,y);ctx.moveTo(x,y-15);ctx.lineTo(x,y-5);ctx.moveTo(x,y+5);ctx.lineTo(x,y+15);ctx.stroke()
}
function hud(){
 ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle="#061018dc";ctx.fillRect(20,20,250,92);ctx.strokeStyle="#273b49";ctx.strokeRect(20.5,20.5,249,91);ctx.fillStyle="#8ea0ad";ctx.font="700 11px system-ui";ctx.fillText(player.inCar?"VEÍCULO":"STATUS",35,43);ctx.fillStyle="#fff";ctx.font="900 25px system-ui";ctx.fillText(player.inCar?Math.round(Math.abs(car.speed)*.22)+" km/h":"A PÉ",35,72);
 if(!player.inCar){ctx.fillStyle=player.reloading?"#ffd45c":"#fff";ctx.font="800 13px system-ui";ctx.fillText(player.reloading?"RECARREGANDO...":player.ammo+" / "+player.reserve+"  •  "+weapons[player.weapon].name,35,96);if(player.hidden){ctx.fillStyle="#71e69a";ctx.font="800 10px system-ui";ctx.fillText("OCULTO NO ARBUSTO",150,43)}}
 const rx=canvas.width-248;ctx.fillStyle="#061018dc";ctx.fillRect(rx,20,228,110);ctx.fillStyle="#fff";ctx.font="800 12px system-ui";ctx.fillText("INTEGRIDADE",rx+16,43);ctx.fillStyle="#263640";ctx.fillRect(rx+16,53,196,9);ctx.fillStyle=car.health>40?"#65ff8b":"#e66";ctx.fillRect(rx+16,53,196*car.health/100,9);ctx.fillStyle="#fff";ctx.fillText("NITRO",rx+16,83);ctx.fillStyle="#263640";ctx.fillRect(rx+16,92,196,9);ctx.fillStyle="#24d9ff";ctx.fillRect(rx+16,92,196*car.nitro/100,9);
 const alive=targets.filter(t=>t.hp>0).length;ctx.fillStyle="#061018dc";ctx.fillRect(20,canvas.height-110,260,90);ctx.fillStyle="#fff";ctx.font="800 12px system-ui";
 if(gameMode==="solo"){ctx.fillText("MODO SOLO  •  KILLS "+kills,34,canvas.height-76);ctx.fillStyle="#ff8b8b";ctx.fillText("INIMIGOS RESTANTES  "+enemies.filter(e=>e.alive).length,34,canvas.height-52)}
 else{ctx.fillText("ONLINE  "+(remotePlayers.size+1)+"  •  SALA "+roomCode.toUpperCase(),34,canvas.height-76);ctx.fillStyle="#65ff8b";ctx.fillText("SEUS ABATES  "+kills,34,canvas.height-52)}
 ctx.fillStyle="#9fb0bd";ctx.fillText("ALVOS RESTANTES  "+alive,34,canvas.height-28);
 if(gameMode==="multi"){
  const rows=[{name:playerName,kills},...Array.from(ranking.values())].sort((a,b)=>b.kills-a.kills).slice(0,5);
  const rw=210,rh=28+rows.length*22,rx2=canvas.width-rw-20,ry2=150;ctx.fillStyle="#061018dc";ctx.fillRect(rx2,ry2,rw,rh);ctx.fillStyle="#fff";ctx.font="900 12px system-ui";ctx.fillText("RANK DE ABATES",rx2+14,ry2+20);
  rows.forEach((p,i)=>{ctx.fillStyle=i===0?"#ffd45c":"#dce7ee";ctx.font="700 11px system-ui";ctx.fillText((i+1)+". "+p.name,rx2+14,ry2+43+i*22);ctx.textAlign="right";ctx.fillText(String(p.kills),rx2+rw-14,ry2+43+i*22);ctx.textAlign="left"});
 }
 const mw=190,mh=120,mx=canvas.width-210,my=canvas.height-140;ctx.fillStyle="#061018e8";ctx.fillRect(mx,my,mw,mh);ctx.fillStyle="#344048";buildings.forEach(b=>ctx.fillRect(mx+b.x/W*mw,my+b.y/H*mh,b.w/W*mw,b.h/H*mh));if(!missionDone){ctx.fillStyle="#ffd65b";ctx.beginPath();ctx.arc(mx+mission.x/W*mw,my+mission.y/H*mh,4,0,Math.PI*2);ctx.fill()}ctx.fillStyle="#65ff8b";ctx.beginPath();ctx.arc(mx+player.x/W*mw,my+player.y/H*mh,4.5,0,Math.PI*2);ctx.fill();
 const near=!player.inCar&&Math.hypot(player.x-car.x,player.y-car.y)<82;if(near){ctx.fillStyle="#081119e8";ctx.fillRect(canvas.width/2-105,canvas.height-93,210,38);ctx.fillStyle="#dfffe6";ctx.font="900 13px system-ui";ctx.fillText("E  ENTRAR NO VEÍCULO",canvas.width/2-83,canvas.height-68)}
 if(paused){ctx.fillStyle="#030609aa";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="900 44px system-ui";ctx.fillText("PAUSADO",canvas.width/2,canvas.height/2);ctx.textAlign="left"}
 if(flash>0){ctx.fillStyle="rgba(255,90,90,"+Math.min(.28,flash*.2)+")";ctx.fillRect(0,0,canvas.width,canvas.height)}
 drawCrosshair()
}
function render(){
 ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,canvas.width,canvas.height);ctx.save();ctx.translate(0,canvas.height*(1-VIEW_TILT)/2);ctx.scale(1,VIEW_TILT);ctx.translate(-cam.x,-cam.y);
 road();drawBuildings();drawTrees();drawBushes(true);drawWeaponPickups();drawMission();drawTargets();drawEnemies();
 for(const s of skids){ctx.globalAlpha=Math.max(0,s.t*.4);ctx.save();ctx.translate(s.x,s.y);ctx.rotate(s.a);ctx.fillStyle="#090a0b";ctx.fillRect(-18,-12,36,3);ctx.fillRect(-18,9,36,3);ctx.restore()}ctx.globalAlpha=1;
 traffic.forEach(t=>drawVehicle(t.x,t.y,t.a,t.c,54,27));drawVehicle(car.x,car.y,car.angle,car.health>40?"#65ff8b":"#d86770");drawPlayer();drawRemotePlayers();drawBushes(false);
 bullets.forEach(b=>{ctx.fillStyle=b.color||"#ffe36e";ctx.beginPath();ctx.arc(b.x,b.y,3,0,Math.PI*2);ctx.fill()});ctx.fillStyle="#d9b761";shells.forEach(s=>ctx.fillRect(s.x,s.y,3,2));
 sparks.forEach(s=>{ctx.fillStyle="#ffd76b";ctx.fillRect(s.x,s.y,3,3)});hitMarks.forEach(h=>{ctx.strokeStyle="#fff";ctx.beginPath();ctx.moveTo(h.x-8,h.y-8);ctx.lineTo(h.x+8,h.y+8);ctx.moveTo(h.x+8,h.y-8);ctx.lineTo(h.x-8,h.y+8);ctx.stroke()});
 ctx.restore();hud()
}
let last=performance.now();function loop(t){const dt=Math.min(.033,(t-last)/1000);last=t;update(dt);render();requestAnimationFrame(loop)}requestAnimationFrame(loop);
for(const btn of document.querySelectorAll("[data-key]")){const k=btn.dataset.key;const down=e=>{e.preventDefault();keys[k]=true},up=e=>{e.preventDefault();keys[k]=false};btn.addEventListener("pointerdown",down);btn.addEventListener("pointerup",up);btn.addEventListener("pointercancel",up);btn.addEventListener("pointerleave",up)}
for(const btn of document.querySelectorAll('[data-action="e"]'))btn.addEventListener("click",toggleCar);
function bindJoystick(id,axis){
 const el=document.getElementById(id);if(!el)return;
 const knob=el.querySelector(".stick-knob");let active=null;
 const reset=()=>{axis.x=0;axis.y=0;knob.style.left="50%";knob.style.top="50%";active=null};
 el.addEventListener("pointerdown",e=>{e.preventDefault();active=e.pointerId;el.setPointerCapture(active);move(e)});
 function move(e){if(e.pointerId!==active)return;const r=el.getBoundingClientRect(),radius=r.width*.34;
  const dx=e.clientX-(r.left+r.width/2),dy=e.clientY-(r.top+r.height/2),len=Math.hypot(dx,dy),scale=Math.min(1,radius/(len||1));
  axis.x=dx*scale/radius;axis.y=dy*scale/radius;
  knob.style.left=(50+axis.x*34)+"%";knob.style.top=(50+axis.y*34)+"%";
 }
 el.addEventListener("pointermove",move);
 el.addEventListener("pointerup",e=>{if(e.pointerId===active)reset()});
 el.addEventListener("pointercancel",reset);
 el.addEventListener("lostpointercapture",reset);
}
bindJoystick("moveStick",touchMove);bindJoystick("aimStick",touchAim);
document.querySelector('[data-action="reload"]')?.addEventListener("click",startReload);
