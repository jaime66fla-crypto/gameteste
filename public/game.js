const canvas=document.getElementById("gameCanvas"),ctx=canvas.getContext("2d"),W=2800,H=1900;
const touchMove={x:0,y:0},touchAim={x:0,y:0};

function resizeGameCanvas(){
 const wrap=document.getElementById("gameWrap");
 if(!wrap)return;
 const rect=wrap.getBoundingClientRect();
 if(rect.width<2||rect.height<2)return;
 const dpr=Math.min(window.devicePixelRatio||1,2);
 const w=Math.max(640,Math.floor(rect.width*dpr));
 const h=Math.max(360,Math.floor(rect.height*dpr));
 if(canvas.width!==w||canvas.height!==h){
  canvas.width=w;
  canvas.height=h;
 }
}
addEventListener("resize",resizeGameCanvas);
document.addEventListener("fullscreenchange",()=>setTimeout(resizeGameCanvas,50));

// 2.5D visual projection: world physics remains in the original XY plane.
const VIEW_TILT=.78;
function getViewZoom(){return player.weapon==="rifle"?.78:1}
function screenToWorldY(y){const z=getViewZoom();return cam.y+(y-canvas.height*(1-VIEW_TILT)/2)/(VIEW_TILT*z);}
function worldToScreenY(y){const z=getViewZoom();return (y-cam.y)*VIEW_TILT*z+canvas.height*(1-VIEW_TILT)/2;}
const keys={},cam={x:0,y:0},mouse={x:0,y:0,down:false};
const player={x:480,y:440,r:16,speed:190,inCar:false,angle:0,walk:0,ammo:12,reserve:72,maxAmmo:12,reloading:false,reloadT:0,shootCd:0,health:100,maxHealth:100,weapon:"pistol",carHitCd:0,hidden:false,dead:false,respawnT:0,roof:null,hitT:0,hitKick:0};
const characterStyle=(()=>{try{return {...{outfit:"#e23b43",skin:"#d7b08c",hair:"#151a21"},...JSON.parse(localStorage.getItem("streetCharacter")||"{}")}}catch(_){return {outfit:"#e23b43",skin:"#d7b08c",hair:"#151a21"}}})();
const weapons={
 pistol:{name:"PISTOLA",mag:12,reserve:72,fire:.16,speed:980,spread:.025,pellets:1,damage:1,color:"#ffe36e"},
 smg:{name:"SMG",mag:30,reserve:120,fire:.075,speed:930,spread:.07,pellets:1,damage:1,color:"#7ee8ff"},
 shotgun:{name:"ESCOPETA",mag:6,reserve:36,fire:.62,speed:820,spread:.34,pellets:7,damage:1,color:"#ffbd69"},
 rifle:{name:"RIFLE",mag:20,reserve:80,fire:.12,speed:1250,spread:.012,pellets:1,damage:2,color:"#b9ff7a"},
 lmg:{name:"METRALHADORA LEVE",mag:60,reserve:240,fire:.06,speed:970,spread:.085,pellets:1,damage:1,color:"#ffd36a"},
 sawedoff:{name:"ESCOPETA CERRADA",mag:2,reserve:40,fire:.78,speed:760,spread:.52,pellets:10,damage:1,color:"#ff8f5a"}
};
const car={x:590,y:440,angle:0,speed:0,acc:430,max:470,turn:2.5,health:100,nitro:100,enemyHitCd:0};
let started=false,paused=false,missionDone=false,flash=0,skids=[],sparks=[],damageChunks=[],bullets=[],remoteBullets=[],enemyBullets=[],missiles=[],shells=[],hitMarks=[],weaponPickups=[],pickupRespawns=[];
let socket=null,myId=null,netTimer=0,connectionStatus="offline",reconnectAttempts=0,playerName="Jogador",roomCode="cidade-1",gameMode="solo",kills=0,bossSpawned=false,bossDefeated=false;
let bossPhaseIntro=0,bossPhaseIntroTotal=3,bossIntroBoss=null;

let audioCtx=null,audioMaster=null,soundEnabled=localStorage.getItem("streetSound")!=="off",engineOsc=null,engineGain=null;
function ensureAudio(){
 if(!soundEnabled)return null;
 if(!audioCtx){
  audioCtx=new (window.AudioContext||window.webkitAudioContext)();
  audioMaster=audioCtx.createGain();audioMaster.gain.value=.42;audioMaster.connect(audioCtx.destination);
 }
 if(audioCtx.state==="suspended")audioCtx.resume().catch(()=>{});
 return audioCtx;
}
function tone(freq=440,dur=.08,type="square",vol=.18,slide=1){
 const ac=ensureAudio();if(!ac)return;
 const o=ac.createOscillator(),g=ac.createGain(),t=ac.currentTime;
 o.type=type;o.frequency.setValueAtTime(freq,t);o.frequency.exponentialRampToValueAtTime(Math.max(30,freq*slide),t+dur);
 g.gain.setValueAtTime(Math.max(.0001,vol),t);g.gain.exponentialRampToValueAtTime(.0001,t+dur);
 o.connect(g);g.connect(audioMaster);o.start(t);o.stop(t+dur+.02);
}
function noise(dur=.08,vol=.12,filterFreq=1600){
 const ac=ensureAudio();if(!ac)return;
 const len=Math.max(1,Math.floor(ac.sampleRate*dur)),buf=ac.createBuffer(1,len,ac.sampleRate),data=buf.getChannelData(0);
 for(let i=0;i<len;i++)data[i]=Math.random()*2-1;
 const src=ac.createBufferSource(),f=ac.createBiquadFilter(),g=ac.createGain(),t=ac.currentTime;
 src.buffer=buf;f.type="lowpass";f.frequency.value=filterFreq;g.gain.setValueAtTime(vol,t);g.gain.exponentialRampToValueAtTime(.0001,t+dur);
 src.connect(f);f.connect(g);g.connect(audioMaster);src.start(t);
}
function playSound(name){
 if(!soundEnabled)return;
 switch(name){
  case "pistol": noise(.055,.12,2600);tone(160,.07,"square",.12,.55);break;
  case "smg": noise(.035,.09,3200);tone(190,.045,"square",.08,.65);break;
  case "shotgun": noise(.14,.22,1800);tone(105,.16,"sawtooth",.16,.45);break;
  case "rifle": noise(.07,.14,3600);tone(220,.065,"square",.11,.5);break;
  case "lmg": noise(.055,.13,2600);tone(145,.055,"square",.09,.58);break;
  case "sawedoff": noise(.18,.26,1500);tone(88,.19,"sawtooth",.18,.38);break;
  case "reload": tone(520,.035,"square",.08,1.05);setTimeout(()=>tone(330,.055,"square",.08,.9),180);break;
  case "damage": noise(.09,.08,900);tone(82,.12,"sawtooth",.09,.65);break;
  case "death": tone(120,.34,"sawtooth",.16,.28);break;
  case "pickup": tone(520,.08,"sine",.08,1.35);setTimeout(()=>tone(760,.1,"sine",.07,1.15),70);break;
  case "car": tone(125,.12,"sawtooth",.09,.8);break;
  case "nitro": noise(.12,.06,1100);tone(180,.14,"sawtooth",.05,1.4);break;
 }
}
function updateEngineSound(){
 if(!soundEnabled||!player.inCar||paused||player.dead){
  if(engineGain)engineGain.gain.setTargetAtTime(.0001,audioCtx?.currentTime||0,.05);
  return;
 }
 const ac=ensureAudio();if(!ac)return;
 if(!engineOsc){
  engineOsc=ac.createOscillator();engineGain=ac.createGain();engineOsc.type="sawtooth";engineGain.gain.value=.0001;
  engineOsc.connect(engineGain);engineGain.connect(audioMaster);engineOsc.start();
 }
 const speed=Math.abs(car.speed),freq=55+speed*.34;
 engineOsc.frequency.setTargetAtTime(freq,ac.currentTime,.045);
 engineGain.gain.setTargetAtTime(.025+Math.min(.075,speed/6500),ac.currentTime,.06);
}
function refreshSoundButton(){
 const b=document.getElementById("soundBtn");if(b)b.textContent=soundEnabled?"Som ON":"Som OFF";
}
document.getElementById("soundBtn")?.addEventListener("click",()=>{
 soundEnabled=!soundEnabled;localStorage.setItem("streetSound",soundEnabled?"on":"off");
 if(soundEnabled)ensureAudio();else if(engineGain&&audioCtx)engineGain.gain.setTargetAtTime(.0001,audioCtx.currentTime,.03);
 refreshSoundButton();
});
refreshSoundButton();
addEventListener("pointerdown",()=>ensureAudio(),{once:true});
addEventListener("keydown",()=>ensureAudio(),{once:true});

const remotePlayers=new Map();
const ranking=new Map();
const enemies=[];
const mission={x:2440,y:1560,r:48};
const buildings=[
{x:80,y:70,w:360,h:240},{x:700,y:70,w:300,h:250},{x:1280,y:60,w:300,h:270},{x:1840,y:80,w:270,h:235},{x:2380,y:70,w:320,h:250},
{x:80,y:570,w:350,h:250},{x:710,y:570,w:300,h:240},{x:1270,y:570,w:300,h:250},{x:1840,y:570,w:270,h:245},{x:2380,y:570,w:320,h:250},
{x:80,y:1070,w:350,h:230},{x:710,y:1070,w:300,h:230},{x:1270,y:1070,w:300,h:230},{x:1840,y:1070,w:270,h:230},{x:2380,y:1070,w:320,h:230},
{x:80,y:1580,w:350,h:230},{x:710,y:1580,w:300,h:230},{x:1270,y:1580,w:300,h:230},{x:1840,y:1580,w:270,h:230},{x:2380,y:1580,w:320,h:230}];

const ladders=buildings.map((b,i)=>({
 building:i,
 x:b.x+b.w*.5-18,
 y:b.y+b.h+6,
 w:36,
 h:66
}));
function ladderForBuilding(index){return ladders.find(l=>l.building===index)}
function pointInBuilding(x,y,b,pad=0){return x>b.x+pad&&x<b.x+b.w-pad&&y>b.y+pad&&y<b.y+b.h-pad}
function tryRoofMovement(dx,dy,dt,run){
 const step=player.speed*run*dt,m=Math.hypot(dx,dy)||1;
 const vx=dx/m*step,vy=dy/m*step;

 if(player.roof!==null){
  const b=buildings[player.roof],l=ladderForBuilding(player.roof);
  const nx=player.x+vx,ny=player.y+vy;
  const ladderCenter=l.x+l.w/2;
  const exitZone=Math.abs(player.x-ladderCenter)<=30&&player.y>=b.y+b.h-68;
  if(exitZone&&dy>0){
   player.roof=null;
   player.x=ladderCenter;
   player.y=b.y+b.h+34;
   playSound("pickup");
   return;
  }
  player.x=Math.max(b.x+player.r,Math.min(b.x+b.w-player.r,nx));
  player.y=Math.max(b.y+player.r,Math.min(b.y+b.h-player.r,ny));
  return;
 }

 // Rooftops are never entered by crossing a building edge.
 // The only valid entry is the ladder zone outside the south wall.
 for(let i=0;i<buildings.length;i++){
  const b=buildings[i],l=ladderForBuilding(i),ladderCenter=l.x+l.w/2;
  const inLadderX=Math.abs(player.x-ladderCenter)<=34;
  const inLadderY=player.y>=b.y+b.h+6&&player.y<=b.y+b.h+70;
  if(inLadderX&&inLadderY&&dy<-.18){
   player.roof=i;
   player.x=ladderCenter;
   player.y=b.y+b.h-34;
   playSound("pickup");
   return;
  }
 }

 const nx=player.x+vx,ny=player.y+vy;
 if(!collides(nx,player.y,player.r))player.x=nx;
 if(!collides(player.x,ny,player.r))player.y=ny;
}

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
function spawnWeaponPickups(count=14){weaponPickups.length=0;const types=["smg","shotgun","rifle","pistol","lmg","sawedoff"];for(let i=0;i<count;i++){const p=randomOpenPoint();weaponPickups.push({x:p.x,y:p.y,type:types[Math.floor(Math.random()*types.length)],spin:Math.random()*6.28})}}
function equipWeapon(type){const w=weapons[type];if(!w)return;player.weapon=type;player.maxAmmo=w.mag;player.ammo=w.mag;player.reserve=w.reserve;player.reloading=false;flash=.18;playSound("pickup")}
function updatePickups(dt){
 for(const p of weaponPickups){p.spin+=dt*2.2;if(!player.inCar&&Math.hypot(player.x-p.x,player.y-p.y)<34){equipWeapon(p.type);pickupRespawns.push({t:18,type:p.type});p.dead=true}}
 weaponPickups=weaponPickups.filter(p=>!p.dead);
 for(const r of pickupRespawns)r.t-=dt;
 const ready=pickupRespawns.filter(r=>r.t<=0);pickupRespawns=pickupRespawns.filter(r=>r.t>0);
 for(const r of ready){const p=randomOpenPoint();weaponPickups.push({x:p.x,y:p.y,type:r.type,spin:Math.random()*6.28})}
}
function updateBushState(){player.hidden=!player.inCar&&!player.dead&&bushes.some(b=>Math.hypot(player.x-b.x,player.y-b.y)<b.r*.72)}

function spawnDamageBurst(x,y,angle=player.angle,strong=false){
 const count=strong?18:9;
 for(let i=0;i<count;i++){
  const a=angle+Math.PI+(Math.random()-.5)*1.7;
  const speed=(strong?115:75)+Math.random()*(strong?180:120);
  damageChunks.push({
   x:x+(Math.random()-.5)*12,y:y+(Math.random()-.5)*12,
   vx:Math.cos(a)*speed,vy:Math.sin(a)*speed,
   t:(strong?.65:.38)+Math.random()*.35,
   maxT:strong?1:.7,
   r:1.8+Math.random()*(strong?3.8:2.5),
   spin:(Math.random()-.5)*10,
   rot:Math.random()*6.28,
   dark:Math.random()<.35
  });
 }
}
function damagePlayer(amount){
 if(player.dead||player.inCar)return;
 player.health=Math.max(0,player.health-amount);
 player.hitT=.22;
 player.hitKick=Math.min(7,2.5+amount*.7);
 spawnDamageBurst(player.x,player.y,player.angle,player.health<=0);
 flash=Math.max(flash,.7);playSound("damage");
 if(navigator.vibrate&&selectedPlatform==="mobile")navigator.vibrate(player.health<=0?[80,45,120]:45);
 if(player.health<=0)killPlayer();
}
function killPlayer(){
 if(player.dead)return;
 player.dead=true;
 player.respawnT=3;
 player.health=0;playSound("death");
 player.reloading=false;
 mouse.down=false;
 touchMove.x=touchMove.y=touchAim.x=touchAim.y=0;
 for(const k of Object.keys(keys))keys[k]=false;
}
function respawnPlayer(){
 const p=randomOpenPoint();
 player.x=p.x;player.y=p.y;
 player.health=player.maxHealth;
 player.dead=false;
 player.respawnT=0;
 player.inCar=false;
 player.roof=null;
 player.ammo=player.maxAmmo;
 player.reloading=false;
 flash=.4;
}


addEventListener("keydown",e=>{
 const k=e.key.toLowerCase();keys[k]=true;
 if(k==="e")toggleCar();if(k==="p")togglePause();if(k==="r")startReload();
 if([" ","arrowup","arrowdown","arrowleft","arrowright"].includes(k))e.preventDefault()
},{passive:false});
addEventListener("keyup",e=>keys[e.key.toLowerCase()]=false);
canvas.addEventListener("mousemove",e=>{const r=canvas.getBoundingClientRect();const scale=Math.min(r.width/canvas.width,r.height/canvas.height),ox=(r.width-canvas.width*scale)/2,oy=(r.height-canvas.height*scale)/2,z=getViewZoom();mouse.x=cam.x+(e.clientX-r.left-ox)/(scale*z);mouse.y=screenToWorldY((e.clientY-r.top-oy)/scale)});
canvas.addEventListener("mousedown",e=>{if(e.button===0){mouse.down=true;shoot()}});
addEventListener("mouseup",e=>{if(e.button===0)mouse.down=false});
canvas.addEventListener("contextmenu",e=>e.preventDefault());
let selectedPlatform=localStorage.getItem("streetPlatform")|| (matchMedia("(pointer:coarse)").matches?"mobile":"desktop");
function setPlatform(platform){
 selectedPlatform=platform;
 localStorage.setItem("streetPlatform",platform);
 document.body.classList.toggle("platform-mobile",platform==="mobile");
 document.body.classList.toggle("platform-desktop",platform==="desktop");
 document.getElementById("desktopPlatformBtn")?.classList.toggle("active",platform==="desktop");
 document.getElementById("mobilePlatformBtn")?.classList.toggle("active",platform==="mobile");
 const help=document.getElementById("controlHelp");
 if(help)help.textContent=platform==="mobile"
  ?"Analógico esquerdo mover • Analógico direito mirar e atirar • CARRO entrar/sair"
  :"WASD mover • Mouse mirar • Clique atirar • R recarregar • E veículo";
 if(platform==="mobile"&&screen.orientation?.lock)screen.orientation.lock("landscape").catch(()=>{});
}
document.getElementById("desktopPlatformBtn")?.addEventListener("click",()=>setPlatform("desktop"));
document.getElementById("mobilePlatformBtn")?.addEventListener("click",()=>setPlatform("mobile"));
setPlatform(selectedPlatform);
document.getElementById("soloModeBtn").onclick=()=>setGameMode("solo");
const savedName=localStorage.getItem("streetPlayerName");
if(savedName&&document.getElementById("playerName"))document.getElementById("playerName").value=savedName;
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
 if(selectedPlatform==="mobile"&&screen.orientation?.lock)screen.orientation.lock("landscape").catch(()=>{});
 localStorage.setItem("streetPlayerName",(document.getElementById("playerName")?.value||"Jogador").trim());
 playerName=(document.getElementById("playerName")?.value||"Jogador").trim().slice(0,18)||"Jogador";
 roomCode=(document.getElementById("roomCode")?.value||"cidade-1").trim().toLowerCase().replace(/[^a-z0-9-]/g,"").slice(0,24)||"cidade-1";
 started=true;document.getElementById("startOverlay").classList.add("hidden");resizeGameCanvas();canvas.focus();spawnWeaponPickups();
 if(gameMode==="multi")connectMultiplayer(); else spawnEnemies();
 if(!localStorage.getItem("streetTutorialDone"))startTutorial();
};
document.getElementById("pauseBtn").onclick=togglePause;
document.getElementById("resumeBtn")?.addEventListener("click",()=>setPauseState(false));
document.getElementById("controlsBtn")?.addEventListener("click",()=>{setPauseState(false);startTutorial(true)});
document.getElementById("pauseRestartBtn")?.addEventListener("click",()=>location.reload());
document.getElementById("pauseExitBtn")?.addEventListener("click",()=>location.reload());
document.getElementById("restartBtn").onclick=()=>location.reload();
document.getElementById("fullscreenBtn").onclick=()=>{const el=document.getElementById("gameWrap");document.fullscreenElement?document.exitFullscreen():el.requestFullscreen?.()};


const tutorialSteps={
 desktop:[
  {title:"Movimente-se",text:"Use WASD para andar pela cidade."},
  {title:"Mire e atire",text:"Mova o mouse para mirar e clique para atirar."},
  {title:"Use veículos",text:"Aproxime-se de um carro e pressione E para entrar ou sair."}
 ],
 mobile:[
  {title:"Movimente-se",text:"Use o analógico esquerdo para andar pela cidade."},
  {title:"Mire e atire",text:"Puxe o analógico direito para mirar. Ao afastar do centro, você atira."},
  {title:"Use veículos",text:"Aproxime-se de um carro e toque em CARRO para entrar ou sair."}
 ]
};
let tutorialIndex=0;
function renderTutorial(){
 const steps=tutorialSteps[selectedPlatform]||tutorialSteps.desktop,step=steps[tutorialIndex];
 document.getElementById("tutorialTitle").textContent=step.title;
 document.getElementById("tutorialText").textContent=step.text;
 document.querySelectorAll(".tutorial-dots i").forEach((el,i)=>el.classList.toggle("active",i===tutorialIndex));
 document.getElementById("tutorialNextBtn").textContent=tutorialIndex===steps.length-1?"Começar":"Próximo";
}
function startTutorial(force=false){
 tutorialIndex=0;
 const overlay=document.getElementById("tutorialOverlay");
 if(!overlay)return;
 overlay.classList.remove("hidden");
 paused=true;
 document.getElementById("pauseBtn").textContent="Continuar";
 renderTutorial();
 if(force)overlay.dataset.force="1"; else delete overlay.dataset.force;
}
function finishTutorial(){
 document.getElementById("tutorialOverlay")?.classList.add("hidden");
 localStorage.setItem("streetTutorialDone","1");
 paused=false;
 document.getElementById("pauseBtn").textContent="Pausar";
 canvas.focus();
}
document.getElementById("tutorialNextBtn")?.addEventListener("click",()=>{
 const steps=tutorialSteps[selectedPlatform]||tutorialSteps.desktop;
 if(tutorialIndex<steps.length-1){tutorialIndex++;renderTutorial()}else finishTutorial();
});
document.getElementById("tutorialSkipBtn")?.addEventListener("click",finishTutorial);

function connectMultiplayer(){
 try{
  if(socket)socket.close();
  const proto=location.protocol==="https:"?"wss:":"ws:";
  socket=new WebSocket(proto+"//"+location.host+"/ws?room="+encodeURIComponent(roomCode));
  socket.onopen=()=>{connectionStatus="connected";reconnectAttempts=0;sendNetState(true)};
  socket.onmessage=e=>{
   try{
    const m=JSON.parse(e.data);
    if(m.type==="welcome"){myId=m.id;return}
    if(m.type==="state"&&m.id!==myId){
     const prev=remotePlayers.get(m.id);
     remotePlayers.set(m.id,{...m,renderX:prev?.renderX??m.x,renderY:prev?.renderY??m.y,seen:performance.now()});
     ranking.set(m.id,{name:m.name||"Jogador",kills:m.kills||0})
    }
    if(m.type==="shot"&&m.id!==myId){
     remoteBullets.push({
      x:Number(m.x)||0,y:Number(m.y)||0,vx:Number(m.vx)||0,vy:Number(m.vy)||0,
      t:Number(m.t)||1,damage:Number(m.damage)||1,color:String(m.color||"#7ee8ff"),
      layer:m.layer===null?null:Number(m.layer),ownerId:m.id
     });
     const wp=String(m.weapon||"pistol");playSound(weapons[wp]?wp:"pistol");
    }
    if(m.type==="hit"&&m.targetId===myId){
     // Legacy compatibility only. Damage is resolved from received projectile collision.
    }
    if(m.type==="ranking"){ranking.clear();for(const p of m.players||[])ranking.set(p.id,{name:p.name,kills:p.kills||0})}
    if(m.type==="leave"){remotePlayers.delete(m.id);ranking.delete(m.id)}
   }catch(_){}
  };
  socket.onerror=()=>{connectionStatus="error"};
  socket.onclose=()=>{connectionStatus="offline";remotePlayers.clear();ranking.clear();if(started&&gameMode==="multi"&&reconnectAttempts++<3)setTimeout(()=>{if(started&&gameMode==="multi")connectMultiplayer()},1800)};
 }catch(_){}
}
function sendNetState(force=false){
 if(gameMode!=="multi"||!socket||socket.readyState!==WebSocket.OPEN)return;
 const msg={type:"state",name:playerName,x:player.x,y:player.y,angle:player.angle,inCar:player.inCar,shooting:player.shootCd>.1,weapon:player.weapon,kills,health:player.health,dead:player.dead,roof:player.roof};
 socket.send(JSON.stringify(msg));
}
function setPauseState(value){
 if(!started)return;
 paused=value;
 document.getElementById("pauseBtn").textContent=paused?"Continuar":"Pausar";
 document.getElementById("pauseOverlay")?.classList.toggle("hidden",!paused);
}
function togglePause(){setPauseState(!paused)}
function toggleCar(){
 if(!started||paused||player.dead||player.roof!==null)return;
 playSound("car");
 if(player.inCar){
  player.inCar=false;
  const ex=car.x+Math.cos(car.angle+Math.PI/2)*58,ey=car.y+Math.sin(car.angle+Math.PI/2)*58;
  const p=findNearestFreePoint(ex,ey,player.r);player.x=p.x;player.y=p.y;
 }
 else if(car.health>0&&Math.hypot(player.x-car.x,player.y-car.y)<82){player.inCar=true;player.x=car.x;player.y=car.y}
}
function collides(x,y,r=20){if(x-r<0||y-r<0||x+r>W||y+r>H)return true;return buildings.some(b=>x+r>b.x&&x-r<b.x+b.w&&y+r>b.y&&y-r<b.y+b.h)}
function segmentPointDistance(x1,y1,x2,y2,px,py){
 const dx=x2-x1,dy=y2-y1,l2=dx*dx+dy*dy;
 if(l2<=.0001)return Math.hypot(px-x1,py-y1);
 let t=((px-x1)*dx+(py-y1)*dy)/l2;t=Math.max(0,Math.min(1,t));
 const cx=x1+t*dx,cy=y1+t*dy;
 return Math.hypot(px-cx,py-cy);
}
function findNearestFreePoint(x,y,r=20){
 if(!collides(x,y,r))return{x,y};
 for(let ring=1;ring<=10;ring++){
  const radius=ring*18;
  for(let i=0;i<16;i++){
   const a=i*Math.PI/8,nx=x+Math.cos(a)*radius,ny=y+Math.sin(a)*radius;
   if(!collides(nx,ny,r))return{x:nx,y:ny};
  }
 }
 return randomOpenPoint();
}
function ensurePlayerNotStuck(){
 if(player.roof!==null||player.inCar||player.dead)return;
 if(collides(player.x,player.y,player.r)){
  const p=findNearestFreePoint(player.x,player.y,player.r);
  player.x=p.x;player.y=p.y;
 }
}
function projectileHitsWall(x1,y1,x2,y2,layer=null){
 const dist=Math.hypot(x2-x1,y2-y1),steps=Math.max(1,Math.ceil(dist/8));
 for(let i=1;i<=steps;i++){
  const t=i/steps,x=x1+(x2-x1)*t,y=y1+(y2-y1)*t;
  if(x<0||y<0||x>W||y>H)return true;
  if(layer===null&&buildings.some(b=>pointInBuilding(x,y,b,0)))return true;
 }
 return false;
}
function projectileOutOfWorld(x1,y1,x2,y2){
 return x2<0||y2<0||x2>W||y2>H;
}
function startReload(){if(player.inCar||player.reloading||player.ammo===player.maxAmmo||player.reserve<=0)return;player.reloading=true;player.reloadT=(player.weapon==="shotgun"||player.weapon==="sawedoff")?1.35:player.weapon==="lmg"?1.65:1.05;playSound("reload")}
function shoot(){
 if(!started||paused||player.dead||player.inCar||player.reloading||player.shootCd>0)return;
 if(player.ammo<=0){startReload();return}
 const w=weapons[player.weapon];player.ammo--;player.shootCd=w.fire;playSound(player.weapon);
 for(let i=0;i<w.pellets;i++){
  const a=player.angle+(Math.random()-.5)*w.spread,ox=player.x+Math.cos(a)*28,oy=player.y+Math.sin(a)*28;
  const bt=player.weapon==="rifle"?1.15:player.weapon==="sawedoff"?.58:.9,bvx=Math.cos(a)*w.speed,bvy=Math.sin(a)*w.speed;
  bullets.push({x:ox,y:oy,vx:bvx,vy:bvy,t:bt,damage:w.damage,color:w.color,layer:player.roof});
  if(gameMode==="multi"&&socket?.readyState===WebSocket.OPEN){
   socket.send(JSON.stringify({type:"shot",weapon:player.weapon,x:ox,y:oy,vx:bvx,vy:bvy,t:bt,damage:w.damage,color:w.color,layer:player.roof}));
  }
 }
 shells.push({x:player.x,y:player.y,vx:Math.cos(player.angle+Math.PI/2)*(50+Math.random()*35),vy:Math.sin(player.angle+Math.PI/2)*(50+Math.random()*35),t:.5});
 if(player.ammo===0&&player.reserve>0)setTimeout(()=>{if(started&&!paused)startReload()},180);
}
function spawnEnemies(){
 enemies.length=0;bossSpawned=false;bossDefeated=false;
 const pts=[[900,440],[1400,950],[2050,1450],[2400,950],[600,1450],[1700,440],[1150,1450],[2520,1450],[850,950],[1980,440]];
 for(let i=0;i<pts.length;i++){
  const sniper=i%4===1;
  enemies.push({
   x:pts[i][0],y:pts[i][1],r:16,
   hp:sniper?2:3,maxHp:sniper?2:3,
   angle:0,speed:sniper?82:70,shootCd:Math.random()*1.5,
   alive:true,boss:false,type:sniper?"sniper":"pistol",
   roof:null,targetRoof:null,climbing:false
  });
 }
}
function spawnBoss(){
 if(bossSpawned||bossDefeated||gameMode!=="solo")return;
 bossSpawned=true;
 const p=randomOpenPoint();
 enemies.push({x:p.x,y:p.y,r:38,hp:60,maxHp:60,angle:0,speed:52,shootCd:.7,alive:true,boss:true,phase:1,missileCd:2.4});
 flash=1;playSound("death");
}
function getBoss(){return enemies.find(e=>e.boss&&e.alive)}

const SNIPER_RANGE=W*.80;
function nearestRoofForEnemy(e){
 let best=null,bestScore=Infinity;
 for(let i=0;i<ladders.length;i++){
  const l=ladders[i],b=buildings[i],lx=l.x+l.w/2,ly=l.y+l.h*.45;
  const walkDist=Math.hypot(e.x-lx,e.y-ly);
  const roofX=b.x+b.w*.5,roofY=b.y+b.h*.5;
  const playerDist=Math.hypot(player.x-roofX,player.y-roofY);
  const canShoot=playerDist<=SNIPER_RANGE;
  const score=(canShoot?0:100000)+playerDist*.65+walkDist*.35;
  if(score<bestScore){bestScore=score;best=i}
 }
 return best;
}
function bestSniperRoof(e){
 let best=e.roof,bestDist=Infinity;
 for(let i=0;i<buildings.length;i++){
  const b=buildings[i],cx=b.x+b.w*.5,cy=b.y+b.h*.5;
  const d=Math.hypot(player.x-cx,player.y-cy);
  if(d<=SNIPER_RANGE&&d<bestDist){bestDist=d;best=i}
 }
 return best;
}
function moveEnemyGround(e,tx,ty,dt){
 const dx=tx-e.x,dy=ty-e.y,d=Math.hypot(dx,dy)||1,step=e.speed*dt;
 const nx=e.x+dx/d*step,ny=e.y+dy/d*step;
 if(!collides(nx,e.y,e.r))e.x=nx;
 if(!collides(e.x,ny,e.r))e.y=ny;
}
function moveEnemyOnRoof(e,tx,ty,dt){
 const b=buildings[e.roof];if(!b)return;
 const dx=tx-e.x,dy=ty-e.y,d=Math.hypot(dx,dy)||1,step=e.speed*dt;
 e.x=Math.max(b.x+e.r,Math.min(b.x+b.w-e.r,e.x+dx/d*step));
 e.y=Math.max(b.y+e.r,Math.min(b.y+b.h-e.r,e.y+dy/d*step));
}
function updateSniperEnemy(e,dt){
 if(e.roof===null){
  if(e.targetRoof===null)e.targetRoof=nearestRoofForEnemy(e);
  const l=ladderForBuilding(e.targetRoof),b=buildings[e.targetRoof];
  if(!l||!b){e.targetRoof=nearestRoofForEnemy(e);return}
  const lx=l.x+l.w/2,ly=l.y+l.h*.45;
  e.angle=Math.atan2(ly-e.y,lx-e.x);
  if(Math.hypot(e.x-lx,e.y-ly)>20){
   moveEnemyGround(e,lx,ly,dt);
  }else{
   e.roof=e.targetRoof;e.climbing=false;e.descending=false;
   e.x=lx;e.y=b.y+b.h-34;
  }
  return;
 }

 const b=buildings[e.roof],l=ladderForBuilding(e.roof);
 const dx=player.x-e.x,dy=player.y-e.y,d=Math.hypot(dx,dy)||1;
 e.angle=Math.atan2(dy,dx);

 // If the player leaves the sniper's effective 80% map range,
 // walk to the ladder, descend and relocate to a better rooftop.
 if(d>SNIPER_RANGE||e.descending){
  e.descending=true;
  const lx=l.x+l.w/2,ly=b.y+b.h-30;
  e.angle=Math.atan2(ly-e.y,lx-e.x);
  if(Math.hypot(e.x-lx,e.y-ly)>16){
   moveEnemyOnRoof(e,lx,ly,dt);
  }else{
   const oldRoof=e.roof;
   e.roof=null;e.descending=false;
   e.x=lx;e.y=b.y+b.h+38;
   e.targetRoof=bestSniperRoof(e);
   if(e.targetRoof===oldRoof)e.targetRoof=nearestRoofForEnemy(e);
  }
  return;
 }

 const centerX=b.x+b.w*.5,centerY=b.y+b.h*.5;
 if(Math.hypot(e.x-centerX,e.y-centerY)>58)moveEnemyOnRoof(e,centerX,centerY,dt);
 e.shootCd-=dt;
 if(!player.inCar&&!player.dead&&d<=SNIPER_RANGE&&e.shootCd<=0){
  e.shootCd=2.0+Math.random()*.8;
  const a=e.angle+(Math.random()-.5)*.025,speed=900;
  enemyBullets.push({
   x:e.x+Math.cos(a)*32,y:e.y+Math.sin(a)*32,
   vx:Math.cos(a)*speed,vy:Math.sin(a)*speed,t:SNIPER_RANGE/speed+.35,damage:22,
   boss:false,sniper:true,layer:e.roof,targetLayer:player.roof
  });
  noise(.045,.05,2600);tone(210,.06,"square",.05,.55);
 }
}

function updatePistolEnemy(e,dt){
 // Player is on a roof: normal soldiers seek that building's ladder and climb.
 if(player.roof!==null){
  if(e.roof===null){
   e.targetRoof=player.roof;
   const l=ladderForBuilding(e.targetRoof),b=buildings[e.targetRoof];
   if(!l||!b)return;
   const lx=l.x+l.w/2,ly=l.y+l.h*.45;
   e.angle=Math.atan2(ly-e.y,lx-e.x);
   if(Math.hypot(e.x-lx,e.y-ly)>20){
    moveEnemyGround(e,lx,ly,dt);
   }else{
    e.roof=e.targetRoof;
    e.x=lx;e.y=b.y+b.h-34;
   }
   return;
  }

  // If the soldier is on a different roof, descend first.
  if(e.roof!==player.roof){
   const b=buildings[e.roof],l=ladderForBuilding(e.roof);
   const lx=l.x+l.w/2,ly=b.y+b.h-30;
   e.angle=Math.atan2(ly-e.y,lx-e.x);
   if(Math.hypot(e.x-lx,e.y-ly)>16){
    moveEnemyOnRoof(e,lx,ly,dt);
   }else{
    e.roof=null;
    e.x=lx;e.y=b.y+b.h+38;
    e.targetRoof=player.roof;
   }
   return;
  }

  const dx=player.x-e.x,dy=player.y-e.y,d=Math.hypot(dx,dy)||1;
  e.angle=Math.atan2(dy,dx);
  if(d>145)moveEnemyOnRoof(e,player.x,player.y,dt);
  e.shootCd-=dt;
  if(!player.dead&&!player.inCar&&d<430&&e.shootCd<=0){
   e.shootCd=1.1+Math.random()*.8;
   const a=e.angle+(Math.random()-.5)*.08,speed=420;
   enemyBullets.push({
    x:e.x+Math.cos(a)*28,y:e.y+Math.sin(a)*28,
    vx:Math.cos(a)*speed,vy:Math.sin(a)*speed,t:1.25,damage:8,
    boss:false,layer:e.roof,targetLayer:player.roof
   });
   noise(.04,.05,1800);tone(130,.05,"square",.04,.7);
  }
  return;
 }

 // Player returned to ground: soldier leaves the rooftop by its ladder.
 if(e.roof!==null){
  const b=buildings[e.roof],l=ladderForBuilding(e.roof);
  const lx=l.x+l.w/2,ly=b.y+b.h-30;
  e.angle=Math.atan2(ly-e.y,lx-e.x);
  if(Math.hypot(e.x-lx,e.y-ly)>16){
   moveEnemyOnRoof(e,lx,ly,dt);
  }else{
   e.roof=null;e.targetRoof=null;
   e.x=lx;e.y=b.y+b.h+38;
  }
  return;
 }

 const dx=player.x-e.x,dy=player.y-e.y,d=Math.hypot(dx,dy)||1;
 e.angle=Math.atan2(dy,dx);
 const canSee=!player.hidden||d<125;
 if(canSee&&d>150)moveEnemyGround(e,player.x,player.y,dt);
 e.shootCd-=dt;
 if(canSee&&!player.inCar&&!player.dead&&d<420&&e.shootCd<=0){
  e.shootCd=1.1+Math.random()*.8;
  const a=e.angle+(Math.random()-.5)*.08,speed=420;
  enemyBullets.push({
   x:e.x+Math.cos(a)*28,y:e.y+Math.sin(a)*28,
   vx:Math.cos(a)*speed,vy:Math.sin(a)*speed,t:1.25,damage:8,
   boss:false,layer:null,targetLayer:null
  });
  noise(.04,.05,1800);tone(130,.05,"square",.04,.7);
 }
}

function updateEnemies(dt){
 if(gameMode!=="solo")return;
 for(const e of enemies){
  if(!e.alive)continue;
  if(!e.boss&&e.type==="sniper"){updateSniperEnemy(e,dt);continue}
  if(!e.boss&&e.type==="pistol"){updatePistolEnemy(e,dt);continue}
  const dx=player.x-e.x,dy=player.y-e.y,d=Math.hypot(dx,dy)||1;e.angle=Math.atan2(dy,dx);
  const canSee=player.roof===null&&(!player.hidden||d<(e.boss?220:125));
  if(canSee&&d>(e.boss?190:150))moveEnemyGround(e,player.x,player.y,dt);
  if(e.boss){
   const newPhase=e.hp<=e.maxHp*.5?2:1;
   if(newPhase!==e.phase){
    e.phase=newPhase;flash=1;playSound("death");
    if(newPhase===2){
     bossPhaseIntro=bossPhaseIntroTotal;
     bossIntroBoss=e;
     e.missileCd=1.2;
     enemyBullets.length=0;
     missiles.length=0;
     tone(72,.45,"sawtooth",.18,.55);
     setTimeout(()=>{if(soundEnabled){tone(96,.35,"square",.13,.7);noise(.22,.12,900)}},450);
    }
   }
   e.missileCd=(e.missileCd??2.4)-dt;
   if(e.phase===2&&bossPhaseIntro<=0&&e.missileCd<=0){
    e.missileCd=2.2+Math.random()*1.4;
    const count=2+Math.floor(Math.random()*3);
    for(let i=0;i<count;i++){
     let tx=player.x+(Math.random()-.5)*520,ty=player.y+(Math.random()-.5)*420,tries=0;
     while(collides(tx,ty,24)&&tries++<20){tx=player.x+(Math.random()-.5)*520;ty=player.y+(Math.random()-.5)*420}
     tx=Math.max(60,Math.min(W-60,tx));ty=Math.max(60,Math.min(H-60,ty));
     missiles.push({x:tx,y:ty,t:1.65,total:1.65,r:54,exploded:false,startX:tx+(Math.random()-.5)*260,startY:ty-320-Math.random()*180});
    }
   }
  }
  e.shootCd-=dt;
  if(canSee&&d<(e.boss?600:420)&&e.shootCd<=0){
   e.shootCd=e.boss?(e.phase===2?.72:.55+Math.random()*.35):1.1+Math.random()*.8;
   if(!player.inCar){
    if(e.boss&&e.phase===2){
     // Phase 2: perfect lock on the player's current position.
     // Standing still guarantees a hit; moving after the shot is fired lets the player dodge.
     const sx=e.x+Math.cos(e.angle)*38,sy=e.y+Math.sin(e.angle)*38;
     const tx=player.x,ty=player.y;
     const dd=Math.hypot(tx-sx,ty-sy)||1,speed=560;
     const vx=(tx-sx)/dd*speed,vy=(ty-sy)/dd*speed;
     enemyBullets.push({
      x:sx,y:sy,vx,vy,
      t:Math.max(1.1,dd/speed+.28),
      damage:18,boss:true,phase2:true,layer:null,targetLayer:player.roof
     });
     noise(.085,.09,1500);tone(88,.10,"square",.075,.62);
    }else{
     const shots=e.boss?3:1;
     for(let s=0;s<shots;s++){
      const spread=(Math.random()-.5)*(e.boss?.22:.08),a=e.angle+spread,speed=e.boss?470:420;
      enemyBullets.push({x:e.x+Math.cos(a)*(e.boss?38:28),y:e.y+Math.sin(a)*(e.boss?38:28),vx:Math.cos(a)*speed,vy:Math.sin(a)*speed,t:e.boss?1.45:1.25,damage:e.boss?12:8,boss:e.boss,layer:null,targetLayer:player.roof});
     }
     noise(e.boss?.07:.04,e.boss?.08:.05,e.boss?1400:1800);tone(e.boss?95:130,e.boss?.08:.05,"square",e.boss?.06:.04,.7);
    }
   }
  }
 }
}

function drawBossTank(e){
 const pulse=.5+.5*Math.sin(performance.now()/120);
 ctx.save();ctx.translate(e.x,e.y);ctx.rotate(e.angle);
 // shadow
 ctx.fillStyle="#0009";ctx.beginPath();ctx.ellipse(6,18,48,26,0,0,Math.PI*2);ctx.fill();
 // tracks
 ctx.fillStyle="#181b20";ctx.fillRect(-38,-30,20,60);ctx.fillRect(18,-30,20,60);
 ctx.fillStyle="#2b3038";
 for(let y=-25;y<=20;y+=10){ctx.fillRect(-35,y,14,6);ctx.fillRect(21,y,14,6)}
 // armored body
 ctx.fillStyle="#4a0f16";ctx.beginPath();ctx.ellipse(0,0,38,34,0,0,Math.PI*2);ctx.fill();
 ctx.strokeStyle="#8b2832";ctx.lineWidth=4;ctx.stroke();
 // spikes
 ctx.fillStyle="#6b1820";
 for(const a of [-2.5,-1.9,-1.2,-.55,.55,1.2,1.9,2.5]){
  ctx.save();ctx.rotate(a);ctx.beginPath();ctx.moveTo(30,-4);ctx.lineTo(44,0);ctx.lineTo(30,4);ctx.fill();ctx.restore();
 }
 // turret
 ctx.fillStyle="#661722";ctx.beginPath();ctx.arc(2,-2,25,0,Math.PI*2);ctx.fill();
 ctx.strokeStyle="#a5323f";ctx.lineWidth=3;ctx.stroke();
 // face visor
 ctx.fillStyle="#1a0a0d";ctx.fillRect(-10,-12,20,13);
 ctx.fillStyle="#ff2f42";ctx.shadowColor="#ff1e35";ctx.shadowBlur=10;ctx.fillRect(-7,-9,5,3);ctx.fillRect(3,-9,5,3);
 ctx.shadowBlur=0;
 // core
 ctx.fillStyle="#22070a";ctx.beginPath();ctx.arc(-6,12,10,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#ff2d3f";ctx.shadowColor="#ff2d3f";ctx.shadowBlur=14+8*pulse;ctx.beginPath();ctx.arc(-6,12,6+1.5*pulse,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0;
 // dual side cannons
 ctx.fillStyle="#2a1a1c";ctx.fillRect(18,-16,34,8);ctx.fillRect(18,8,34,8);
 ctx.fillStyle="#7c2630";ctx.fillRect(26,-14,28,4);ctx.fillRect(26,10,28,4);
 if(e.shootCd>.35){
  ctx.fillStyle="#ff7b32";ctx.shadowColor="#ff4a1f";ctx.shadowBlur=14;
  ctx.beginPath();ctx.moveTo(55,-12);ctx.lineTo(70,-18);ctx.lineTo(66,-10);ctx.lineTo(73,-8);ctx.lineTo(55,-6);ctx.closePath();ctx.fill();
  ctx.beginPath();ctx.moveTo(55,10);ctx.lineTo(70,4);ctx.lineTo(66,12);ctx.lineTo(73,14);ctx.lineTo(55,16);ctx.closePath();ctx.fill();ctx.shadowBlur=0;
 }
 ctx.restore();
 // local boss bar
 const bw=150,by=e.y-62;
 ctx.fillStyle="#0b0d10dd";ctx.fillRect(e.x-bw/2,by,bw,12);
 ctx.fillStyle="#ff3045";ctx.fillRect(e.x-bw/2+2,by+2,(bw-4)*(e.hp/e.maxHp),8);
 ctx.strokeStyle="#5d1d25";ctx.strokeRect(e.x-bw/2+.5,by+.5,bw-1,11);
 ctx.fillStyle="#fff";ctx.font="900 12px system-ui";ctx.textAlign="center";ctx.fillText("GOLIAS",e.x,by-7);ctx.textAlign="left";
}

function drawEnemies(){
 if(gameMode!=="solo")return;
 for(const e of enemies){
  if(!e.alive)continue;if(e.boss){drawBossTank(e);continue}
  const sniper=e.type==="sniper";
  drawTopDownCharacter({
   x:e.x,y:e.y,angle:e.angle,
   outfit:sniper?"#4f614d":"#7a3338",skin:"#d1a884",hair:"#1b1f22",
   weapon:sniper?"rifle":"pistol",shooting:false,role:sniper?"sniper":"enemy",showLaser:true
  });
  if(sniper){ctx.fillStyle="#8dffb7";ctx.font="900 9px system-ui";ctx.textAlign="center";ctx.fillText(e.roof===null?"SNIPER ↑":"SNIPER",e.x,e.y-40);ctx.textAlign="left"}
  ctx.fillStyle="#111";ctx.fillRect(e.x-18,e.y-33,36,5);ctx.fillStyle="#ff5f5f";ctx.fillRect(e.x-18,e.y-33,36*(e.hp/e.maxHp),5);
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
  damagePlayer(18);player.carHitCd=.85;
  for(let i=0;i<8;i++)sparks.push({x:player.x,y:player.y,vx:(Math.random()-.5)*150,vy:(Math.random()-.5)*150,t:.35});
 }
 if(t.a===0&&t.x>W+60)t.x=-60;if(t.a===Math.PI&&t.x<-60)t.x=W+60;if(t.a===Math.PI/2&&t.y>H+60)t.y=-60;if(t.a===-Math.PI/2&&t.y<-60)t.y=H+60
}}
function updateBullets(dt){
 for(const b of bullets){
  const ox=b.x,oy=b.y,nx=b.x+b.vx*dt,ny=b.y+b.vy*dt;b.t-=dt;
  const playerShotFromRoof=b.layer!==null&&b.layer!==undefined;
  const playerShotBlocked=playerShotFromRoof?projectileOutOfWorld(ox,oy,nx,ny):projectileHitsWall(ox,oy,nx,ny,null);
  if(playerShotBlocked){b.x=nx;b.y=ny;b.t=0;sparks.push({x:b.x,y:b.y,vx:(Math.random()-.5)*80,vy:(Math.random()-.5)*80,t:.25});continue}
  b.x=nx;b.y=ny;
  if(gameMode==="solo"){for(const e of enemies){
   if(!e.alive)continue;
   const enemyOnRoof=e.roof!==null&&e.roof!==undefined;
   const canHitEnemy=playerShotFromRoof||!enemyOnRoof;
   if(canHitEnemy&&Math.hypot(b.x-e.x,b.y-e.y)<e.r+6){
    e.hp-=b.damage||1;b.t=0;
    if(e.hp<=0){e.alive=false;if(e.boss){bossDefeated=true;bossSpawned=false;flash=1;playSound("pickup")}reportKill()}
    hitMarks.push({x:e.x,y:e.y,t:.25});break
   }
  }}
  if(gameMode==="multi"&&b.t>0){
   // PvP damage is resolved on the receiving client from the replicated projectile.
  }
  if(b.layer===null){for(const t of targets){if(t.hp>0&&Math.hypot(b.x-t.x,b.y-t.y)<t.r+4){t.hp--;b.t=0;hitMarks.push({x:t.x,y:t.y,t:.25});for(let i=0;i<5;i++)sparks.push({x:b.x,y:b.y,vx:(Math.random()-.5)*120,vy:(Math.random()-.5)*120,t:.35});break}}}
 }
 bullets=bullets.filter(b=>b.t>0);
 for(const b of remoteBullets){
  const ox=b.x,oy=b.y,nx=b.x+b.vx*dt,ny=b.y+b.vy*dt;b.t-=dt;
  const fromRoof=b.layer!==null&&b.layer!==undefined;
  const blocked=fromRoof?projectileOutOfWorld(ox,oy,nx,ny):projectileHitsWall(ox,oy,nx,ny,null);
  if(blocked){b.t=0;continue}
  b.x=nx;b.y=ny;

  if(gameMode==="multi"&&!player.dead&&!player.inCar&&b.ownerId!==myId){
   const playerLayer=player.roof===null?null:Number(player.roof);
   const canHitLocal=(b.layer===null&&playerLayer===null)||(b.layer!==null&&(playerLayer===b.layer||playerLayer===null));
   if(canHitLocal&&segmentPointDistance(ox,oy,nx,ny,player.x,player.y)<player.r+7){
    const before=player.health;
    damagePlayer(Math.max(1,Number(b.damage)||1));
    b.t=0;hitMarks.push({x:player.x,y:player.y,t:.25});
    if(before>0&&player.dead&&socket?.readyState===WebSocket.OPEN){
     socket.send(JSON.stringify({type:"killed",killerId:b.ownerId||null}));
    }
   }
  }
 }
 remoteBullets=remoteBullets.filter(b=>b.t>0);
 for(const b of enemyBullets){
  const ox=b.x,oy=b.y,nx=b.x+b.vx*dt,ny=b.y+b.vy*dt;b.t-=dt;
  const fromRoof=b.layer!==null&&b.layer!==undefined;
  const groundShot=b.layer===null||b.layer===undefined;
  const enemyShotBlocked=fromRoof?projectileOutOfWorld(ox,oy,nx,ny):projectileHitsWall(ox,oy,nx,ny,null);
  if(enemyShotBlocked){b.x=nx;b.y=ny;b.t=0;sparks.push({x:b.x,y:b.y,vx:(Math.random()-.5)*70,vy:(Math.random()-.5)*70,t:.22});continue}
  b.x=nx;b.y=ny;
  const canHitPlayer=(groundShot&&player.roof===null)||(fromRoof&&(player.roof===b.layer||player.roof===null));
  if(canHitPlayer&&!player.inCar&&!player.dead&&Math.hypot(b.x-player.x,b.y-player.y)<player.r+5){
   damagePlayer(b.damage||8);b.t=0;
   hitMarks.push({x:player.x,y:player.y,t:.18});
  }
 }
 enemyBullets=enemyBullets.filter(b=>b.t>0);
 for(const m of missiles){
  m.t-=dt;
  if(m.t<=0&&!m.exploded){
   m.exploded=true;m.t=.35;
   for(let i=0;i<18;i++)sparks.push({x:m.x,y:m.y,vx:(Math.random()-.5)*260,vy:(Math.random()-.5)*260,t:.5});
   if(!player.dead&&!player.inCar&&player.roof===null&&Math.hypot(player.x-m.x,player.y-m.y)<m.r)killPlayer();
   if(player.inCar&&Math.hypot(car.x-m.x,car.y-m.y)<m.r){car.health=0;car.speed=0;car.nitro=0;player.inCar=false;player.x=car.x+55;player.y=car.y}
   playSound("death");
  }
 }
 missiles=missiles.filter(m=>m.t>0);
 shells.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.vx*=.94;s.vy*=.94;s.t-=dt});shells=shells.filter(s=>s.t>0);
 hitMarks.forEach(h=>h.t-=dt);hitMarks=hitMarks.filter(h=>h.t>0);
}
function update(dt){
 if(!started||paused)return;
 if(bossPhaseIntro>0&&bossIntroBoss?.alive){
  bossPhaseIntro=Math.max(0,bossPhaseIntro-dt);
  flash=Math.max(flash,.45+.35*Math.sin(performance.now()/90));
  const z=getViewZoom(),visibleWorldWidth=canvas.width/z,visibleWorldHeight=canvas.height/(VIEW_TILT*z);
  const tx=bossIntroBoss.x-visibleWorldWidth/2,ty=bossIntroBoss.y-visibleWorldHeight/2;
  cam.x+=(Math.max(0,Math.min(W-visibleWorldWidth,tx))-cam.x)*Math.min(1,dt*4.8);
  cam.y+=(Math.max(0,Math.min(H-visibleWorldHeight,ty))-cam.y)*Math.min(1,dt*4.8);
  if(bossPhaseIntro<=0){
   bossIntroBoss.missileCd=Math.max(.7,bossIntroBoss.missileCd||0);
   bossIntroBoss=null;
   flash=1;
   tone(150,.16,"square",.14,.45);
  }
  return;
 }
 if(player.dead){
  player.respawnT=Math.max(0,player.respawnT-dt);
  flash=Math.max(0,flash-dt*1.4);
  if(player.respawnT<=0)respawnPlayer();
  return;
 }
 player.carHitCd=Math.max(0,player.carHitCd-dt);car.enemyHitCd=Math.max(0,car.enemyHitCd-dt);player.hitT=Math.max(0,player.hitT-dt);player.hitKick=Math.max(0,player.hitKick-dt*34);updateTraffic(dt);updateBushState();updatePickups(dt);flash=Math.max(0,flash-dt*2);player.shootCd=Math.max(0,player.shootCd-dt);
 if(player.reloading){player.reloadT-=dt;if(player.reloadT<=0){const need=player.maxAmmo-player.ammo,take=Math.min(need,player.reserve);player.ammo+=take;player.reserve-=take;player.reloading=false}}
 if(player.inCar){
  if(car.health<=0){
   car.speed=0;car.nitro=0;player.inCar=false;
   const ex=car.x+Math.cos(car.angle+Math.PI/2)*58,ey=car.y+Math.sin(car.angle+Math.PI/2)*58;
   const p=findNearestFreePoint(ex,ey,player.r);player.x=p.x;player.y=p.y;
   playSound("death");
  }
  const throttle=car.health>0?((keys.w||keys.arrowup?1:0)-(keys.s||keys.arrowdown?1:0)-touchMove.y):0;let boost=1;
  if(keys.shift&&car.nitro>0&&throttle>0){boost=1.42;if(car.nitro>96)playSound("nitro");car.nitro=Math.max(0,car.nitro-31*dt)}else car.nitro=Math.min(100,car.nitro+10*dt);
  car.speed+=throttle*car.acc*boost*dt;if(!throttle)car.speed*=Math.pow(.25,dt);car.speed=Math.max(-230,Math.min(car.max*boost,car.speed));
  const steer=(keys.d||keys.arrowright?1:0)-(keys.a||keys.arrowleft?1:0)+touchMove.x;if(Math.abs(car.speed)>8)car.angle+=steer*car.turn*dt*(car.speed/car.max)*(keys[" "]?1.55:1);
  if(keys[" "])car.speed*=Math.pow(.34,dt);
  const ox=car.x,oy=car.y;car.x+=Math.cos(car.angle)*car.speed*dt;car.y+=Math.sin(car.angle)*car.speed*dt;
  if(collides(car.x,car.y,27)){car.x=ox;car.y=oy;car.speed*=-.24;car.health=Math.max(0,car.health-7);if(car.health<=0){car.speed=0;car.nitro=0}flash=.5;for(let i=0;i<10;i++)sparks.push({x:car.x,y:car.y,vx:(Math.random()-.5)*190,vy:(Math.random()-.5)*190,t:.45})}
  if(gameMode==="solo"&&car.enemyHitCd<=0&&Math.abs(car.speed)>85){
   for(const e of enemies){
    if(!e.alive)continue;
    const hitDist=(e.boss?48:34);
    if(Math.hypot(car.x-e.x,car.y-e.y)<hitDist){
     const dmg=e.boss?3:Math.max(3,Math.round(Math.abs(car.speed)/80));
     e.hp-=dmg;
     const push=Math.min(90,Math.abs(car.speed)*.22),dir=Math.atan2(e.y-car.y,e.x-car.x);
     const ex=e.x+Math.cos(dir)*push,ey=e.y+Math.sin(dir)*push;
     if(!collides(ex,e.y,e.r))e.x=ex;if(!collides(e.x,ey,e.r))e.y=ey;
     car.speed*=.58;car.enemyHitCd=.45;
     for(let i=0;i<10;i++)sparks.push({x:e.x,y:e.y,vx:(Math.random()-.5)*170,vy:(Math.random()-.5)*170,t:.35});
     if(e.hp<=0){e.alive=false;if(e.boss){bossDefeated=true;bossSpawned=false;flash=1;playSound("pickup")}reportKill()}
     break;
    }
   }
  }
  if((keys[" "]||Math.abs(steer)>.25)&&Math.abs(car.speed)>125)skids.push({x:car.x-Math.cos(car.angle)*25,y:car.y-Math.sin(car.angle)*25,a:car.angle,t:1});
  player.x=car.x;player.y=car.y;
 }else{
  const dx=(keys.d||keys.arrowright?1:0)-(keys.a||keys.arrowleft?1:0)+touchMove.x,dy=(keys.s||keys.arrowdown?1:0)-(keys.w||keys.arrowup?1:0)+touchMove.y;
  const moving=dx!==0||dy!==0,m=Math.hypot(dx,dy)||1,run=keys.shift?1.55:1;
  tryRoofMovement(dx,dy,dt,run);
  if(moving)player.walk+=dt*(run>1?13:9);
  if(Math.hypot(touchAim.x,touchAim.y)>.12){player.angle=Math.atan2(touchAim.y/VIEW_TILT,touchAim.x);mouse.x=player.x+touchAim.x*200;mouse.y=player.y+touchAim.y*200/VIEW_TILT;}
  else if(!matchMedia("(pointer:coarse)").matches)player.angle=Math.atan2(mouse.y-player.y,mouse.x-player.x);
  if(mouse.down||Math.hypot(touchAim.x,touchAim.y)>.32)shoot();
 }
 ensurePlayerNotStuck();updateBushState();updateBullets(dt);updateEnemies(dt);
 if(gameMode==="solo"&&!bossSpawned&&!bossDefeated&&enemies.filter(e=>e.alive&&!e.boss).length===0)spawnBoss();
 if(!missionDone&&Math.hypot(player.x-mission.x,player.y-mission.y)<70){missionDone=true;flash=1}
 skids.forEach(s=>s.t-=dt*.34);skids=skids.filter(s=>s.t>0);sparks.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.t-=dt});sparks=sparks.filter(s=>s.t>0);damageChunks.forEach(p=>{p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=Math.pow(.055,dt);p.vy*=Math.pow(.055,dt);p.vy+=70*dt;p.rot+=p.spin*dt;p.t-=dt});damageChunks=damageChunks.filter(p=>p.t>0);
 updateEngineSound();
 const z=getViewZoom(),visibleWorldWidth=canvas.width/z,visibleWorldHeight=canvas.height/(VIEW_TILT*z);const tx=player.x-visibleWorldWidth/2,ty=player.y-visibleWorldHeight/2;cam.x+=(Math.max(0,Math.min(W-visibleWorldWidth,tx))-cam.x)*Math.min(1,dt*5.5);cam.y+=(Math.max(0,Math.min(H-visibleWorldHeight,ty))-cam.y)*Math.min(1,dt*5.5);netTimer+=dt;if(netTimer>=.033){netTimer=0;sendNetState()}
}
function road(){
 // Terrain base with subtle deterministic texture.
 ctx.fillStyle="#18251f";ctx.fillRect(0,0,W,H);
 ctx.save();
 for(let y=18;y<H;y+=34){
  for(let x=16;x<W;x+=38){
   const n=((x*13+y*7)%29)/29;
   ctx.fillStyle=n>.58?"rgba(76,111,78,.10)":"rgba(8,20,14,.10)";
   ctx.fillRect(x+((y/34)%2)*8,y,2+n*3,1+n*2);
  }
 }
 ctx.restore();

 const roadsY=[390,900,1400],roadsX=[535,1100,1660,2200];
 const sidewalk="#757c79",curb="#aeb3ad";

 // Sidewalks and curbs make the road blocks feel less flat.
 ctx.fillStyle=sidewalk;
 for(const y of roadsY){ctx.fillRect(0,y-19,W,19);ctx.fillRect(0,y+100,W,19)}
 for(const x of roadsX){ctx.fillRect(x-18,0,18,H);ctx.fillRect(x+90,0,18,H)}
 ctx.strokeStyle=curb;ctx.lineWidth=2;ctx.globalAlpha=.55;
 for(const y of roadsY){ctx.beginPath();ctx.moveTo(0,y-2);ctx.lineTo(W,y-2);ctx.moveTo(0,y+102);ctx.lineTo(W,y+102);ctx.stroke()}
 for(const x of roadsX){ctx.beginPath();ctx.moveTo(x-2,0);ctx.lineTo(x-2,H);ctx.moveTo(x+92,0);ctx.lineTo(x+92,H);ctx.stroke()}
 ctx.globalAlpha=1;

 // Asphalt with layered tonal bands.
 const asphalt=ctx.createLinearGradient(0,390,0,500);
 asphalt.addColorStop(0,"#31393c");asphalt.addColorStop(.48,"#454d50");asphalt.addColorStop(1,"#2d3438");
 ctx.fillStyle=asphalt;for(const y of roadsY)ctx.fillRect(0,y,W,100);
 for(const x of roadsX)ctx.fillRect(x,0,90,H);

 // Fine aggregate texture.
 ctx.save();ctx.globalAlpha=.23;
 for(let i=0;i<760;i++){
  const horizontal=i%2===0;
  const lane=horizontal?roadsY[(i*7)%roadsY.length]:roadsX[(i*11)%roadsX.length];
  const px=horizontal?((i*137)%W):lane+((i*19)%84)+3;
  const py=horizontal?lane+((i*23)%94)+3:((i*149)%H);
  const light=(i%5===0);
  ctx.fillStyle=light?"#889194":"#151a1d";
  ctx.fillRect(px,py,1+(i%3),1);
 }
 ctx.restore();

 // Lane edges and faded center lines.
 ctx.strokeStyle="#20272a";ctx.lineWidth=3;ctx.globalAlpha=.48;
 for(const y of [410,470,920,980,1420,1480]){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(W,y);ctx.stroke()}
 for(const x of [555,605,1120,1170,1680,1730,2220,2270]){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,H);ctx.stroke()}
 ctx.globalAlpha=1;
 ctx.strokeStyle="#d2c76f";ctx.lineWidth=3;ctx.setLineDash([28,24]);ctx.beginPath();
 [440,950,1450].forEach(y=>{ctx.moveTo(0,y);ctx.lineTo(W,y)});
 [580,1145,1705,2245].forEach(x=>{ctx.moveTo(x,0);ctx.lineTo(x,H)});
 ctx.stroke();ctx.setLineDash([]);

 // Crosswalks near a few intersections.
 ctx.fillStyle="rgba(224,226,218,.48)";
 const crossings=[[620,390],[1185,900],[1745,1400],[2200,1018]];
 for(const [cx,cy] of crossings){
  for(let k=-3;k<=3;k++)ctx.fillRect(cx+k*11,cy+7,6,34);
 }

 // Cracks, patched asphalt and old skid marks.
 ctx.strokeStyle="#171d20";ctx.lineWidth=2;ctx.globalAlpha=.74;
 for(let i=0;i<34;i++){
  const x=70+(i*173)%2700,y=roadsY[i%3]+24+((i*19)%50);
  ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+14,y-6);ctx.lineTo(x+25,y+4);ctx.lineTo(x+43,y-2);ctx.stroke();
 }
 ctx.fillStyle="rgba(20,25,27,.28)";
 for(let i=0;i<15;i++){
  const x=120+(i*257)%2550,y=roadsY[i%3]+12+(i*17)%64;
  ctx.beginPath();ctx.ellipse(x,y,20+(i%4)*7,6+(i%3)*3,.18,0,Math.PI*2);ctx.fill();
 }
 ctx.globalAlpha=.28;ctx.strokeStyle="#090c0e";ctx.lineWidth=5;
 for(let i=0;i<12;i++){
  const x=180+(i*241)%2550,y=[417,967,1418][i%3];
  ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+58,y+((i%2)?8:-8));ctx.stroke();
 }
 ctx.globalAlpha=1;

 // Manholes and drain grates.
 for(const [mx,my] of [[760,438],[1470,944],[2440,1445]]){
  ctx.fillStyle="#20272a";ctx.beginPath();ctx.arc(mx,my,12,0,Math.PI*2);ctx.fill();
  ctx.strokeStyle="#586166";ctx.lineWidth=2;ctx.beginPath();ctx.arc(mx,my,8,0,Math.PI*2);ctx.stroke();
  ctx.strokeStyle="#343c40";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(mx-6,my);ctx.lineTo(mx+6,my);ctx.moveTo(mx,my-6);ctx.lineTo(mx,my+6);ctx.stroke();
 }
}
function drawBuildings(){
 buildings.forEach((b,i)=>{
  const height=58+(i%4)*17,roofY=b.y-height,shift=height*.30,rx=b.x+shift,ry=roofY;

  // Deep cast shadow anchors each building to the ground.
  ctx.fillStyle="rgba(0,0,0,.38)";
  ctx.beginPath();ctx.roundRect(b.x+17,b.y+20,b.w+8,b.h+9,8);ctx.fill();

  // Right wall.
  const sideGrad=ctx.createLinearGradient(b.x+b.w,b.y,b.x+b.w+shift,roofY);
  sideGrad.addColorStop(0,"#18242b");sideGrad.addColorStop(1,"#25343c");
  ctx.fillStyle=sideGrad;
  ctx.beginPath();ctx.moveTo(b.x+b.w,b.y);ctx.lineTo(b.x+b.w+shift,roofY);ctx.lineTo(b.x+b.w+shift,b.y+b.h-height);ctx.lineTo(b.x+b.w,b.y+b.h);ctx.closePath();ctx.fill();

  // Front wall.
  const wall=ctx.createLinearGradient(b.x,b.y,b.x,b.y+b.h);
  wall.addColorStop(0,i%2?"#344750":"#2d4049");wall.addColorStop(1,"#1d2a31");
  ctx.fillStyle=wall;
  ctx.beginPath();ctx.moveTo(b.x,b.y+b.h);ctx.lineTo(b.x+shift,roofY+b.h);ctx.lineTo(b.x+b.w+shift,roofY+b.h);ctx.lineTo(b.x+b.w,b.y+b.h);ctx.closePath();ctx.fill();

  // Vertical wall seams / concrete panels.
  ctx.strokeStyle="rgba(9,15,18,.28)";ctx.lineWidth=1;
  for(let x=b.x+28;x<b.x+b.w-20;x+=52){
   ctx.beginPath();ctx.moveTo(x,b.y+b.h-height*.67);ctx.lineTo(x,b.y+b.h-5);ctx.stroke();
  }

  // Windows with frames and occasional warm light.
  for(let x=b.x+32;x<b.x+b.w-22;x+=58){
   const lit=((Math.floor(x/58)+i)%4===0);
   const wy=b.y+b.h-height*.57;
   ctx.fillStyle="#111b21";ctx.fillRect(x-2,wy-2,32,17);
   ctx.fillStyle=lit?"#f7c66c":"#628b9b";ctx.globalAlpha=lit?.82:.58;ctx.fillRect(x,wy,28,13);ctx.globalAlpha=1;
   ctx.strokeStyle="rgba(218,231,235,.28)";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x+14,wy);ctx.lineTo(x+14,wy+13);ctx.stroke();
   if(lit){ctx.fillStyle="rgba(255,197,100,.10)";ctx.fillRect(x-7,wy+15,42,16)}
  }

  // Rooftop slab.
  const roofGrad=ctx.createLinearGradient(rx,ry,rx+b.w,ry+b.h);
  roofGrad.addColorStop(0,i%3===0?"#667982":"#596f79");roofGrad.addColorStop(.55,"#475a63");roofGrad.addColorStop(1,"#33434b");
  ctx.fillStyle=roofGrad;ctx.fillRect(rx,ry,b.w,b.h);
  ctx.strokeStyle="#9eb0b8";ctx.lineWidth=3;ctx.strokeRect(rx,ry,b.w,b.h);

  // Roof membrane seams and weathering.
  ctx.strokeStyle="rgba(20,35,42,.38)";ctx.lineWidth=1;
  for(let xx=rx+24;xx<rx+b.w-15;xx+=48){ctx.beginPath();ctx.moveTo(xx,ry+12);ctx.lineTo(xx,ry+b.h-12);ctx.stroke()}
  for(let yy=ry+28;yy<ry+b.h-15;yy+=44){ctx.beginPath();ctx.moveTo(rx+12,yy);ctx.lineTo(rx+b.w-12,yy);ctx.stroke()}
  ctx.fillStyle="rgba(15,27,32,.13)";
  for(let n=0;n<7;n++){
   const px=rx+18+((n*71+i*19)%(Math.max(20,b.w-45)));
   const py=ry+18+((n*47+i*31)%(Math.max(20,b.h-45)));
   ctx.beginPath();ctx.ellipse(px,py,10+(n%3)*6,4+(n%2)*3,.4,0,Math.PI*2);ctx.fill();
  }

  // Raised parapet.
  ctx.strokeStyle="#253740";ctx.lineWidth=4;ctx.strokeRect(rx+14,ry+14,b.w-28,b.h-28);
  ctx.strokeStyle="rgba(190,207,214,.20)";ctx.lineWidth=1;ctx.strokeRect(rx+16,ry+16,b.w-32,b.h-32);

  // AC units with fan blades.
  for(let n=0;n<2;n++){
   const ax=rx+34+n*78,ay=ry+28+(n%2)*24;
   ctx.fillStyle="#26343c";ctx.fillRect(ax,ay,48,27);
   ctx.fillStyle="rgba(255,255,255,.08)";ctx.fillRect(ax+3,ay+3,42,4);
   ctx.strokeStyle="#81939c";ctx.lineWidth=1;ctx.strokeRect(ax+.5,ay+.5,47,26);
   ctx.fillStyle="#11191e";ctx.beginPath();ctx.arc(ax+24,ay+13.5,8,0,Math.PI*2);ctx.fill();
   ctx.strokeStyle="#596872";
   for(let a=0;a<6;a++){const ang=a*Math.PI/3;ctx.beginPath();ctx.moveTo(ax+24,ay+13.5);ctx.lineTo(ax+24+Math.cos(ang)*7,ay+13.5+Math.sin(ang)*7);ctx.stroke()}
  }

  // Ducts, pipes and a roof access box.
  ctx.fillStyle="#7d8b92";ctx.fillRect(rx+b.w-92,ry+34,58,10);ctx.fillRect(rx+b.w-42,ry+34,10,48);
  ctx.fillStyle="#27343c";ctx.fillRect(rx+b.w-95,ry+31,14,16);
  ctx.fillStyle="#384950";ctx.fillRect(rx+b.w-82,ry+b.h-68,46,35);
  ctx.strokeStyle="#73858e";ctx.strokeRect(rx+b.w-81.5,ry+b.h-67.5,45,34);
  ctx.fillStyle="#11191e";ctx.fillRect(rx+b.w-48,ry+b.h-54,4,4);

  // Warm entrance glow.
  const ex=b.x+b.w*.5,ey=b.y+b.h-5;
  ctx.save();const glow=ctx.createRadialGradient(ex,ey,4,ex,ey,64);
  glow.addColorStop(0,"rgba(255,190,95,.32)");glow.addColorStop(1,"rgba(255,190,95,0)");
  ctx.fillStyle=glow;ctx.beginPath();ctx.arc(ex,ey,64,0,Math.PI*2);ctx.fill();ctx.restore();
 });
}
function drawLadders(){
 for(const l of ladders){
  ctx.save();
  ctx.fillStyle="rgba(126,232,255,.12)";
  ctx.fillRect(l.x-8,l.y-8,l.w+16,l.h+10);
  ctx.strokeStyle="#7ee8ff";ctx.lineWidth=2;ctx.setLineDash([6,5]);
  ctx.strokeRect(l.x-8,l.y-8,l.w+16,l.h+10);ctx.setLineDash([]);
  ctx.fillStyle="#2b3036";
  ctx.fillRect(l.x,l.y-42,5,l.h+44);
  ctx.fillRect(l.x+l.w-5,l.y-42,5,l.h+44);
  ctx.fillStyle="#c4d0d7";
  for(let y=l.y-38;y<l.y+l.h;y+=9)ctx.fillRect(l.x+4,y,l.w-8,3);
  ctx.fillStyle="#7ee8ff";ctx.font="900 9px system-ui";ctx.textAlign="center";
  ctx.fillText("ESCADA",l.x+l.w/2,l.y+l.h+14);ctx.textAlign="left";
  ctx.restore();
 }
}

function drawTrees(){trees.forEach((t,ti)=>{
 ctx.save();
 // Soft offset shadow.
 ctx.fillStyle="rgba(0,0,0,.34)";ctx.beginPath();ctx.ellipse(t.x+20,t.y+13,34,11,-.22,0,Math.PI*2);ctx.fill();

 // Trunk with highlight and branch split.
 const trunk=ctx.createLinearGradient(t.x-7,t.y,t.x+8,t.y);
 trunk.addColorStop(0,"#3c281e");trunk.addColorStop(.55,"#76513a");trunk.addColorStop(1,"#2d2019");
 ctx.fillStyle=trunk;ctx.fillRect(t.x-6,t.y-33,12,40);
 ctx.strokeStyle="#5d3d2b";ctx.lineWidth=5;ctx.beginPath();ctx.moveTo(t.x,t.y-24);ctx.lineTo(t.x-12,t.y-42);ctx.moveTo(t.x+2,t.y-27);ctx.lineTo(t.x+14,t.y-46);ctx.stroke();

 // Layered canopy gives a fuller 2.5D crown.
 const leaves=[
  [-18,-36,18,"#173e2a"],[16,-42,20,"#245b3b"],[-3,-57,22,"#34754a"],
  [4,-34,20,"#2d6841"],[-23,-52,15,"#285f3d"],[20,-58,14,"#3f8252"]
 ];
 for(const [dx,dy,r,col] of leaves){
  ctx.fillStyle=col;ctx.beginPath();ctx.arc(t.x+dx,t.y+dy,r,0,Math.PI*2);ctx.fill();
  const g=ctx.createRadialGradient(t.x+dx-r*.35,t.y+dy-r*.4,1,t.x+dx,t.y+dy,r);
  g.addColorStop(0,"rgba(183,226,172,.22)");g.addColorStop(1,"rgba(0,0,0,0)");
  ctx.fillStyle=g;ctx.beginPath();ctx.arc(t.x+dx,t.y+dy,r,0,Math.PI*2);ctx.fill();
 }
 ctx.restore();
})}
function drawBushes(base=true){for(const b of bushes){
 ctx.save();ctx.globalAlpha=base?.83:.94;
 if(base){ctx.fillStyle="rgba(0,0,0,.20)";ctx.beginPath();ctx.ellipse(b.x+8,b.y+9,b.r*.78,b.r*.34,0,0,Math.PI*2);ctx.fill()}
 const outer=base?"#1f4930":"#2d6840",inner=base?"#2b603b":"#3d8050";
 ctx.fillStyle=outer;
 for(let i=0;i<8;i++){
  const a=i*Math.PI/4,r=b.r*.44,rr=b.r*(.38+(i%3)*.045);
  ctx.beginPath();ctx.arc(b.x+Math.cos(a)*r,b.y+Math.sin(a)*r,rr,0,Math.PI*2);ctx.fill();
 }
 ctx.fillStyle=inner;ctx.beginPath();ctx.arc(b.x,b.y,b.r*.60,0,Math.PI*2);ctx.fill();
 if(!base){
  ctx.fillStyle="rgba(168,223,153,.15)";
  for(let i=0;i<5;i++){const a=i*1.27;ctx.beginPath();ctx.arc(b.x+Math.cos(a)*b.r*.32,b.y+Math.sin(a)*b.r*.32,b.r*.13,0,Math.PI*2);ctx.fill()}
 }
 ctx.restore();
}}
function drawWeaponModel(type,x=0,y=0,scale=1,muzzle=false){
 const w=weapons[type]||weapons.pistol;
 ctx.save();ctx.translate(x,y);ctx.scale(scale,scale);ctx.lineCap="round";ctx.lineJoin="round";
 const longGun=["rifle","shotgun","lmg"].includes(type);
 const metal=ctx.createLinearGradient(-52,-8,48,9);metal.addColorStop(0,"#d1d8dd");metal.addColorStop(.22,"#77848d");metal.addColorStop(.55,"#303a42");metal.addColorStop(1,"#11171c");
 const black=ctx.createLinearGradient(0,-10,0,20);black.addColorStop(0,"#4c5860");black.addColorStop(.45,"#252e34");black.addColorStop(1,"#0c1115");
 const wood=ctx.createLinearGradient(-12,-8,45,12);wood.addColorStop(0,"#a36b44");wood.addColorStop(.5,"#6c422d");wood.addColorStop(1,"#3d261d");
 if(scale>.48){ctx.fillStyle="rgba(0,0,0,.35)";ctx.beginPath();ctx.ellipse(5,15,longGun?45:29,6,0,0,Math.PI*2);ctx.fill()}
 const barrel=(x1,x2,y=0,h=6)=>{ctx.fillStyle=metal;ctx.roundRect(x1,y-h/2,x2-x1,h,h/2);ctx.fill();ctx.fillStyle="rgba(255,255,255,.18)";ctx.fillRect(x1+5,y-h/2+1,Math.max(6,(x2-x1)*.5),1)};
 const grip=(gx,gy)=>{ctx.fillStyle=black;ctx.beginPath();ctx.moveTo(gx,gy);ctx.lineTo(gx+11,gy+1);ctx.lineTo(gx+7,gy+24);ctx.lineTo(gx-5,gy+20);ctx.closePath();ctx.fill();ctx.strokeStyle="#080c0f";ctx.lineWidth=2;ctx.stroke()};
 if(type==="pistol"){
  barrel(-25,23,-4,13);ctx.fillStyle="#151c21";ctx.roundRect(-21,-8,34,4,2);ctx.fill();grip(-1,2);
  ctx.strokeStyle="#0b1013";ctx.lineWidth=3;ctx.beginPath();ctx.arc(1,6,8,.2,Math.PI*.95);ctx.stroke();
 }else if(type==="smg"){
  barrel(-42,27,-2,12);ctx.fillStyle="#1d262c";ctx.roundRect(-35,5,39,8,3);ctx.fill();grip(-3,5);
  ctx.strokeStyle="#71808a";ctx.lineWidth=4;ctx.beginPath();ctx.moveTo(25,-5);ctx.lineTo(47,-13);ctx.lineTo(47,10);ctx.lineTo(26,5);ctx.stroke();
  ctx.fillStyle="#20292f";ctx.roundRect(-15,-17,26,7,3);ctx.fill();
 }else if(type==="shotgun"){
  barrel(-50,48,-4,7);barrel(-47,43,5,5);ctx.fillStyle=wood;ctx.roundRect(-12,4,27,11,5);ctx.fill();
  ctx.beginPath();ctx.moveTo(17,-7);ctx.lineTo(48,-11);ctx.lineTo(52,10);ctx.lineTo(18,7);ctx.closePath();ctx.fill();grip(-4,8);
 }else if(type==="rifle"){
  barrel(-53,49,-3,7);ctx.fillStyle="#27362d";ctx.roundRect(-13,2,38,13,4);ctx.fill();grip(-5,9);
  ctx.fillStyle="#182025";ctx.roundRect(-10,-18,31,7,3);ctx.fill();ctx.strokeStyle="#86949c";ctx.lineWidth=2.5;ctx.beginPath();ctx.arc(2,-14,7,0,Math.PI*2);ctx.stroke();
  ctx.fillStyle="#374b3d";ctx.beginPath();ctx.moveTo(24,1);ctx.lineTo(50,-5);ctx.lineTo(54,9);ctx.lineTo(26,15);ctx.closePath();ctx.fill();
 }else if(type==="lmg"){
  barrel(-55,48,-4,9);ctx.fillStyle=black;ctx.roundRect(-43,-10,70,18,5);ctx.fill();grip(-3,7);
  ctx.fillStyle="#20282e";ctx.beginPath();ctx.arc(4,22,15,0,Math.PI*2);ctx.fill();ctx.strokeStyle="#5d6c75";ctx.lineWidth=3;ctx.stroke();
  ctx.strokeStyle="#788892";ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(-12,8);ctx.lineTo(-23,30);ctx.moveTo(-2,8);ctx.lineTo(8,30);ctx.stroke();
 }else{
  barrel(-42,47,-5,7);barrel(-40,45,5,6);ctx.fillStyle=wood;ctx.roundRect(-10,9,22,9,4);ctx.fill();grip(-5,7);
 }
 const tip=type==="pistol"?27:type==="smg"?50:56;
 ctx.fillStyle="#0b0f12";ctx.fillRect(tip-5,-4,7,8);
 if(muzzle){
  const pulse=.85+Math.sin(performance.now()/28)*.15;
  ctx.save();ctx.translate(tip+2,0);ctx.shadowColor=w.color||"#ffd25a";ctx.shadowBlur=18;
  const g=ctx.createRadialGradient(0,0,1,0,0,18);g.addColorStop(0,"#fff7cf");g.addColorStop(.35,w.color||"#ffd25a");g.addColorStop(1,"rgba(255,120,20,0)");
  ctx.fillStyle=g;ctx.beginPath();ctx.arc(0,0,18*pulse,0,Math.PI*2);ctx.fill();
  ctx.fillStyle="#fff0ad";ctx.beginPath();ctx.moveTo(1,0);ctx.lineTo(20,-6);ctx.lineTo(14,0);ctx.lineTo(20,6);ctx.closePath();ctx.fill();ctx.restore();
 }
 ctx.restore();
}
function drawWeaponPickups(){for(const p of weaponPickups){const w=weapons[p.type];ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.spin*.18);ctx.fillStyle="#061018dd";ctx.beginPath();ctx.arc(0,0,29,0,Math.PI*2);ctx.fill();ctx.strokeStyle=w.color;ctx.lineWidth=2.5;ctx.beginPath();ctx.arc(0,0,25,0,Math.PI*2);ctx.stroke();ctx.rotate(-p.spin*.18);drawWeaponModel(p.type,0,-2,.48,false);ctx.restore();ctx.fillStyle="#eaf4fa";ctx.font="800 9px system-ui";ctx.textAlign="center";ctx.fillText(w.name,p.x,p.y-34);ctx.textAlign="left"}}
function drawVehicle(x,y,a,c,w=62,h=32){
 ctx.save();ctx.translate(x,y);ctx.rotate(a);
 const damaged=c==="#3a3a3a";
 ctx.fillStyle="rgba(0,0,0,.46)";ctx.beginPath();ctx.ellipse(-1,8,w*.56,h*.58,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#090c0f";const tw=w*.15,th=h*.25;
 for(const sx of [-1,1])for(const sy of [-1,1])ctx.roundRect((sx<0?-w*.35:w*.21),(sy<0?-h*.58:h*.34),tw,th,3);ctx.fill();
 const body=ctx.createLinearGradient(-w*.2,-h*.5,w*.18,h*.55);
 body.addColorStop(0,damaged?"#555b5f":"#eef4f6");body.addColorStop(.16,c);body.addColorStop(.64,c);body.addColorStop(1,damaged?"#22272a":"#182229");
 ctx.fillStyle=body;ctx.beginPath();
 ctx.moveTo(-w*.49,-h*.23);ctx.quadraticCurveTo(-w*.45,-h*.46,-w*.24,-h*.49);
 ctx.lineTo(w*.22,-h*.49);ctx.quadraticCurveTo(w*.43,-h*.45,w*.50,-h*.25);
 ctx.lineTo(w*.50,h*.25);ctx.quadraticCurveTo(w*.43,h*.45,w*.22,h*.49);
 ctx.lineTo(-w*.24,h*.49);ctx.quadraticCurveTo(-w*.45,h*.46,-w*.49,h*.23);ctx.closePath();ctx.fill();
 ctx.strokeStyle="rgba(8,12,15,.75)";ctx.lineWidth=1.5;ctx.stroke();
 ctx.fillStyle="rgba(255,255,255,.12)";ctx.roundRect(w*.20,-h*.35,w*.20,h*.70,4);ctx.fill();
 ctx.fillStyle="rgba(0,0,0,.14)";ctx.roundRect(-w*.43,-h*.34,w*.18,h*.68,4);ctx.fill();
 const glass=ctx.createLinearGradient(-w*.18,-h*.32,w*.22,h*.30);glass.addColorStop(0,"#b7dce4");glass.addColorStop(.35,"#648995");glass.addColorStop(1,"#1c3039");
 ctx.fillStyle=glass;ctx.beginPath();
 ctx.moveTo(-w*.16,-h*.35);ctx.lineTo(w*.14,-h*.35);ctx.quadraticCurveTo(w*.26,-h*.31,w*.29,-h*.17);
 ctx.lineTo(w*.29,h*.17);ctx.quadraticCurveTo(w*.26,h*.31,w*.14,h*.35);ctx.lineTo(-w*.16,h*.35);
 ctx.quadraticCurveTo(-w*.24,h*.29,-w*.26,h*.15);ctx.lineTo(-w*.26,-h*.15);ctx.quadraticCurveTo(-w*.24,-h*.29,-w*.16,-h*.35);ctx.closePath();ctx.fill();
 ctx.strokeStyle="#16252c";ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(-w*.23,-h*.27);ctx.lineTo(w*.23,-h*.27);ctx.moveTo(-w*.23,h*.27);ctx.lineTo(w*.23,h*.27);ctx.moveTo(0,-h*.33);ctx.lineTo(0,h*.33);ctx.stroke();
 ctx.fillStyle="#151d22";ctx.roundRect(-w*.08,-h*.59,10,4,2);ctx.roundRect(-w*.08,h*.47,10,4,2);ctx.fill();
 ctx.fillStyle="#10161a";ctx.fillRect(w*.44,-h*.20,5,h*.40);ctx.fillRect(-w*.49,-h*.19,4,h*.38);
 ctx.shadowBlur=10;ctx.shadowColor="#e9fbff";ctx.fillStyle="#ecfbff";ctx.roundRect(w*.39,-h*.31,8,6,2);ctx.roundRect(w*.39,h*.14,8,6,2);ctx.fill();
 ctx.shadowColor="#ff3d48";ctx.fillStyle="#ff414d";ctx.roundRect(-w*.47,-h*.30,6,6,2);ctx.roundRect(-w*.47,h*.13,6,6,2);ctx.fill();ctx.shadowBlur=0;
 ctx.strokeStyle="rgba(255,255,255,.32)";ctx.lineWidth=1.2;ctx.beginPath();ctx.moveTo(-w*.34,-h*.40);ctx.quadraticCurveTo(0,-h*.47,w*.30,-h*.39);ctx.stroke();
 ctx.strokeStyle="rgba(0,0,0,.22)";ctx.beginPath();ctx.moveTo(-w*.34,h*.39);ctx.quadraticCurveTo(0,h*.46,w*.30,h*.38);ctx.stroke();
 ctx.fillStyle="rgba(255,224,160,.11)";ctx.beginPath();ctx.moveTo(w*.48,-h*.20);ctx.lineTo(w*.48+82,-h*.46);ctx.lineTo(w*.48+82,-h*.03);ctx.closePath();ctx.fill();
 ctx.beginPath();ctx.moveTo(w*.48,h*.20);ctx.lineTo(w*.48+82,h*.46);ctx.lineTo(w*.48+82,h*.03);ctx.closePath();ctx.fill();
 if(damaged){ctx.strokeStyle="#16191b";ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(-8,-10);ctx.lineTo(5,-3);ctx.lineTo(-2,5);ctx.moveTo(14,4);ctx.lineTo(25,-4);ctx.stroke()}
 ctx.restore();
}
function drawTopDownCharacter(opts){
 const {
  x,y,angle=0,outfit="#e23b43",skin="#d7b08c",hair="#151a21",
  weapon="pistol",shooting=false,step=0,bob=0,hit=false,
  role="player",showLaser=false
 }=opts;
 ctx.save();ctx.translate(x,y);

 // Layered contact shadow.
 ctx.fillStyle="rgba(0,0,0,.34)";ctx.beginPath();ctx.ellipse(5,17,21,8.5,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="rgba(0,0,0,.16)";ctx.beginPath();ctx.ellipse(8,18,27,11,0,0,Math.PI*2);ctx.fill();
 ctx.rotate(angle);

 const enemy=role==="enemy",sniper=role==="sniper";
 const armor=sniper?"#35483d":enemy?"#333c43":"#25333b";
 const armorHi=sniper?"#536957":enemy?"#4c5961":"#40535d";
 const clothDark=sniper?"#27372f":enemy?"#3c292d":"#222b31";
 const helmet=sniper?"#34463b":enemy?"#30383e":"#222a30";

 // Legs: separated silhouette and walking pose.
 ctx.fillStyle=clothDark;
 ctx.beginPath();ctx.ellipse(-6.5,10+step,6.2,12,0,0,Math.PI*2);ctx.ellipse(7,10-step,6.2,12,0,0,Math.PI*2);ctx.fill();
 ctx.strokeStyle="rgba(255,255,255,.08)";ctx.lineWidth=1;
 ctx.beginPath();ctx.moveTo(-8,3+step);ctx.lineTo(-8,15+step);ctx.moveTo(8,3-step);ctx.lineTo(8,15-step);ctx.stroke();

 // Boots.
 ctx.fillStyle="#090d10";
 ctx.beginPath();ctx.ellipse(-9,18+step,6.8,4.5,.12,0,Math.PI*2);ctx.ellipse(10,18-step,6.8,4.5,-.12,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#333b40";ctx.fillRect(-13,16+step,7,2);ctx.fillRect(7,16-step,7,2);

 // Backpack / radio pack.
 const packColor=sniper?"#4c5c4d":enemy?"#343c42":"#4e5b4b";
 ctx.fillStyle="#12191d";ctx.beginPath();ctx.roundRect(-16,-7+bob,15,28,6);ctx.fill();
 ctx.fillStyle=packColor;ctx.beginPath();ctx.roundRect(-14.5,-5+bob,12,24,5);ctx.fill();
 ctx.strokeStyle="#252f34";ctx.lineWidth=1.2;ctx.strokeRect(-13,-3.5+bob,9,20);
 ctx.fillStyle="#222b30";ctx.fillRect(-11,1+bob,6,3);ctx.fillRect(-11,8+bob,6,3);
 ctx.strokeStyle="#11171a";ctx.beginPath();ctx.moveTo(-4,-3+bob);ctx.lineTo(-1,-12+bob);ctx.stroke();

 // Shoulders create a stronger top-down silhouette.
 ctx.fillStyle=hit?"#ff7d85":outfit;
 ctx.beginPath();ctx.ellipse(-10,-3+bob,8,9,-.25,0,Math.PI*2);ctx.ellipse(10,-3+bob,8,9,.25,0,Math.PI*2);ctx.fill();

 // Torso with directional light.
 const torso=ctx.createLinearGradient(-17,-12,17,18);
 torso.addColorStop(0,hit?"#ff9ca2":outfit);torso.addColorStop(.52,hit?"#ff6d77":outfit);torso.addColorStop(1,"#151f25");
 ctx.fillStyle=torso;ctx.beginPath();ctx.roundRect(-15,-10+bob,30,29,10);ctx.fill();
 ctx.strokeStyle="rgba(0,0,0,.45)";ctx.lineWidth=1.2;ctx.stroke();

 // Tactical vest with pouches and shoulder straps.
 ctx.fillStyle=armor;ctx.beginPath();ctx.roundRect(-11,-6+bob,22,20,5);ctx.fill();
 ctx.strokeStyle=armorHi;ctx.lineWidth=1.1;ctx.strokeRect(-9.5,-4.5+bob,19,16);
 ctx.strokeStyle="#11191d";ctx.lineWidth=2;
 ctx.beginPath();ctx.moveTo(-8,-6+bob);ctx.lineTo(-5,13+bob);ctx.moveTo(8,-6+bob);ctx.lineTo(5,13+bob);ctx.stroke();
 ctx.fillStyle=armorHi;ctx.fillRect(-8,2+bob,6,5);ctx.fillRect(2,2+bob,6,5);
 ctx.fillStyle="#12191d";ctx.fillRect(-1,-4+bob,2,17);

 // Utility belt.
 ctx.fillStyle="#11171b";ctx.fillRect(-13,12+bob,26,4);
 ctx.fillStyle="#56646b";ctx.fillRect(-3,12.5+bob,6,3);

 // Neck and head with rim outline.
 ctx.fillStyle=skin;ctx.fillRect(-3,-13+bob,8,6);
 ctx.fillStyle="#10171b";ctx.beginPath();ctx.ellipse(1,-18+bob,10.7,11.7,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle=skin;ctx.beginPath();ctx.ellipse(1,-18+bob,9.3,10.3,0,0,Math.PI*2);ctx.fill();

 // Hair visible around helmet/cap.
 ctx.fillStyle=hair;ctx.beginPath();ctx.arc(-2,-20+bob,7.8,Math.PI*.9,Math.PI*1.95);ctx.lineTo(6,-18+bob);ctx.closePath();ctx.fill();

 // Helmet / cap and brim.
 ctx.fillStyle=helmet;ctx.beginPath();ctx.ellipse(0,-22+bob,10.7,7.2,0,Math.PI,Math.PI*2);ctx.fill();
 ctx.fillStyle=armorHi;ctx.fillRect(5,-22+bob,10,3);
 ctx.strokeStyle="rgba(255,255,255,.12)";ctx.lineWidth=1;ctx.beginPath();ctx.arc(0,-21+bob,9,Math.PI,Math.PI*1.82);ctx.stroke();

 // Face direction cue.
 ctx.fillStyle="rgba(72,44,34,.55)";ctx.beginPath();ctx.ellipse(8,-17+bob,2.2,1.5,0,0,Math.PI*2);ctx.fill();ctx.fillStyle="rgba(255,255,255,.55)";ctx.beginPath();ctx.arc(8.8,-18+bob,1,0,Math.PI*2);ctx.fill();

 // Headset / earpiece.
 ctx.strokeStyle="#11171b";ctx.lineWidth=2.5;ctx.beginPath();ctx.arc(0,-20+bob,10,Math.PI*.88,Math.PI*1.67);ctx.stroke();
 ctx.fillStyle="#0d1215";ctx.beginPath();ctx.arc(-8,-18+bob,3.5,0,Math.PI*2);ctx.fill();

 // Arms and sleeves, aimed forward.
 ctx.strokeStyle=outfit;ctx.lineWidth=8;ctx.lineCap="round";
 ctx.beginPath();ctx.moveTo(8,-3+bob);ctx.lineTo(19,-8+bob);ctx.stroke();
 ctx.beginPath();ctx.moveTo(8,7+bob);ctx.lineTo(20,9+bob);ctx.stroke();
 ctx.strokeStyle=skin;ctx.lineWidth=5;
 ctx.beginPath();ctx.moveTo(18,-8+bob);ctx.lineTo(28,-3+bob);ctx.stroke();
 ctx.beginPath();ctx.moveTo(19,9+bob);ctx.lineTo(28,4+bob);ctx.stroke();

 // Gloves.
 ctx.fillStyle="#12181c";ctx.beginPath();ctx.arc(28,-3+bob,3.7,0,Math.PI*2);ctx.arc(29,4+bob,3.7,0,Math.PI*2);ctx.fill();

 // Weapon sits above hands for a cleaner combat silhouette.
 drawWeaponModel(weapon,26,bob-.5,sniper?.40:.36,shooting);

 // Small muzzle bloom on the character itself.
 if(shooting){
  ctx.fillStyle="rgba(255,221,111,.28)";ctx.beginPath();ctx.arc(45,bob,10,0,Math.PI*2);ctx.fill();
 }

 if(showLaser){
  ctx.strokeStyle=sniper?"#73ff9b":"#ff5959";ctx.lineWidth=1;ctx.globalAlpha=.52;
  ctx.beginPath();ctx.moveTo(41,0);ctx.lineTo(sniper?116:80,0);ctx.stroke();ctx.globalAlpha=1;
 }
 ctx.restore();
}
function drawPlayer(){
 if(player.inCar||player.dead)return;
 const moving=keys.w||keys.a||keys.s||keys.d||keys.arrowup||keys.arrowdown||keys.arrowleft||keys.arrowright||Math.hypot(touchMove.x,touchMove.y)>.1;
 const bob=moving?Math.sin(player.walk)*1.4:0,step=moving?Math.sin(player.walk)*4.2:0;
 const recoil=player.hitT>0?player.hitKick*(.65+.35*Math.sin(performance.now()/24)):0;
 drawTopDownCharacter({
  x:player.x-Math.cos(player.angle)*recoil,
  y:player.y-Math.sin(player.angle)*recoil,
  angle:player.angle,outfit:characterStyle.outfit,skin:characterStyle.skin,hair:characterStyle.hair,
  weapon:player.weapon,shooting:player.shootCd>.10,step,bob,hit:player.hitT>0,role:"player"
 });
}
function drawRemotePlayers(){
 const now=performance.now();
 for(const [id,p] of remotePlayers){
  if(now-p.seen>6000){remotePlayers.delete(id);continue}
  p.renderX+=(p.x-p.renderX)*.38;p.renderY+=(p.y-p.renderY)*.38;
  const rxp=p.renderX,ryp=p.renderY;
  if(p.inCar){drawVehicle(rxp,ryp,p.angle||0,"#42b9ff",58,30)}
  else{
   drawTopDownCharacter({
    x:rxp,y:ryp,angle:p.angle||0,outfit:"#3f9ee8",skin:"#d7b08c",hair:"#151a21",
    weapon:p.weapon||"pistol",shooting:!!p.shooting,role:"player"
   });
  }
  ctx.save();ctx.font="700 11px system-ui";ctx.textAlign="center";ctx.fillStyle="#dff5ff";ctx.fillText(p.name||"Jogador",rxp,ryp-40);
  const hp=Math.max(0,Math.min(100,Number(p.health??100)));ctx.fillStyle="#111";ctx.fillRect(rxp-18,ryp-33,36,4);ctx.fillStyle="#65ff8b";ctx.fillRect(rxp-18,ryp-33,36*hp/100,4);ctx.restore();
 }
}
function drawTargets(){targets.forEach(t=>{if(t.hp<=0)return;ctx.fillStyle="#0007";ctx.beginPath();ctx.ellipse(t.x,t.y+13,23,10,0,0,Math.PI*2);ctx.fill();ctx.fillStyle=t.hp===3?"#ff725f":t.hp===2?"#ffb24b":"#ffe765";ctx.beginPath();ctx.arc(t.x,t.y,t.r,0,Math.PI*2);ctx.fill();ctx.fillStyle="#341b1b";ctx.fillRect(t.x-5,t.y-11,10,22);ctx.fillRect(t.x-11,t.y-5,22,10)})}
function drawMission(){if(missionDone)return;const p=.5+.5*Math.sin(performance.now()/260);ctx.strokeStyle="rgba(101,255,139,"+(.45+p*.45)+")";ctx.lineWidth=4;ctx.beginPath();ctx.arc(mission.x,mission.y,mission.r+p*8,0,Math.PI*2);ctx.stroke();ctx.fillStyle="#65ff8b22";ctx.beginPath();ctx.arc(mission.x,mission.y,mission.r,0,Math.PI*2);ctx.fill()}
function drawBossPhaseIntro(){
 if(bossPhaseIntro<=0)return;
 const elapsed=bossPhaseIntroTotal-bossPhaseIntro;
 const p=Math.max(0,Math.min(1,elapsed/bossPhaseIntroTotal));
 const pulse=.5+.5*Math.sin(performance.now()/85);
 ctx.save();
 ctx.setTransform(1,0,0,1,0,0);
 ctx.fillStyle="rgba(4,0,3,"+(0.50+0.18*pulse)+")";
 ctx.fillRect(0,0,canvas.width,canvas.height);
 ctx.fillStyle="rgba(255,30,55,"+(0.06+0.10*pulse)+")";
 ctx.fillRect(0,0,canvas.width,canvas.height);
 const barH=Math.max(54,canvas.height*.09);
 ctx.fillStyle="#05070bee";
 ctx.fillRect(0,0,canvas.width,barH);
 ctx.fillRect(0,canvas.height-barH,canvas.width,barH);
 ctx.textAlign="center";
 ctx.shadowColor="#ff2038";ctx.shadowBlur=28;
 ctx.fillStyle="#ff3048";
 ctx.font="900 "+Math.round(Math.min(86,canvas.height*.12))+"px system-ui";
 ctx.fillText("FASE 2",canvas.width/2,canvas.height*.46);
 ctx.shadowBlur=0;
 ctx.fillStyle="#fff";
 ctx.font="900 "+Math.round(Math.min(32,canvas.height*.045))+"px system-ui";
 ctx.fillText("GOLIAS DESPERTOU",canvas.width/2,canvas.height*.54);
 ctx.fillStyle="#ff9aa5";
 ctx.font="800 "+Math.round(Math.min(18,canvas.height*.026))+"px system-ui";
 ctx.fillText("ATAQUE DE MÍSSEIS LIBERADO",canvas.width/2,canvas.height*.59);
 ctx.fillStyle="#2b1117";
 const bw=Math.min(520,canvas.width*.52),bx=(canvas.width-bw)/2,by=canvas.height*.64;
 ctx.fillRect(bx,by,bw,7);
 ctx.fillStyle="#ff3048";
 ctx.fillRect(bx,by,bw*p,7);
 ctx.textAlign="left";
 ctx.restore();
}
function drawCrosshair(){
 if(player.inCar||!started||bossPhaseIntro>0)return;const z=getViewZoom(),x=(mouse.x-cam.x)*z,y=worldToScreenY(mouse.y);ctx.strokeStyle="#ffffffdd";ctx.lineWidth=2;ctx.beginPath();ctx.arc(x,y,9,0,Math.PI*2);ctx.moveTo(x-15,y);ctx.lineTo(x-5,y);ctx.moveTo(x+5,y);ctx.lineTo(x+15,y);ctx.moveTo(x,y-15);ctx.lineTo(x,y-5);ctx.moveTo(x,y+5);ctx.lineTo(x,y+15);ctx.stroke()
}
function hud(){
 ctx.setTransform(1,0,0,1,0,0);ctx.shadowColor="#24d9ff";ctx.shadowBlur=10;ctx.fillStyle="#061018dc";ctx.fillRect(20,20,250,128);ctx.shadowBlur=0;ctx.strokeStyle="#365362";ctx.strokeRect(20.5,20.5,249,127);ctx.fillStyle="#8ea0ad";ctx.font="700 11px system-ui";ctx.fillText(player.inCar?"VEÍCULO":"STATUS",35,43);ctx.fillStyle="#fff";ctx.font="900 25px system-ui";ctx.fillText(player.inCar?Math.round(Math.abs(car.speed)*.22)+" km/h":"A PÉ",35,72);
 ctx.fillStyle="#fff";ctx.font="800 11px system-ui";ctx.fillText("VIDA "+Math.ceil(player.health)+" / "+player.maxHealth,35,94);ctx.fillStyle="#263640";ctx.fillRect(35,102,200,9);ctx.fillStyle=player.health>55?"#65ff8b":player.health>25?"#ffd45c":"#ff626e";ctx.fillRect(35,102,200*(player.health/player.maxHealth),9);
 if(!player.inCar){ctx.fillStyle=player.reloading?"#ffd45c":"#fff";ctx.font="800 12px system-ui";ctx.fillText(player.reloading?"RECARREGANDO...":player.ammo+" / "+player.reserve+"  •  "+weapons[player.weapon].name,35,132);if(player.roof!==null){ctx.fillStyle="#7ee8ff";ctx.font="800 10px system-ui";ctx.fillText("NO TELHADO",150,43)}if(player.hidden){ctx.fillStyle="#71e69a";ctx.font="800 10px system-ui";ctx.fillText("OCULTO NO ARBUSTO",150,43)}}

 const bossTop=getBoss();
 if(bossTop){
  const bw=Math.min(620,canvas.width*.52),bx=(canvas.width-bw)/2,by=18;
  ctx.fillStyle="#071018e8";ctx.fillRect(bx,by,bw,52);ctx.strokeStyle="#263845";ctx.strokeRect(bx+.5,by+.5,bw-1,51);
  ctx.fillStyle="#fff";ctx.font="900 14px system-ui";ctx.fillText("VIDA",bx+14,by+20);
  ctx.textAlign="center";ctx.fillText("GOLIAS  •  FASE "+(bossTop.phase||1),canvas.width/2,by+20);ctx.textAlign="left";
  ctx.fillStyle="#263640";ctx.fillRect(bx+14,by+29,bw-28,11);
  ctx.fillStyle="#ff3045";ctx.fillRect(bx+14,by+29,(bw-28)*(bossTop.hp/bossTop.maxHp),11);
 }

 const rx=canvas.width-248;ctx.shadowColor="#24d9ff";ctx.shadowBlur=10;ctx.fillStyle="#061018dc";ctx.fillRect(rx,20,228,110);ctx.shadowBlur=0;ctx.fillStyle="#fff";ctx.font="800 12px system-ui";ctx.fillText(car.health<=0?"VEÍCULO QUEBRADO":"INTEGRIDADE",rx+16,43);ctx.fillStyle="#263640";ctx.fillRect(rx+16,53,196,9);ctx.fillStyle=car.health>40?"#65ff8b":"#e66";ctx.fillRect(rx+16,53,196*car.health/100,9);ctx.fillStyle="#fff";ctx.fillText("NITRO",rx+16,83);ctx.fillStyle="#263640";ctx.fillRect(rx+16,92,196,9);ctx.fillStyle="#24d9ff";ctx.fillRect(rx+16,92,196*car.nitro/100,9);
 const alive=targets.filter(t=>t.hp>0).length;ctx.fillStyle="#061018dc";ctx.fillRect(20,canvas.height-110,260,90);ctx.fillStyle="#fff";ctx.font="800 12px system-ui";
 if(gameMode==="solo"){
  const boss=getBoss(),normalLeft=enemies.filter(e=>e.alive&&!e.boss).length;
  ctx.fillText("MODO SOLO  •  KILLS "+kills,34,canvas.height-76);
  if(boss){ctx.fillStyle="#ff626e";ctx.fillText("GOLIAS FASE "+(boss.phase||1)+"  "+Math.ceil(boss.hp)+" / "+boss.maxHp,34,canvas.height-52)}
  else if(bossDefeated){ctx.fillStyle="#65ff8b";ctx.fillText("BOSS DERROTADO",34,canvas.height-52)}
  else{ctx.fillStyle="#ff8b8b";ctx.fillText("INIMIGOS RESTANTES  "+normalLeft,34,canvas.height-52)}
 }
 else{ctx.fillText((connectionStatus==="connected"?"ONLINE":"DESCONECTADO")+"  •  SALA "+roomCode.toUpperCase(),34,canvas.height-76);ctx.fillStyle=connectionStatus==="connected"?"#65ff8b":"#ff8b8b";ctx.fillText(connectionStatus==="connected"?"SEUS ABATES  "+kills:"SERVIDOR MULTIPLAYER INDISPONÍVEL",34,canvas.height-52)}
 ctx.fillStyle="#9fb0bd";ctx.fillText("ALVOS RESTANTES  "+alive,34,canvas.height-28);
 if(gameMode==="multi"){
  const rows=[{name:playerName,kills},...Array.from(ranking.values())].sort((a,b)=>b.kills-a.kills).slice(0,5);
  const rw=210,rh=28+rows.length*22,rx2=canvas.width-rw-20,ry2=150;ctx.fillStyle="#061018dc";ctx.fillRect(rx2,ry2,rw,rh);ctx.fillStyle="#fff";ctx.font="900 12px system-ui";ctx.fillText("RANK DE ABATES",rx2+14,ry2+20);
  rows.forEach((p,i)=>{ctx.fillStyle=i===0?"#ffd45c":"#dce7ee";ctx.font="700 11px system-ui";ctx.fillText((i+1)+". "+p.name,rx2+14,ry2+43+i*22);ctx.textAlign="right";ctx.fillText(String(p.kills),rx2+rw-14,ry2+43+i*22);ctx.textAlign="left"});
 }
 const mw=190,mh=120,mx=canvas.width-210,my=canvas.height-140;ctx.fillStyle="#061018e8";ctx.fillRect(mx,my,mw,mh);ctx.fillStyle="#344048";buildings.forEach(b=>ctx.fillRect(mx+b.x/W*mw,my+b.y/H*mh,b.w/W*mw,b.h/H*mh));if(!missionDone){ctx.fillStyle="#ffd65b";ctx.beginPath();ctx.arc(mx+mission.x/W*mw,my+mission.y/H*mh,4,0,Math.PI*2);ctx.fill()}ctx.fillStyle="#65ff8b";ctx.beginPath();ctx.arc(mx+player.x/W*mw,my+player.y/H*mh,4.5,0,Math.PI*2);ctx.fill();
 if(gameMode==="solo"){
  for(const e of enemies){if(!e.alive)continue;ctx.fillStyle=e.boss?"#ff2d3f":"#ff8b8b";ctx.beginPath();ctx.arc(mx+e.x/W*mw,my+e.y/H*mh,e.boss?5:3,0,Math.PI*2);ctx.fill()}
 }
 const ladderNear=player.roof===null&&ladders.find(l=>Math.abs(player.x-(l.x+l.w/2))<=48&&player.y>=l.y-4&&player.y<=l.y+l.h+28);
 if(ladderNear){ctx.fillStyle="#081119e8";ctx.fillRect(canvas.width/2-120,canvas.height-142,240,36);ctx.fillStyle="#7ee8ff";ctx.font="900 12px system-ui";ctx.fillText("SUBA PELA ESCADA",canvas.width/2-78,canvas.height-118)}
  const near=!player.inCar&&car.health>0&&Math.hypot(player.x-car.x,player.y-car.y)<82;if(near){ctx.fillStyle="#081119e8";ctx.fillRect(canvas.width/2-105,canvas.height-93,210,38);ctx.fillStyle="#dfffe6";ctx.font="900 13px system-ui";ctx.fillText("E  ENTRAR NO VEÍCULO",canvas.width/2-83,canvas.height-68)}
 if(player.dead){ctx.fillStyle="#140307b8";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="900 46px system-ui";ctx.fillText("VOCÊ FOI DERRUBADO",canvas.width/2,canvas.height/2-12);ctx.fillStyle="#ff9ba3";ctx.font="800 20px system-ui";ctx.fillText("Renasce em "+Math.max(1,Math.ceil(player.respawnT))+"...",canvas.width/2,canvas.height/2+28);ctx.textAlign="left"}
 if(paused){ctx.fillStyle="#030609aa";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="900 44px system-ui";ctx.fillText("PAUSADO",canvas.width/2,canvas.height/2);ctx.textAlign="left"}
 if(flash>0){ctx.fillStyle="rgba(255,90,90,"+Math.min(.28,flash*.2)+")";ctx.fillRect(0,0,canvas.width,canvas.height)}
 drawBossPhaseIntro();
 drawCrosshair()
}
function drawWorldLighting(){
 ctx.save();ctx.globalCompositeOperation="screen";
 for(let i=0;i<buildings.length;i++){const b=buildings[i],x=b.x+b.w*.5,y=b.y+b.h-2;const g=ctx.createRadialGradient(x,y,3,x,y,75);g.addColorStop(0,"rgba(255,190,95,.22)");g.addColorStop(1,"rgba(255,190,95,0)");ctx.fillStyle=g;ctx.beginPath();ctx.arc(x,y,75,0,Math.PI*2);ctx.fill()}
 for(const t of trees){const g=ctx.createRadialGradient(t.x-8,t.y-58,2,t.x-8,t.y-58,30);g.addColorStop(0,"rgba(111,211,148,.07)");g.addColorStop(1,"rgba(111,211,148,0)");ctx.fillStyle=g;ctx.beginPath();ctx.arc(t.x-8,t.y-58,30,0,Math.PI*2);ctx.fill()}
 ctx.restore();
}
function render(){
 ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,canvas.width,canvas.height);ctx.save();const z=getViewZoom();ctx.translate(0,canvas.height*(1-VIEW_TILT)/2);ctx.scale(z,z*VIEW_TILT);ctx.translate(-cam.x,-cam.y);
 road();drawBuildings();drawLadders();drawTrees();drawBushes(true);drawWeaponPickups();drawMission();drawTargets();drawEnemies();
 for(const s of skids){ctx.globalAlpha=Math.max(0,s.t*.4);ctx.save();ctx.translate(s.x,s.y);ctx.rotate(s.a);ctx.fillStyle="#090a0b";ctx.fillRect(-18,-12,36,3);ctx.fillRect(-18,9,36,3);ctx.restore()}ctx.globalAlpha=1;
 traffic.forEach(t=>drawVehicle(t.x,t.y,t.a,t.c,54,27));drawVehicle(car.x,car.y,car.angle,car.health<=0?"#3a3a3a":car.health>40?"#65ff8b":"#d86770");drawWorldLighting();if(car.health<=0){ctx.fillStyle="#111";ctx.beginPath();ctx.arc(car.x+8,car.y-20,13,0,Math.PI*2);ctx.fill();ctx.fillStyle="#333";ctx.beginPath();ctx.arc(car.x+16,car.y-34,9,0,Math.PI*2);ctx.fill()}drawPlayer();drawRemotePlayers();drawBushes(false);
 bullets.forEach(b=>{const a=Math.atan2(b.vy,b.vx);ctx.save();ctx.translate(b.x,b.y);ctx.rotate(a);const col=b.color||"#ffe36e";ctx.shadowColor=col;ctx.shadowBlur=10;ctx.strokeStyle=col;ctx.lineWidth=4;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(-14,0);ctx.lineTo(4,0);ctx.stroke();ctx.shadowBlur=0;ctx.fillStyle="#fff8d2";ctx.beginPath();ctx.arc(5,0,2.4,0,Math.PI*2);ctx.fill();ctx.restore()});
 remoteBullets.forEach(b=>{const a=Math.atan2(b.vy,b.vx);ctx.save();ctx.translate(b.x,b.y);ctx.rotate(a);ctx.shadowColor=b.color||"#7ee8ff";ctx.shadowBlur=12;ctx.strokeStyle=b.color||"#7ee8ff";ctx.lineWidth=6;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(-18,0);ctx.lineTo(7,0);ctx.stroke();ctx.shadowBlur=0;ctx.fillStyle="#fff";ctx.beginPath();ctx.arc(8,0,3,0,Math.PI*2);ctx.fill();ctx.restore()});
 missiles.forEach(m=>{
  ctx.save();
  const p=Math.max(0,Math.min(1,m.t/(m.total||1.65)));
  if(!m.exploded){
   ctx.strokeStyle="#ff3045";ctx.lineWidth=3;ctx.setLineDash([8,6]);ctx.beginPath();ctx.arc(m.x,m.y,m.r,0,Math.PI*2);ctx.stroke();ctx.setLineDash([]);
   ctx.fillStyle="rgba(255,48,69,"+(0.10+0.18*(1-p))+")";ctx.beginPath();ctx.arc(m.x,m.y,m.r,0,Math.PI*2);ctx.fill();

   const travel=1-p;
   const mx=(m.startX??m.x)+(m.x-(m.startX??m.x))*travel;
   const my=(m.startY??m.y)+(m.y-(m.startY??m.y))*travel;
   const ang=Math.atan2(m.y-(m.startY??m.y),m.x-(m.startX??m.x));
   const shadowScale=.45+.55*travel;
   ctx.fillStyle="rgba(0,0,0,"+(0.18+0.32*travel)+")";ctx.beginPath();ctx.ellipse(m.x,m.y+6,18*shadowScale,8*shadowScale,0,0,Math.PI*2);ctx.fill();

   for(let i=0;i<4;i++){
    const back=18+i*10;
    const sx=mx-Math.cos(ang)*back+(Math.random()-.5)*5;
    const sy=my-Math.sin(ang)*back+(Math.random()-.5)*5;
    ctx.fillStyle="rgba(180,190,198,"+(0.18-i*.025)+")";
    ctx.beginPath();ctx.arc(sx,sy,7+i*2,0,Math.PI*2);ctx.fill();
   }

   ctx.save();ctx.translate(mx,my);ctx.rotate(ang);
   ctx.fillStyle="#2a2f35";ctx.fillRect(-18,-5,30,10);
   ctx.fillStyle="#6f7780";ctx.fillRect(-8,-7,18,14);
   ctx.fillStyle="#d9dee3";ctx.beginPath();ctx.moveTo(13,0);ctx.lineTo(3,-8);ctx.lineTo(3,8);ctx.closePath();ctx.fill();
   ctx.fillStyle="#ff8a2a";ctx.shadowColor="#ff5a1f";ctx.shadowBlur=12;ctx.beginPath();ctx.moveTo(-19,0);ctx.lineTo(-31,-7);ctx.lineTo(-31,7);ctx.closePath();ctx.fill();ctx.shadowBlur=0;
   ctx.restore();

   ctx.fillStyle="#fff";ctx.font="900 10px system-ui";ctx.textAlign="center";ctx.fillText("MÍSSIL",m.x,m.y+3);ctx.textAlign="left";
  }else{
   ctx.fillStyle="rgba(255,92,28,"+(m.t/.35)+")";ctx.beginPath();ctx.arc(m.x,m.y,m.r*(1.2-m.t/.7),0,Math.PI*2);ctx.fill();
  }
  ctx.restore();
 });
 enemyBullets.forEach(b=>{
  const a=Math.atan2(b.vy,b.vx);
  ctx.save();ctx.translate(b.x,b.y);ctx.rotate(a);
  ctx.strokeStyle=b.phase2?"#ffcf33":b.boss?"#ff00aa":"#ff3b3b";ctx.lineWidth=b.phase2?7:b.boss?6:4;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(b.phase2?-20:-14,0);ctx.lineTo(4,0);ctx.stroke();
  ctx.fillStyle="#fff3a3";ctx.beginPath();ctx.arc(5,0,4.5,0,Math.PI*2);ctx.fill();
  ctx.shadowColor="#ff3b3b";ctx.shadowBlur=12;ctx.fillStyle="#ff6565";ctx.beginPath();ctx.arc(5,0,3,0,Math.PI*2);ctx.fill();ctx.restore();
 });
 ctx.fillStyle="#d9b761";shells.forEach(s=>ctx.fillRect(s.x,s.y,3,2));
 sparks.forEach(s=>{ctx.fillStyle="#ffd76b";ctx.fillRect(s.x,s.y,3,3)});damageChunks.forEach(p=>{ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.rot);ctx.globalAlpha=Math.max(0,Math.min(1,p.t/(p.maxT||.7)));ctx.fillStyle=p.dark?"#6b171d":"#c92f39";ctx.fillRect(-p.r,-p.r*.55,p.r*2,p.r*1.1);ctx.restore()});ctx.globalAlpha=1;hitMarks.forEach(h=>{ctx.save();ctx.globalAlpha=Math.max(.15,Math.min(1,h.t/.25));ctx.strokeStyle="#fff";ctx.lineWidth=2;ctx.shadowColor="#ff4d5a";ctx.shadowBlur=8;ctx.beginPath();ctx.moveTo(h.x-9,h.y-9);ctx.lineTo(h.x-3,h.y-3);ctx.moveTo(h.x+9,h.y-9);ctx.lineTo(h.x+3,h.y-3);ctx.moveTo(h.x-9,h.y+9);ctx.lineTo(h.x-3,h.y+3);ctx.moveTo(h.x+9,h.y+9);ctx.lineTo(h.x+3,h.y+3);ctx.stroke();ctx.restore()});
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
 el.addEventListener("pointercancel",e=>{if(e.pointerId===active)reset()});
 el.addEventListener("lostpointercapture",e=>{if(e.pointerId===active)reset()});
}
bindJoystick("moveStick",touchMove);bindJoystick("aimStick",touchAim);
addEventListener("blur",()=>{touchMove.x=touchMove.y=touchAim.x=touchAim.y=0;mouse.down=false;for(const k of Object.keys(keys))keys[k]=false});
document.querySelector('[data-action="reload"]')?.addEventListener("click",startReload);
