const canvas=document.getElementById("gameCanvas"),ctx=canvas.getContext("2d"),W=4000,H=2800;
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

// Diamond isometric projection: both world axes slope at the same angle.
// Simulation, networking and collisions keep their original XY coordinates.
const VIEW_TILT=.42,VIEW_SKEW=-1;
const ISO={a:.84,b:VIEW_TILT,c:-.84,d:VIEW_TILT};
const ISO_DET=ISO.a*ISO.d-ISO.b*ISO.c;
function projectVector(x,y){return {x:ISO.a*x+ISO.c*y,y:ISO.b*x+ISO.d*y}}
function unprojectVector(x,y){return {x:(ISO.d*x-ISO.c*y)/ISO_DET,y:(ISO.a*y-ISO.b*x)/ISO_DET}}
function undoProjection(c){c.transform(ISO.d/ISO_DET,-ISO.b/ISO_DET,-ISO.c/ISO_DET,ISO.a/ISO_DET,0,0)}
function projectedAngle(a){const v=projectVector(Math.cos(a),Math.sin(a));return Math.atan2(v.y,v.x)}
window.gameProjection={projectVector,unprojectVector,undo:undoProjection,angle:projectedAngle};
function getViewZoom(){return player.weapon==="rifle"?.78:1}
function viewOffsetY(){return canvas.height*.53}
function viewOffsetX(){return canvas.width*.5}
function screenToWorldPoint(sx,sy){
 const z=getViewZoom(),v=unprojectVector((sx-viewOffsetX())/z,(sy-viewOffsetY())/z);
 return {x:cam.x+v.x,y:cam.y+v.y};
}
function screenToWorldY(y){return screenToWorldPoint(viewOffsetX(),y).y}
function worldToScreenX(x,y){return viewOffsetX()+getViewZoom()*projectVector(x-cam.x,y-cam.y).x}
function worldToScreenY(y,x=player.x){return viewOffsetY()+getViewZoom()*projectVector(x-cam.x,y-cam.y).y}
function followCamera(x,y,dt,speed=5.5,height=0){const v=unprojectVector(0,-height),t=Math.min(1,dt*speed);cam.x+=(x+v.x-cam.x)*t;cam.y+=(y+v.y-cam.y)*t}
function buildingHeight(index){return index===null||index===undefined?0:100+(index%4)*16}
function elevated(index,draw){const h=buildingHeight(index),v=unprojectVector(0,-h);ctx.save();ctx.translate(v.x,v.y);draw();ctx.restore()}
function insidePolygon(x,y,points){
 let inside=false;
 for(let i=0,j=points.length-1;i<points.length;j=i++){
  const a=points[i],b=points[j];
  if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])inside=!inside;
 }
 return inside;
}
function screenAlignedInput(x,y){const v=unprojectVector(x,y),n=Math.hypot(v.x,v.y)||1,m=Math.min(1,Math.hypot(x,y));return {x:v.x/n*m,y:v.y/n*m}}
const keys={},cam={x:480,y:440},mouse={x:0,y:0,down:false,screenX:null,screenY:null,layer:null};
const player={x:480,y:440,r:16,speed:190,inCar:false,angle:0,walk:0,ammo:12,reserve:72,maxAmmo:12,reloading:false,reloadT:0,shootCd:0,health:100,maxHealth:100,weapon:"pistol",carHitCd:0,hidden:false,dead:false,respawnT:0,roof:null,hitT:0,hitKick:0};
const characterStyle=(()=>{try{return {...{outfit:"#303746",visual:"tactical",skin:"#d7b08c",hair:"#151a21"},...JSON.parse(localStorage.getItem("streetCharacter")||"{}")}}catch(_){return {outfit:"#303746",visual:"tactical",skin:"#d7b08c",hair:"#151a21"}}})();
addEventListener("characterchange",e=>Object.assign(characterStyle,e.detail));
function tacticalPlayerEnabled(){return characterStyle.visual!=="custom"&&window.playerArt?.ready}
function updatePointerAim(sx,sy){
 mouse.screenX=sx;mouse.screenY=sy;mouse.layer=null;
 let p=screenToWorldPoint(sx,sy);
 if(player.roof!==null){
  const onRoof=screenToWorldPoint(sx,sy+buildingHeight(player.roof)*getViewZoom());
  if(pointInBuilding(onRoof.x,onRoof.y,buildings[player.roof])){p=onRoof;mouse.layer=player.roof}
 }
 mouse.x=p.x;mouse.y=p.y;
}
function projectileVisualPoint(b){
 const sourceHeight=buildingHeight(b.layer);
 if(!sourceHeight)return {x:b.x,y:b.y};
 const distance=Math.hypot(b.x-b.visualX,b.y-b.visualY),t=Math.min(1,distance/(b.visualRange||300));
 const height=sourceHeight+(buildingHeight(b.targetLayer)-sourceHeight)*t,v=unprojectVector(0,-height);
 return {x:b.x+v.x,y:b.y+v.y};
}
function playerGunPose(){
 const p=window.playerArt.pose(player.angle);
 const offset=unprojectVector(p.x,p.y),wx=offset.x,wy=offset.y;
 const x=player.x+wx,y=player.y+wy;
 const angle=Math.atan2(mouse.y-y,mouse.x-x);
 const delta=projectVector(mouse.x-x,mouse.y-y);
 const screenAngle=Math.atan2(delta.y+buildingHeight(player.roof)-buildingHeight(mouse.layer),delta.x);
 return {x,y,angle,screenAngle};
}
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
let bossDeathIntro=0,bossDeathIntroTotal=4.8,bossDeathScene=null;

let audioCtx=null,audioMaster=null,soundEnabled=localStorage.getItem("streetSound")!=="off";
let engineOsc=null,engineOsc2=null,engineGain=null,engineFilter=null,stepPhase=0,ambientTimer=0;
function ensureAudio(){
 if(!soundEnabled)return null;
 if(!audioCtx){
  audioCtx=new (window.AudioContext||window.webkitAudioContext)();
  audioMaster=audioCtx.createGain();
  const comp=audioCtx.createDynamicsCompressor();
  comp.threshold.value=-10;comp.knee.value=12;comp.ratio.value=4;comp.attack.value=.003;comp.release.value=.18;
  audioMaster.gain.value=.48;audioMaster.connect(comp);comp.connect(audioCtx.destination);
 }
 if(audioCtx.state==="suspended")audioCtx.resume().catch(()=>{});
 return audioCtx;
}
function spatialNodes(x=null,y=null,vol=1){
 const ac=ensureAudio();if(!ac)return null;
 const gain=ac.createGain(),pan=ac.createStereoPanner?ac.createStereoPanner():null;
 let distance=0,p=0;
 if(Number.isFinite(x)&&Number.isFinite(y)){
  distance=Math.hypot(x-player.x,y-player.y);
  const max=1150;vol*=Math.max(.045,1-distance/max);
  p=Math.max(-.82,Math.min(.82,(x-player.x)/650));
 }
 gain.gain.value=Math.max(.0001,vol);
 if(pan){pan.pan.value=p;gain.connect(pan);pan.connect(audioMaster)}else gain.connect(audioMaster);
 return {ac,gain,pan,distance};
}
function tone(freq=440,dur=.08,type="square",vol=.18,slide=1,x=null,y=null,delay=0){
 const n=spatialNodes(x,y,vol);if(!n)return;
 const {ac,gain}=n,o=ac.createOscillator(),t=ac.currentTime+delay;
 o.type=type;o.frequency.setValueAtTime(Math.max(30,freq),t);
 o.frequency.exponentialRampToValueAtTime(Math.max(30,freq*slide),t+dur);
 gain.gain.setValueAtTime(Math.max(.0001,gain.gain.value),t);
 gain.gain.exponentialRampToValueAtTime(.0001,t+dur);
 o.connect(gain);o.start(t);o.stop(t+dur+.025);
}
function noise(dur=.08,vol=.12,filterFreq=1600,x=null,y=null,filterType="lowpass",delay=0){
 const n=spatialNodes(x,y,vol);if(!n)return;
 const {ac,gain}=n,len=Math.max(1,Math.floor(ac.sampleRate*dur)),buf=ac.createBuffer(1,len,ac.sampleRate),data=buf.getChannelData(0);
 for(let i=0;i<len;i++)data[i]=(Math.random()*2-1)*(1-i/len*.28);
 const src=ac.createBufferSource(),f=ac.createBiquadFilter(),t=ac.currentTime+delay;
 src.buffer=buf;f.type=filterType;f.frequency.value=filterFreq;f.Q.value=.65;
 gain.gain.setValueAtTime(Math.max(.0001,gain.gain.value),t);gain.gain.exponentialRampToValueAtTime(.0001,t+dur);
 src.connect(f);f.connect(gain);src.start(t);src.stop(t+dur+.02);
}
function gunshot(kind,x=null,y=null,scale=1){
 const v=.82+Math.random()*.18,pitch=.94+Math.random()*.12;
 const cfg={
  pistol:[2450,.10,.14,122,.12],
  smg:[3150,.065,.10,155,.07],
  shotgun:[1450,.20,.22,78,.22],
  rifle:[3900,.11,.16,108,.14],
  lmg:[2600,.075,.14,118,.085],
  sawedoff:[1200,.24,.25,66,.26]
 }[kind]||[2400,.08,.12,120,.1];
 noise(cfg[1],cfg[2]*v*scale,cfg[0],x,y,"lowpass");
 noise(cfg[1]*.45,cfg[2]*.55*v*scale,6200,x,y,"highpass");
 tone(cfg[3]*pitch,cfg[4],kind==="rifle"?"triangle":"sawtooth",cfg[2]*.44*v*scale,.42,x,y);
 tone((kind==="shotgun"||kind==="sawedoff")?52:72,cfg[4]*1.35,"sine",cfg[2]*.36*v*scale,.72,x,y,.012);
 // short reflection gives outdoor shots more body without audio files
 noise(cfg[1]*.8,cfg[2]*.18*v*scale,1100,x,y,"lowpass",.055+Math.random()*.035);
}
function playSound(name,opts={}){
 if(!soundEnabled)return;
 const x=opts.x??null,y=opts.y??null,s=opts.vol??1;
 switch(name){
  case "pistol":case "smg":case "shotgun":case "rifle":case "lmg":case "sawedoff":gunshot(name,x,y,s);break;
  case "reload":
   noise(.025,.035*s,5200,x,y,"highpass");tone(720,.025,"triangle",.05*s,.72,x,y,.025);tone(410,.045,"triangle",.055*s,.82,x,y,.19);break;
  case "damage": noise(.10,.09*s,780,x,y);tone(68,.15,"sawtooth",.08*s,.62,x,y);break;
  case "death": tone(105,.42,"sawtooth",.13*s,.24,x,y);noise(.18,.055*s,520,x,y);break;
  case "pickup": tone(520,.07,"sine",.07*s,1.25,x,y);tone(760,.09,"sine",.055*s,1.12,x,y,.07);break;
  case "car": tone(92,.10,"triangle",.07*s,.82,x,y);noise(.045,.025*s,1300,x,y);break;
  case "nitro": noise(.20,.075*s,1450,x,y);tone(125,.22,"sawtooth",.045*s,1.65,x,y);break;
  case "step": noise(.035,.026*s,850,x,y);tone(82,.025,"sine",.018*s,.7,x,y);break;
  case "stepRoof": noise(.03,.023*s,2100,x,y,"bandpass");tone(145,.025,"triangle",.015*s,.82,x,y);break;
  case "impact": noise(.045,.045*s,2800,x,y,"bandpass");tone(115,.045,"triangle",.03*s,.65,x,y);break;
  case "missileLaunch": noise(.38,.065*s,900,x,y);tone(95,.42,"sawtooth",.055*s,1.7,x,y);break;
  case "missileIncoming": tone(760,.17,"sine",.035*s,1.45,x,y);break;
  case "explosion":
   noise(.34,.30*s,1050,x,y);noise(.16,.13*s,4200,x,y,"highpass");
   tone(58,.38,"sine",.22*s,.42,x,y);tone(92,.22,"sawtooth",.10*s,.34,x,y,.018);break;
  case "skid": noise(.12,.035*s,3900,x,y,"bandpass");break;
 }
}
function updateFootsteps(moving,run,dt){
 if(!moving||player.inCar||player.dead){stepPhase=0;return}
 stepPhase+=dt;
 const interval=run>1?.27:.39;
 if(stepPhase>=interval){
  stepPhase%=interval;
  playSound(player.roof!==null?"stepRoof":"step",{x:player.x,y:player.y,vol:run>1?1.35:1});
 }
}
function updateAmbientSound(dt){
 if(!started||paused||player.dead)return;
 ambientTimer-=dt;if(ambientTimer>0)return;
 ambientTimer=3.5+Math.random()*5.5;
 const a=Math.random()*Math.PI*2,d=520+Math.random()*520,x=player.x+Math.cos(a)*d,y=player.y+Math.sin(a)*d;
 if(Math.random()<.55)noise(.35,.018,700,x,y);else tone(170+Math.random()*70,.45,"sine",.009,.92,x,y);
}
function updateEngineSound(){
 if(!soundEnabled||!player.inCar||paused||player.dead||car.health<=0){
  if(engineGain&&audioCtx)engineGain.gain.setTargetAtTime(.0001,audioCtx.currentTime,.06);
  return;
 }
 const ac=ensureAudio();if(!ac)return;
 if(!engineOsc){
  engineOsc=ac.createOscillator();engineOsc2=ac.createOscillator();engineGain=ac.createGain();engineFilter=ac.createBiquadFilter();
  engineOsc.type="sawtooth";engineOsc2.type="triangle";engineFilter.type="lowpass";engineFilter.Q.value=.75;engineGain.gain.value=.0001;
  engineOsc.connect(engineFilter);engineOsc2.connect(engineFilter);engineFilter.connect(engineGain);engineGain.connect(audioMaster);
  engineOsc.start();engineOsc2.start();
 }
 const speed=Math.abs(car.speed),throttle=(keys.w||keys.arrowup||touchMove.y<-.18)?1:0;
 const rpm=Math.min(1,speed/Math.max(1,car.max)),base=43+rpm*92+throttle*14;
 engineOsc.frequency.setTargetAtTime(base,ac.currentTime,.055);
 engineOsc2.frequency.setTargetAtTime(base*2.03,ac.currentTime,.055);
 engineFilter.frequency.setTargetAtTime(500+rpm*1800+throttle*500,ac.currentTime,.08);
 engineGain.gain.setTargetAtTime(.028+rpm*.058+throttle*.018,ac.currentTime,.07);
 if((keys[" "]||Math.abs(touchMove.x)>.75)&&speed>150&&Math.random()<.08)playSound("skid",{x:car.x,y:car.y});
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

// Shared street geometry keeps asphalt, crossings, foliage and minimap aligned.
const streets={horizontal:[440,950,1450,2050,2520],vertical:[580,1145,1705,2245,2900,3500],width:160,sidewalk:24};
function inStreet(x,y,padding=0){
 const half=streets.width/2+padding;
 return streets.horizontal.some(c=>Math.abs(y-c)<half)||streets.vertical.some(c=>Math.abs(x-c)<half);
}
const remotePlayers=new Map();
const ranking=new Map();
const enemies=[];
const mission={x:3650,y:2380,r:48};
const buildings=[
{x:80,y:70,w:360,h:240},{x:700,y:70,w:300,h:250},{x:1280,y:60,w:300,h:270},{x:1840,y:80,w:270,h:235},{x:2380,y:70,w:320,h:250},
{x:80,y:570,w:350,h:250},{x:710,y:570,w:300,h:240},{x:1270,y:570,w:300,h:250},{x:1840,y:570,w:270,h:245},{x:2380,y:570,w:320,h:250},
{x:80,y:1070,w:350,h:230},{x:710,y:1070,w:300,h:230},{x:1270,y:1070,w:300,h:230},{x:1840,y:1070,w:270,h:230},{x:2380,y:1070,w:320,h:230},
{x:80,y:1580,w:350,h:230},{x:710,y:1580,w:300,h:230},{x:1270,y:1580,w:300,h:230},
{x:80,y:2180,w:350,h:230},{x:710,y:2180,w:300,h:230},{x:1270,y:2180,w:300,h:230},{x:1840,y:2180,w:270,h:230},
{x:2380,y:120,w:330,h:260},{x:2380,y:570,w:330,h:250},{x:2380,y:1070,w:330,h:230},
{x:3020,y:120,w:310,h:260},{x:3020,y:570,w:310,h:250},{x:3020,y:1070,w:310,h:230}];

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
 const magnitude=Math.hypot(dx,dy);
  const step=player.speed*run*dt*Math.min(1,magnitude);
  const vx=magnitude?dx/magnitude*step:0,vy=magnitude?dy/magnitude*step:0;

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
  const inLadderX=Math.abs(player.x-ladderCenter)<=Math.max(16,l.w*.6);
  const inLadderY=player.y>=b.y+b.h+player.r&&player.y<=b.y+b.h+player.r+20;
  if(inLadderX&&inLadderY&&dy<-.35){
   player.roof=i;
   player.x=ladderCenter;
   player.y=b.y+b.h-34;
   playSound("pickup");
   return;
  }
 }

 const segments=Math.max(1,Math.ceil(Math.hypot(vx,vy)/Math.max(4,player.r*.45)));
  for(let i=0;i<segments;i++){
   const sx=vx/segments,sy=vy/segments;
   if(!collides(player.x+sx,player.y,player.r))player.x+=sx;
   if(!collides(player.x,player.y+sy,player.r))player.y+=sy;
  }
}

const traffic=[
{x:100,y:440,a:0,s:95,c:"#f06b6b"},{x:3820,y:950,a:Math.PI,s:115,c:"#69a7ff"},{x:1145,y:140,a:Math.PI/2,s:82,c:"#ffd35f"},{x:1705,y:2650,a:-Math.PI/2,s:90,c:"#d77cff"},{x:2900,y:1880,a:Math.PI/2,s:88,c:"#8bd6a6"},{x:3500,y:2230,a:-Math.PI/2,s:104,c:"#e7a45f"}];
const targets=[
{x:860,y:440,r:20,hp:3},{x:1420,y:950,r:20,hp:3},{x:2020,y:1450,r:20,hp:3},{x:3120,y:950,r:20,hp:3},{x:580,y:2050,r:20,hp:3},{x:3500,y:1450,r:20,hp:3},{x:2900,y:2520,r:20,hp:3}
];
const trees=[];for(let x=470;x<W;x+=250)for(let y=330;y<H;y+=330){const t={x:x+Math.random()*50,y:y+Math.random()*55};if(!inStreet(t.x,t.y,28)&&!collides(t.x,t.y,20))trees.push(t);}
const bushes=[];
for(let i=0;i<34;i++){
 let x,y,tries=0;
 do{x=110+Math.random()*(W-220);y=110+Math.random()*(H-220);tries++}while((collides(x,y,34)||inStreet(x,y,48))&&tries<80);
 if(collides(x,y,34)||inStreet(x,y,48))continue;
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
canvas.addEventListener("mousemove",e=>{const r=canvas.getBoundingClientRect();const scale=Math.min(r.width/canvas.width,r.height/canvas.height),ox=(r.width-canvas.width*scale)/2,oy=(r.height-canvas.height*scale)/2;const sx=(e.clientX-r.left-ox)/scale,sy=(e.clientY-r.top-oy)/scale,p=updatePointerAim(sx,sy)});
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
function projectileHitsWall(x1,y1,x2,y2,layer=null,targetLayer=null,originX=x1,originY=y1,visualRange=300){
 const dist=Math.hypot(x2-x1,y2-y1),steps=Math.max(1,Math.ceil(dist/8));
 const sourceHeight=buildingHeight(layer),targetHeight=buildingHeight(targetLayer);
 for(let i=1;i<=steps;i++){
  const t=i/steps,x=x1+(x2-x1)*t,y=y1+(y2-y1)*t;
  if(x<0||y<0||x>W||y>H)return true;
  const traveled=Math.hypot(x-originX,y-originY);
  const ht=Math.min(1,traveled/Math.max(1,visualRange));
  const projectileHeight=sourceHeight+(targetHeight-sourceHeight)*ht;
  for(let bi=0;bi<buildings.length;bi++){
   const b=buildings[bi];
   if(!pointInBuilding(x,y,b,0))continue;
   // A shot may travel above the rooftop it was fired from, but walls and
   // other rooftops block it whenever their physical height reaches the shot.
   if(bi===layer&&projectileHeight>=buildingHeight(bi)-4)continue;
   if(projectileHeight<=buildingHeight(bi)+4)return true;
  }
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
  const gun=tacticalPlayerEnabled()?playerGunPose():null;
  const a=(gun?gun.angle:player.angle)+(Math.random()-.5)*w.spread;
  const tip=(player.weapon==="pistol"?27:player.weapon==="smg"?50:56)*.32;
  const projectedLength=gun?Math.hypot(...Object.values(projectVector(Math.cos(gun.angle),Math.sin(gun.angle)))):1;
  const muzzleDistance=gun?tip/projectedLength:28;
  const ox=(gun?gun.x:player.x)+Math.cos(a)*muzzleDistance,oy=(gun?gun.y:player.y)+Math.sin(a)*muzzleDistance;
  const bt=player.weapon==="rifle"?1.15:player.weapon==="sawedoff"?.58:.9,bvx=Math.cos(a)*w.speed,bvy=Math.sin(a)*w.speed;
  bullets.push({x:ox,y:oy,vx:bvx,vy:bvy,t:bt,damage:w.damage,color:w.color,layer:player.roof,visualX:ox,visualY:oy,visualRange:Math.hypot(mouse.x-ox,mouse.y-oy),targetLayer:mouse.layer});
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
 e.movePhase=(e.movePhase||0)+dt*(e.speed>80?10:7);
 const dx=tx-e.x,dy=ty-e.y,d=Math.hypot(dx,dy)||1,step=e.speed*dt;
 const nx=e.x+dx/d*step,ny=e.y+dy/d*step;
 if(!collides(nx,e.y,e.r))e.x=nx;
 if(!collides(e.x,ny,e.r))e.y=ny;
}
function roofSafePoint(roofIndex,preferX=null,preferY=null){
 const b=buildings[roofIndex];if(!b)return null;
 const margin=56;
 const minX=b.x+margin,maxX=b.x+b.w-margin;
 const minY=b.y+margin,maxY=b.y+b.h-margin;
 const x=Math.max(minX,Math.min(maxX,preferX??b.x+b.w*.58));
 const y=Math.max(minY,Math.min(maxY,preferY??b.y+b.h*.46));
 return {x,y};
}
function moveEnemyOnRoof(e,tx,ty,dt){
 e.movePhase=(e.movePhase||0)+dt*(e.speed>80?10:7);
 const b=buildings[e.roof];if(!b)return;
 const safe=roofSafePoint(e.roof,tx,ty);if(!safe)return;
 const dx=safe.x-e.x,dy=safe.y-e.y,d=Math.hypot(dx,dy)||1,step=e.speed*dt;
 e.x=Math.max(b.x+56,Math.min(b.x+b.w-56,e.x+dx/d*step));
 e.y=Math.max(b.y+56,Math.min(b.y+b.h-56,e.y+dy/d*step));
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
   const perch=roofSafePoint(e.roof,lx,b.y+b.h*.55);
   e.x=perch.x;e.y=perch.y;
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
  const lx=l.x+l.w/2,ly=b.y+b.h-58;
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

 const perch=roofSafePoint(e.roof,b.x+b.w*.62,b.y+b.h*.46);
 if(perch&&Math.hypot(e.x-perch.x,e.y-perch.y)>18)moveEnemyOnRoof(e,perch.x,perch.y,dt);
 e.shootCd-=dt;
 if(!player.inCar&&!player.dead&&d<=SNIPER_RANGE&&e.shootCd<=0){
  e.shootCd=2.0+Math.random()*.8;
  const a=e.angle+(Math.random()-.5)*.025,speed=900;
  enemyBullets.push({
   x:e.x+Math.cos(a)*32,y:e.y+Math.sin(a)*32-6,
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
    playSound("missileLaunch",{x:e.x,y:e.y,vol:1.15});
    for(let i=0;i<count;i++){
     let tx=player.x+(Math.random()-.5)*520,ty=player.y+(Math.random()-.5)*420,tries=0;
     while(collides(tx,ty,24)&&tries++<20){tx=player.x+(Math.random()-.5)*520;ty=player.y+(Math.random()-.5)*420}
     tx=Math.max(60,Math.min(W-60,tx));ty=Math.max(60,Math.min(H-60,ty));
     missiles.push({x:tx,y:ty,t:1.65,total:1.65,r:54,exploded:false,startX:tx+(Math.random()-.5)*260,startY:ty-320-Math.random()*180});if(i===0)playSound("missileIncoming",{x:tx,y:ty,vol:1.15});
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

function triggerBossDeath(e){
 if(!e||bossDeathIntro>0||bossDefeated)return;
 bossDefeated=true;bossSpawned=false;
 bossDeathIntro=bossDeathIntroTotal;
 bossDeathScene={x:e.x,y:e.y,angle:e.angle||0,t:0,burst:0};
 enemyBullets.length=0;missiles.length=0;
 flash=1;
 for(let i=0;i<18;i++)sparks.push({x:e.x+(Math.random()-.5)*44,y:e.y+(Math.random()-.5)*36,vx:(Math.random()-.5)*220,vy:(Math.random()-.5)*220,t:.65});
 tone(82,.35,"sawtooth",.18,.48);noise(.25,.18,900);
}
function drawBossDeathWorld(){
 if(!bossDeathScene||bossDeathIntro<=0)return;
 const s=bossDeathScene,p=1-bossDeathIntro/bossDeathIntroTotal;
 ctx.save();ctx.translate(s.x,s.y);ctx.rotate(s.angle);
 // Ground shadow and wreck silhouette.
 ctx.fillStyle="rgba(0,0,0,.68)";ctx.beginPath();ctx.ellipse(10,20,54+18*p,26+8*p,0,0,Math.PI*2);ctx.fill();
 ctx.rotate(p*.18);
 ctx.fillStyle="#321016";ctx.beginPath();ctx.ellipse(0,5,40,31,0,0,Math.PI*2);ctx.fill();
 ctx.strokeStyle="#70242e";ctx.lineWidth=4;ctx.stroke();
 ctx.fillStyle="#171a1e";ctx.fillRect(-37,-25,19,52);ctx.fillRect(18,-25,19,52);
 // Broken turret drops and tilts.
 ctx.save();ctx.translate(10*p,12*p);ctx.rotate(.45*p);
 ctx.fillStyle="#4b151d";ctx.beginPath();ctx.arc(2,-4,23,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#1b1013";ctx.fillRect(16,-11,38,8);ctx.restore();
 // Core flickers before final detonation.
 const flicker=.45+.55*Math.sin(performance.now()/55);
 if(p<.72){ctx.shadowColor="#ff354b";ctx.shadowBlur=18+18*flicker;ctx.fillStyle="#ff3348";ctx.beginPath();ctx.arc(-5,10,5+3*flicker,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0}
 // Smoke plumes.
 for(let i=0;i<5;i++){
  const age=Math.max(0,p-i*.08),r=10+age*34;
  if(age<=0)continue;
  ctx.fillStyle="rgba(43,48,55,"+(0.42-age*.25)+")";ctx.beginPath();ctx.arc(-16+i*9,-18-age*36,r,0,Math.PI*2);ctx.fill();
 }
 ctx.restore();

 window.worldArt?.effect(ctx,"wreck",s.x,s.y,115);

 // Multi-stage explosions.
 const blasts=[.12,.32,.52,.73];
 for(let i=0;i<blasts.length;i++){
  const age=p-blasts[i];if(age<0||age>.22)continue;
  const q=age/.22,r=20+q*70;
  const g=ctx.createRadialGradient(s.x+(i-1.5)*14,s.y+(i%2?-10:7),2,s.x+(i-1.5)*14,s.y+(i%2?-10:7),r);
  g.addColorStop(0,"rgba(255,255,210,"+(1-q)+")");g.addColorStop(.25,"rgba(255,180,55,"+(.9-q*.6)+")");g.addColorStop(.65,"rgba(255,64,30,"+(.55-q*.4)+")");g.addColorStop(1,"rgba(255,40,20,0)");
  ctx.fillStyle=g;ctx.beginPath();ctx.arc(s.x+(i-1.5)*14,s.y+(i%2?-10:7),r,0,Math.PI*2);ctx.fill();
  window.worldArt?.effect(ctx,"explosion",s.x+(i-1.5)*14,s.y+(i%2?-10:7),r*2,1-q);
 }
}
function drawBossDeathOverlay(){
 if(bossDeathIntro<=0||!bossDeathScene)return;
 const p=1-bossDeathIntro/bossDeathIntroTotal;
 ctx.save();ctx.setTransform(1,0,0,1,0,0);
 const fadeIn=Math.min(1,p/.16),fadeOut=Math.min(1,(1-p)/.12),alpha=Math.min(fadeIn,fadeOut);
 ctx.fillStyle="rgba(3,5,8,"+(0.18+0.18*alpha)+")";ctx.fillRect(0,0,canvas.width,canvas.height);
 if(p>.63){
  ctx.textAlign="center";
  ctx.shadowColor="#ff3b4d";ctx.shadowBlur=22;
  ctx.fillStyle="rgba(255,255,255,"+Math.min(1,(p-.63)/.12)+")";
  ctx.font="900 "+Math.round(Math.min(56,canvas.height*.075))+"px system-ui";
  ctx.fillText("GOLIAS ELIMINADO",canvas.width/2,canvas.height*.45);
  ctx.shadowBlur=0;
  ctx.fillStyle="rgba(255,120,105,"+Math.min(1,(p-.7)/.12)+")";
  ctx.font="800 "+Math.round(Math.min(18,canvas.height*.026))+"px system-ui";
  ctx.fillText("AMEAÇA NEUTRALIZADA",canvas.width/2,canvas.height*.50);
 }
 if(p>.84){
  ctx.fillStyle="rgba(220,235,245,"+Math.min(1,(p-.84)/.10)+")";
  ctx.font="700 "+Math.round(Math.min(13,canvas.height*.018))+"px system-ui";
  ctx.fillText("CONTROLE DEVOLVIDO AO JOGADOR",canvas.width/2,canvas.height*.56);
 }
 ctx.textAlign="left";ctx.restore();
}
function drawBossTank(e){
 const pulse=.5+.5*Math.sin(performance.now()/120);
 if(!window.worldArt?.entity(ctx,"boss",{x:e.x,y:e.y,angle:e.angle,size:110,damaged:e.hp<e.maxHp*.4})){
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
 }
 // local boss bar
 const bw=150,by=e.y-86;
 ctx.fillStyle="#0b0d10dd";ctx.fillRect(e.x-bw/2,by,bw,12);
 ctx.fillStyle="#ff3045";ctx.fillRect(e.x-bw/2+2,by+2,(bw-4)*(e.hp/e.maxHp),8);
 ctx.strokeStyle="#5d1d25";ctx.strokeRect(e.x-bw/2+.5,by+.5,bw-1,11);
 ctx.fillStyle="#fff";ctx.font="900 12px system-ui";ctx.textAlign="center";ctx.fillText("GOLIAS",e.x,by-7);ctx.textAlign="left";
}

function drawEnemies(only=null){
 if(gameMode!=="solo")return;
 for(const e of only?[only]:enemies){
  if(!e.alive)continue;if(e.boss){drawBossTank(e);continue}
  const sniper=e.type==="sniper";
  const phase=e.movePhase||0;
  const moving=Math.abs(Math.sin(phase))>.04;
  const roofLift=0;
  if(!window.worldArt?.entity(ctx,sniper?"sniper":"enemy",{x:e.x,y:e.y-roofLift,angle:e.angle,size:sniper?60:57,moving,phase,shooting:e.shootCd>.92}))drawTopDownCharacter({
   x:e.x,y:e.y-roofLift,angle:e.angle,
   outfit:sniper?"#394334":"#343840",skin:"#d1a884",hair:"#171b20",
   weapon:sniper?"rifle":"pistol",shooting:e.shootCd>.92,
   role:sniper?"sniper":"enemy",showLaser:true,
   moving,phase,running:false
  });
  ctx.save();ctx.translate(e.x,e.y);undoProjection(ctx);
  if(sniper){ctx.fillStyle="#a6c7a6";ctx.font="800 8px system-ui";ctx.textAlign="center";ctx.fillText("SNIPER",0,-64)}
  ctx.fillStyle="#11171c";ctx.fillRect(-16,-58,32,4);ctx.fillStyle="#ba655c";ctx.fillRect(-16,-58,32*(e.hp/e.maxHp),4);ctx.restore();
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
  const playerShotBlocked=projectileHitsWall(ox,oy,nx,ny,b.layer,b.targetLayer,b.visualX??ox,b.visualY??oy,b.visualRange||300);
  if(playerShotBlocked){b.x=nx;b.y=ny;b.t=0;sparks.push({x:b.x,y:b.y,vx:(Math.random()-.5)*80,vy:(Math.random()-.5)*80,t:.25});if(Math.random()<.55)playSound("impact",{x:b.x,y:b.y,vol:.7});continue}
  b.x=nx;b.y=ny;
  if(gameMode==="solo"){for(const e of enemies){
   if(!e.alive)continue;
   const enemyOnRoof=e.roof!==null&&e.roof!==undefined;
   const canHitEnemy=playerShotFromRoof||!enemyOnRoof;
   if(canHitEnemy&&Math.hypot(b.x-e.x,b.y-e.y)<e.r+6){
    e.hp-=b.damage||1;b.t=0;
    if(e.hp<=0){e.alive=false;if(e.boss)triggerBossDeath(e);reportKill()}
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
  if(b.visualX===undefined){b.visualX=b.x;b.visualY=b.y;b.visualRange=Math.hypot(player.x-b.x,player.y-b.y);b.targetLayer=player.roof}
  const ox=b.x,oy=b.y,nx=b.x+b.vx*dt,ny=b.y+b.vy*dt;b.t-=dt;
  const fromRoof=b.layer!==null&&b.layer!==undefined;
  const blocked=projectileHitsWall(ox,oy,nx,ny,b.layer,b.targetLayer,b.visualX??ox,b.visualY??oy,b.visualRange||300);
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
  if(b.visualX===undefined){b.visualX=b.x;b.visualY=b.y;b.visualRange=Math.max(40,Math.hypot(player.x-b.x,player.y-b.y))}
  const ox=b.x,oy=b.y,nx=b.x+b.vx*dt,ny=b.y+b.vy*dt;b.t-=dt;
  const fromRoof=b.layer!==null&&b.layer!==undefined;
  const groundShot=b.layer===null||b.layer===undefined;
  const enemyShotBlocked=projectileHitsWall(ox,oy,nx,ny,b.layer,b.targetLayer,b.visualX??ox,b.visualY??oy,b.visualRange||300);
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
   playSound("explosion",{x:m.x,y:m.y,vol:1.2});
  }
 }
 missiles=missiles.filter(m=>m.t>0);
 shells.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.vx*=.94;s.vy*=.94;s.t-=dt});shells=shells.filter(s=>s.t>0);
 hitMarks.forEach(h=>h.t-=dt);hitMarks=hitMarks.filter(h=>h.t>0);
}
function update(dt){
 if(!started||paused)return;
 if(bossDeathIntro>0&&bossDeathScene){
  bossDeathIntro=Math.max(0,bossDeathIntro-dt);bossDeathScene.t+=dt;
  const p=1-bossDeathIntro/bossDeathIntroTotal;
  followCamera(bossDeathScene.x,bossDeathScene.y,dt,5.2);
  if((p>.14&&bossDeathScene.burst<1)||(p>.34&&bossDeathScene.burst<2)||(p>.55&&bossDeathScene.burst<3)||(p>.74&&bossDeathScene.burst<4)){
   bossDeathScene.burst++;
   const count=10+bossDeathScene.burst*4;
   for(let i=0;i<count;i++)sparks.push({x:bossDeathScene.x+(Math.random()-.5)*65,y:bossDeathScene.y+(Math.random()-.5)*50,vx:(Math.random()-.5)*300,vy:(Math.random()-.5)*300,t:.55});
   flash=Math.max(flash,.8);noise(.18,.16,850);tone(70+bossDeathScene.burst*18,.16,"sawtooth",.11,.55);
  }
  sparks.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.t-=dt});sparks=sparks.filter(s=>s.t>0);
  flash=Math.max(0,flash-dt*1.4);
  if(bossDeathIntro<=0){bossDeathScene=null;flash=0;playSound("pickup")}
  return;
 }
 if(bossPhaseIntro>0&&bossIntroBoss?.alive){
  bossPhaseIntro=Math.max(0,bossPhaseIntro-dt);
  flash=Math.max(flash,.45+.35*Math.sin(performance.now()/90));
  followCamera(bossIntroBoss.x,bossIntroBoss.y,dt,4.8);
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
  const move=screenAlignedInput(dx,dy);tryRoofMovement(move.x,move.y,dt,run);
  if(moving)player.walk+=dt*(run>1?13:9);updateFootsteps(moving,run,dt);
  if(Math.hypot(touchAim.x,touchAim.y)>.12){const aim=unprojectVector(touchAim.x,touchAim.y),wx=aim.x,wy=aim.y;player.angle=Math.atan2(wy,wx);mouse.x=player.x+wx*200;mouse.y=player.y+wy*200;mouse.layer=player.roof;}
  else if(!matchMedia("(pointer:coarse)").matches)player.angle=Math.atan2(mouse.y-player.y,mouse.x-player.x);
  if(mouse.down||Math.hypot(touchAim.x,touchAim.y)>.32)shoot();
 }
 ensurePlayerNotStuck();updateBushState();updateBullets(dt);updateEnemies(dt);
 if(gameMode==="solo"&&!bossSpawned&&!bossDefeated&&enemies.filter(e=>e.alive&&!e.boss).length===0)spawnBoss();
 if(!missionDone&&Math.hypot(player.x-mission.x,player.y-mission.y)<70){missionDone=true;flash=1}
 skids.forEach(s=>s.t-=dt*.34);skids=skids.filter(s=>s.t>0);sparks.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.t-=dt});sparks=sparks.filter(s=>s.t>0);damageChunks.forEach(p=>{p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=Math.pow(.055,dt);p.vy*=Math.pow(.055,dt);p.vy+=70*dt;p.rot+=p.spin*dt;p.t-=dt});damageChunks=damageChunks.filter(p=>p.t>0);
 updateEngineSound();updateAmbientSound(dt);
 followCamera(player.x,player.y,dt,5.5,buildingHeight(player.roof));
 if(selectedPlatform!=="mobile"&&mouse.screenX!==null)updatePointerAim(mouse.screenX,mouse.screenY);
 netTimer+=dt;if(netTimer>=.033){netTimer=0;sendNetState()}
}
function road(){
 ctx.fillStyle="#101923";ctx.fillRect(0,0,W,H);
 const width=streets.width,swSize=streets.sidewalk;
 const roadsY=streets.horizontal.map(c=>c-width/2),roadsX=streets.vertical.map(c=>c-width/2);

 // Ground blocks: blue-gray concrete with subtle grime.
 ctx.fillStyle="#3b453b";ctx.fillRect(0,0,W,H);
 ctx.save();
 for(let y=14;y<H;y+=30){
  for(let x=12;x<W;x+=34){
   const n=((x*17+y*11)%37)/37;
   ctx.fillStyle=n>.58?"rgba(145,161,174,.035)":"rgba(4,9,14,.06)";
   ctx.fillRect(x+((y/30)%2)*5,y,2+(n*3),1+(n*2));
  }
 }
 ctx.restore();

 // Sidewalk slabs around roads.
 const sw="#747970";
 ctx.fillStyle=sw;
 for(const y of roadsY){ctx.fillRect(0,y-swSize,W,swSize);ctx.fillRect(0,y+width,W,swSize)}
 for(const x of roadsX){ctx.fillRect(x-swSize,0,swSize,H);ctx.fillRect(x+width,0,swSize,H)}
 ctx.strokeStyle="rgba(205,214,221,.22)";ctx.lineWidth=1;
 for(const y of roadsY){
  for(let x=0;x<W;x+=54){ctx.beginPath();ctx.moveTo(x,y-swSize);ctx.lineTo(x,y);ctx.moveTo(x,y+width);ctx.lineTo(x,y+width+swSize);ctx.stroke()}
 }
 for(const x of roadsX){
  for(let y=0;y<H;y+=54){ctx.beginPath();ctx.moveTo(x-swSize,y);ctx.lineTo(x,y);ctx.moveTo(x+width,y);ctx.lineTo(x+width+swSize,y);ctx.stroke()}
 }

 // Curbs.
 ctx.strokeStyle="#9ba3a8";ctx.lineWidth=2;ctx.globalAlpha=.72;
 for(const y of roadsY){ctx.beginPath();ctx.moveTo(0,y-2);ctx.lineTo(W,y-2);ctx.moveTo(0,y+width+2);ctx.lineTo(W,y+width+2);ctx.stroke()}
 for(const x of roadsX){ctx.beginPath();ctx.moveTo(x-2,0);ctx.lineTo(x-2,H);ctx.moveTo(x+width+2,0);ctx.lineTo(x+width+2,H);ctx.stroke()}
 ctx.globalAlpha=1;

 // Dark asphalt.
 const asphalt=ctx.createLinearGradient(0,roadsY[0],0,roadsY[0]+width);
 asphalt.addColorStop(0,"#343b3b");asphalt.addColorStop(.5,"#414846");asphalt.addColorStop(1,"#303837");
 ctx.fillStyle=asphalt;
 for(const y of roadsY)ctx.fillRect(0,y,W,width);
 for(const x of roadsX)ctx.fillRect(x,0,width,H);

 // Asphalt aggregate/noise.
 ctx.save();ctx.globalAlpha=.22;
 for(let i=0;i<1050;i++){
  const horiz=i%2===0,lane=horiz?roadsY[(i*7)%roadsY.length]:roadsX[(i*11)%roadsX.length];
  const px=horiz?((i*137)%W):lane+((i*19)%(width-6))+3;
  const py=horiz?lane+((i*23)%(width-6))+3:((i*149)%H);
  ctx.fillStyle=i%5===0?"#74808a":"#090d12";
  ctx.fillRect(px,py,1+(i%2),1);
 }
 ctx.restore();

 // District pass inspired by the full-city reference: distinct readable zones.
 // These are mostly visual surfaces so core movement/AI remains stable.
 ctx.save();

 // Central civic plaza / park.
 ctx.fillStyle="#59645a";ctx.fillRect(1185,1020,500,360);
 ctx.fillStyle="#71786f";ctx.beginPath();ctx.arc(1435,1200,118,0,Math.PI*2);ctx.fill();
 ctx.strokeStyle="rgba(220,224,214,.28)";ctx.lineWidth=8;ctx.beginPath();ctx.arc(1435,1200,82,0,Math.PI*2);ctx.stroke();
 ctx.strokeStyle="rgba(220,224,214,.18)";ctx.lineWidth=12;
 for(const a of [0,Math.PI/2,Math.PI,Math.PI*1.5]){
  ctx.beginPath();ctx.moveTo(1435+Math.cos(a)*82,1200+Math.sin(a)*82);ctx.lineTo(1435+Math.cos(a)*170,1200+Math.sin(a)*170);ctx.stroke();
 }
 for(const [tx,ty] of [[1320,1100],[1550,1100],[1320,1300],[1550,1300]]){
  ctx.fillStyle="#2d5b38";ctx.beginPath();ctx.arc(tx,ty,24,0,Math.PI*2);ctx.fill();
 }

 // Residential / greener west side.
 ctx.fillStyle="rgba(52,88,56,.22)";ctx.fillRect(0,0,560,H);
 for(let i=0;i<28;i++){
  const gx=70+(i*83)%430,gy=120+(i*137)%(H-240);
  ctx.fillStyle=i%3===0?"rgba(55,110,65,.45)":"rgba(42,82,50,.35)";
  ctx.beginPath();ctx.arc(gx,gy,8+(i%4)*3,0,Math.PI*2);ctx.fill();
 }

 // Industrial sector east-center.
 ctx.fillStyle="rgba(92,84,68,.22)";ctx.fillRect(1780,0,1420,1850);
 for(const [tx,ty,r] of [[1960,360,46],[2070,360,39],[1975,760,42],[2110,760,48],[2620,360,44],[2760,760,50],[3040,1220,46]]){
  ctx.fillStyle="#74766f";ctx.beginPath();ctx.arc(tx,ty,r,0,Math.PI*2);ctx.fill();
  ctx.strokeStyle="#9a9b90";ctx.lineWidth=5;ctx.stroke();
  ctx.fillStyle="#4d5250";ctx.beginPath();ctx.arc(tx,ty,r*.55,0,Math.PI*2);ctx.fill();
 }

 // Port / container yards on far east.
 ctx.fillStyle="rgba(58,72,78,.34)";ctx.fillRect(3225,0,775,1850);
 const containerColors=["#7a503b","#596f78","#5e6948","#6d4d58"];
 for(let i=0;i<28;i++){
  const cx=3290+(i%7)*82,cy=280+Math.floor(i/7)*72;
  ctx.fillStyle=containerColors[i%containerColors.length];ctx.fillRect(cx,cy,58,24);
  ctx.strokeStyle="rgba(20,25,28,.55)";ctx.strokeRect(cx+.5,cy+.5,57,23);
 }
 // Quays and piers.
 ctx.fillStyle="#5f6462";ctx.fillRect(3860,120,120,1420);
 ctx.fillRect(3720,120,95,560);ctx.fillRect(3720,820,95,520);
 ctx.strokeStyle="#b18b51";ctx.lineWidth=6;
 for(const y of [240,560,920,1260]){ctx.beginPath();ctx.moveTo(3790,y);ctx.lineTo(3960,y-110);ctx.stroke()}

 // Airport carved out in south-east.
 ctx.fillStyle="#59605f";ctx.fillRect(2360,1940,1540,760);
 ctx.fillStyle="#2f3538";ctx.fillRect(2480,2290,1260,130);
 ctx.strokeStyle="#d8d0a2";ctx.lineWidth=3;ctx.setLineDash([34,22]);ctx.beginPath();ctx.moveTo(2530,2355);ctx.lineTo(3690,2355);ctx.stroke();ctx.setLineDash([]);
 ctx.strokeStyle="#d6d9d0";ctx.lineWidth=3;
 for(const x of [2560,2740,2920,3100,3280,3460,3640]){ctx.beginPath();ctx.moveTo(x,2308);ctx.lineTo(x,2324);ctx.moveTo(x,2386);ctx.lineTo(x,2402);ctx.stroke()}
 // Taxiway / apron.
 ctx.fillStyle="#3f4649";ctx.fillRect(2520,2070,1080,110);ctx.fillRect(3460,2070,280,350);
 ctx.strokeStyle="rgba(232,193,84,.65)";ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(2570,2125);ctx.lineTo(3650,2125);ctx.stroke();
 // Simple aircraft silhouette.
 ctx.save();ctx.translate(3360,2125);ctx.fillStyle="#c7ced2";
 ctx.fillRect(-45,-5,90,10);ctx.fillRect(-7,-36,14,72);
 ctx.beginPath();ctx.moveTo(45,-5);ctx.lineTo(64,0);ctx.lineTo(45,5);ctx.closePath();ctx.fill();
 ctx.fillRect(-22,-24,44,5);ctx.restore();

 // Coastal edge / water impression around map border.
 ctx.strokeStyle="#163b48";ctx.lineWidth=26;ctx.strokeRect(12,12,W-24,H-24);
 ctx.strokeStyle="rgba(77,137,153,.28)";ctx.lineWidth=9;ctx.strokeRect(28,28,W-56,H-56);

 ctx.restore();

 // Faded lane markers.
 ctx.strokeStyle="rgba(190,166,76,.68)";ctx.lineWidth=3;ctx.setLineDash([24,22]);ctx.beginPath();
 for(const y of streets.horizontal){
  let from=0;
  for(const x of streets.vertical){ctx.moveTo(from,y);ctx.lineTo(x-width/2-8,y);from=x+width/2+8;}
  ctx.moveTo(from,y);ctx.lineTo(W,y);
 }
 for(const x of streets.vertical){
  let from=0;
  for(const y of streets.horizontal){ctx.moveTo(x,from);ctx.lineTo(x,y-width/2-8);from=y+width/2+8;}
  ctx.moveTo(x,from);ctx.lineTo(x,H);
 }
 ctx.stroke();ctx.setLineDash([]);

 // Crossings span both lanes, outside each clear intersection.
 ctx.fillStyle="rgba(218,220,214,.56)";
 for(const x of streets.vertical)for(const y of streets.horizontal){
  for(let k=-width/2+12;k<width/2-6;k+=14){
   ctx.fillRect(x+k,y-width/2-30,7,24);
   ctx.fillRect(x+width/2+6,y+k,24,7);
  }
 }

 // Patches, cracks and worn asphalt.
 ctx.fillStyle="rgba(5,9,13,.22)";
 for(let i=0;i<24;i++){
  const x=80+(i*223)%(W-140),y=roadsY[i%roadsY.length]+14+(i*29)%(width-28);
  ctx.beginPath();ctx.ellipse(x,y,16+(i%4)*8,5+(i%3)*3,.18,0,Math.PI*2);ctx.fill();
 }
 ctx.strokeStyle="rgba(4,8,11,.86)";ctx.lineWidth=1.6;
 for(let i=0;i<52;i++){
  const horiz=i%3!==0;
  const x=horiz?50+(i*157)%(W-100):roadsX[i%roadsX.length]+12+((i*13)%(width-24));
  const y=horiz?roadsY[i%roadsY.length]+12+((i*31)%(width-24)):40+(i*151)%(H-80);
  ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x+10,y-7);ctx.lineTo(x+21,y+2);ctx.lineTo(x+31,y-5);ctx.stroke();
  if(i%4===0){ctx.beginPath();ctx.moveTo(x+14,y-4);ctx.lineTo(x+10,y+7);ctx.stroke()}
 }

 // Old tire marks.
 ctx.globalAlpha=.26;ctx.strokeStyle="#020406";ctx.lineWidth=4;
 for(let i=0;i<15;i++){
  const x=160+(i*229)%(W-260),y=roadsY[i%roadsY.length]-22;
  ctx.beginPath();ctx.moveTo(x,y);ctx.quadraticCurveTo(x+28,y+(i%2?10:-8),x+68,y+(i%2?3:-3));ctx.stroke();
 }
 ctx.globalAlpha=1;

 // Manholes and drains.
 for(const [mx,my] of [[760,438],[1470,944],[2440,1445]]){
  ctx.fillStyle="#141a20";ctx.beginPath();ctx.arc(mx,my,13,0,Math.PI*2);ctx.fill();
  ctx.strokeStyle="#5b646d";ctx.lineWidth=2;ctx.beginPath();ctx.arc(mx,my,9,0,Math.PI*2);ctx.stroke();
  ctx.strokeStyle="#343b42";ctx.lineWidth=1;for(let a=0;a<4;a++){const ang=a*Math.PI/2;ctx.beginPath();ctx.moveTo(mx-Math.cos(ang)*6,my-Math.sin(ang)*6);ctx.lineTo(mx+Math.cos(ang)*6,my+Math.sin(ang)*6);ctx.stroke()}
 }
}
function drawBuildings(only=null){
 for(const i of only===null?buildings.map((_,i)=>i):[only]){
  const b=buildings[i],h=buildingHeight(i);
  ctx.save();ctx.translate(b.x,b.y);undoProjection(ctx);
  const point=(x,y,z=0)=>{const p=projectVector(x,y);return [p.x,p.y-z]};
  const poly=(points,color,stroke=null)=>{ctx.beginPath();points.forEach((p,k)=>k?ctx.lineTo(...p):ctx.moveTo(...p));ctx.closePath();ctx.fillStyle=color;ctx.fill();if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1;ctx.stroke()}};
  const A=point(0,0),B=point(b.w,0),C=point(b.w,b.h),D=point(0,b.h);
  const ar=point(0,0,h),br=point(b.w,0,h),cr=point(b.w,b.h,h),dr=point(0,b.h,h);
  poly([A,B,C,D].map(p=>[p[0]+32,p[1]+20]),"rgba(0,0,0,.26)");
  // Fade a blocking building so the operator remains visible behind its walls.
  const foot=projectVector(player.x-b.x,player.y-b.y);
  const silhouette=[ar,br,B,C,D,dr];
  const intersects=insidePolygon(foot.x,foot.y,silhouette)||insidePolygon(foot.x,foot.y-38,silhouette);
  if(started&&!player.inCar&&player.roof!==i&&intersects&&player.x+player.y<b.x+b.w+b.y+b.h)ctx.globalAlpha=.25;
  const masonry=[['#726a5b','#58584d'],['#777b72','#555e59'],['#846f60','#63564e'],['#686e72','#4d575b']][i%4];
  poly([D,C,cr,dr],masonry[0],'#292f2d');poly([B,C,cr,br],masonry[1],'#292f2d');
  // Facade-local quads follow both isometric walls and rise vertically.
  function facade(side,u,v,w,height,color,outline){
   const at=(q,z)=>side===0?point(q,b.h,z):point(b.w,q,z);
   poly([at(u,v),at(u+w,v),at(u+w,v+height),at(u,v+height)],color,outline);
  }
  for(let side=0;side<2;side++){
   const span=side===0?b.w:b.h;
   for(let z=8,row=0;z<h-5;z+=12,row++){
    facade(side,0,z,span,1,'rgba(25,30,27,.18)');
    for(let u=12+(row%2)*22;u<span;u+=44)facade(side,u,z,1,12,'rgba(25,30,27,.14)');
   }
   for(let u=27,n=0;u<span-34;u+=68,n++){
    const z=h*.50,lit=(n+i+side)%5===0;
    facade(side,u-4,z-4,38,40,'#303b3b');
    facade(side,u,z,30,32,lit?'#b5a16e':'#3d555c','#9a9b89');
    facade(side,u+14,z,2,32,'#202f33');facade(side,u,z+15,30,2,'#202f33');
    facade(side,u-5,z-7,40,4,'#99998a');
   }
   facade(side,0,0,span,9,'#3c413a');facade(side,0,h-8,span,8,'#9b9d8b');
   for(let n=0;n<7;n++)facade(side,8+(n*47+i*13)%(span-32),12+(n*17)%29,20,4,'rgba(32,40,33,.19)');
  }
  facade(0,b.w*.5-17,8,34,53,'#26332f','#aaa896');
  facade(0,b.w*.5+8,30,3,4,'#d6bb79');
  // Raised roof cap, inset parapet, seams and ventilation units.
  poly([ar,br,cr,dr],i%2?'#666d69':'#747971','#a1a594');
  const inset=10;
  poly([point(inset,inset,h+2),point(b.w-inset,inset,h+2),point(b.w-inset,b.h-inset,h+2),point(inset,b.h-inset,h+2)],'#4a5553','#343d3a');
  ctx.strokeStyle='rgba(174,184,164,.14)';ctx.lineWidth=1;
  for(let x=35;x<b.w-10;x+=42){ctx.beginPath();ctx.moveTo(...point(x,12,h+2));ctx.lineTo(...point(x,b.h-12,h+2));ctx.stroke()}
  for(let y=35;y<b.h-10;y+=42){ctx.beginPath();ctx.moveTo(...point(12,y,h+2));ctx.lineTo(...point(b.w-12,y,h+2));ctx.stroke()}
  const vx=b.w*.25,vy=b.h*.30;
  poly([point(vx,vy+28,h+3),point(vx+44,vy+28,h+3),point(vx+44,vy+28,h+24),point(vx,vy+28,h+24)],'#3c4643');
  poly([point(vx+44,vy,h+3),point(vx+44,vy+28,h+3),point(vx+44,vy+28,h+24),point(vx+44,vy,h+24)],'#303c3b');
  poly([point(vx,vy,h+24),point(vx+44,vy,h+24),point(vx+44,vy+28,h+24),point(vx,vy+28,h+24)],'#8a9388','#434f48');
  for(let q=6;q<40;q+=7){ctx.beginPath();ctx.moveTo(...point(vx+q,vy+4,h+25));ctx.lineTo(...point(vx+q,vy+24,h+25));ctx.strokeStyle='#48544e';ctx.stroke()}
  ctx.restore();
 }
}
function drawLadders(only=null){
 for(const l of only===null?ladders:[ladders[only]]){
  const b=buildings[l.building],h=buildingHeight(l.building),x=l.x+l.w/2,y=b.y+b.h;
  const bottom=projectVector(0,42),top={x:0,y:-h+5};
  ctx.save();ctx.translate(x,y);undoProjection(ctx);
  ctx.strokeStyle='#b2b7a6';ctx.lineWidth=3;
  for(const offset of [-13,13]){ctx.beginPath();ctx.moveTo(bottom.x+offset,bottom.y);ctx.lineTo(top.x+offset,top.y);ctx.stroke()}
  const count=Math.ceil(h/11);
  ctx.lineWidth=2;for(let k=0;k<=count;k++){const t=k/count,cx=bottom.x+(top.x-bottom.x)*t,cy=bottom.y+(top.y-bottom.y)*t;ctx.beginPath();ctx.moveTo(cx-13,cy);ctx.lineTo(cx+13,cy);ctx.stroke()}
  if(Math.hypot(player.x-x,player.y-(y+34))<100||player.roof===l.building){ctx.fillStyle='#bde6cc';ctx.font='800 9px system-ui';ctx.textAlign='center';ctx.fillText('ESCADA',bottom.x,bottom.y+18)}
  ctx.restore();
 }
}

function drawTrees(only=null){(only?[only]:trees).forEach((t,ti)=>{
 ctx.save();ctx.translate(t.x,t.y);undoProjection(ctx);ctx.translate(-t.x,-t.y);
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
 if(window.worldArt?.weapon(ctx,type,x,y,scale,muzzle))return;
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
 if(w>=58&&window.worldArt?.entity(ctx,"jeep",{x,y,angle:a,size:68,damaged:c==="#3a3a3a"||c==="#d86770"}))return;
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
  x,y,angle=0,outfit="#2f343c",skin="#d7b08c",hair="#151a21",
  weapon="pistol",shooting=false,step=0,bob=0,hit=false,
  role="player",showLaser=false,running=false,moving=false,phase=0
 }=opts;

 const styles={
  player:{cloth:outfit,vest:"#6e684b",vestHi:"#918661",pack:"#756d4c",helmet:"#242832",accent:"#a9b4bd"},
  enemy:{cloth:"#343840",vest:"#595a4a",vestHi:"#777866",pack:"#5b5943",helmet:"#252932",accent:"#c74a4a"},
  sniper:{cloth:"#31392d",vest:"#566247",vestHi:"#7a8968",pack:"#4e5840",helmet:"#394034",accent:"#84a665"},
  elite:{cloth:"#252a31",vest:"#3d454e",vestHi:"#606b76",pack:"#30363d",helmet:"#171b21",accent:"#cb4141"},
  boss:{cloth:"#31292b",vest:"#5f4b42",vestHi:"#87695a",pack:"#4a3c35",helmet:"#7a2025",accent:"#ff4f4f"}
 };
 const s=styles[role]||styles.player;
 const screenAngle=projectedAngle(angle);
 const visualAngle=Math.round(screenAngle/(Math.PI/4))*(Math.PI/4);
 const dirDelta=screenAngle-visualAngle;
 const gait=moving?Math.sin(phase||0):0;
 const gait2=moving?Math.cos(phase||0):0;
 const stride=(running?6.2:4.2)*gait;
 const bodyBob=(running?2.1:1.25)*Math.abs(gait2)+(bob||0)*.35;
 const lean=running?2.5:0;

 ctx.save();ctx.translate(x,y);undoProjection(ctx);

 // Contact shadow responds to movement and gives the body stronger relief.
 ctx.fillStyle="rgba(0,0,0,.42)";ctx.beginPath();ctx.ellipse(5,19,running?24:21,running?8:9,visualAngle*.08,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="rgba(0,0,0,.16)";ctx.beginPath();ctx.ellipse(9,20,running?31:27,12,0,0,Math.PI*2);ctx.fill();

 ctx.rotate(visualAngle);
 ctx.translate(lean,0);

 // Legs with alternating stride and visible knee pads.
 ctx.fillStyle="#20252b";
 ctx.beginPath();ctx.ellipse(-7,10+stride,6.7,13,-.12,0,Math.PI*2);ctx.ellipse(7,10-stride,6.7,13,.12,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#343a40";
 ctx.beginPath();ctx.ellipse(-7,7+stride,5,4,0,0,Math.PI*2);ctx.ellipse(7,7-stride,5,4,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle="#0c1014";
 ctx.beginPath();ctx.ellipse(-9,20+stride,7.5,4.8,.10,0,Math.PI*2);ctx.ellipse(10,20-stride,7.5,4.8,-.10,0,Math.PI*2);ctx.fill();

 // Backpack sits behind the torso like the reference sheet.
 ctx.fillStyle="#10151a";ctx.beginPath();ctx.roundRect(-18,-10+bodyBob,16,31,7);ctx.fill();
 ctx.fillStyle=s.pack;ctx.beginPath();ctx.roundRect(-16,-8+bodyBob,13,27,6);ctx.fill();
 ctx.strokeStyle="rgba(15,18,18,.55)";ctx.lineWidth=1.4;
 for(let yy=-3;yy<15;yy+=6){ctx.beginPath();ctx.moveTo(-14,yy+bodyBob);ctx.lineTo(-5,yy+bodyBob);ctx.stroke()}
 ctx.strokeStyle="#11171b";ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(-5,-8+bodyBob);ctx.lineTo(-1,-18+bodyBob);ctx.stroke();

 // Shoulders / upper body.
 ctx.fillStyle=hit?"#ff777f":s.cloth;
 ctx.beginPath();ctx.ellipse(-11,-3+bodyBob,8.5,9,-.24,0,Math.PI*2);ctx.ellipse(10,-3+bodyBob,8.5,9,.24,0,Math.PI*2);ctx.fill();
 const torso=ctx.createLinearGradient(-16,-12,16,18);
 torso.addColorStop(0,hit?"#ff9aa0":s.cloth);torso.addColorStop(.55,s.cloth);torso.addColorStop(1,"#151a20");
 ctx.fillStyle=torso;ctx.beginPath();ctx.roundRect(-15,-11+bodyBob,30,30,10);ctx.fill();
 ctx.strokeStyle="rgba(0,0,0,.48)";ctx.lineWidth=1.4;ctx.stroke();

 // Tactical vest + straps + pouches.
 ctx.fillStyle=s.vest;ctx.beginPath();ctx.roundRect(-12,-7+bodyBob,24,21,5);ctx.fill();
 ctx.strokeStyle=s.vestHi;ctx.lineWidth=1.2;ctx.strokeRect(-10,-5+bodyBob,20,17);
 ctx.strokeStyle="#11171b";ctx.lineWidth=2;
 ctx.beginPath();ctx.moveTo(-8,-7+bodyBob);ctx.lineTo(-5,14+bodyBob);ctx.moveTo(8,-7+bodyBob);ctx.lineTo(5,14+bodyBob);ctx.stroke();
 ctx.fillStyle=s.vestHi;ctx.fillRect(-9,2+bodyBob,6,5);ctx.fillRect(3,2+bodyBob,6,5);ctx.fillRect(-3,8+bodyBob,6,5);

 // Belt / holster.
 ctx.fillStyle="#11161b";ctx.fillRect(-14,13+bodyBob,28,4);
 ctx.fillStyle="#5f676f";ctx.fillRect(-3,13.5+bodyBob,6,3);
 ctx.fillStyle="#161b20";ctx.roundRect(-17,12+bodyBob,5,10,2);ctx.fill();

 // Neck and larger top-down head.
 ctx.fillStyle=skin;ctx.fillRect(-3,-15+bodyBob,8,7);
 ctx.fillStyle="#0d1115";ctx.beginPath();ctx.ellipse(0,-21+bodyBob,11.7,12.5,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle=skin;ctx.beginPath();ctx.ellipse(1,-20.5+bodyBob,10,10.8,0,0,Math.PI*2);ctx.fill();
 ctx.fillStyle=hair;ctx.beginPath();ctx.arc(-2,-22+bodyBob,8.4,Math.PI*.88,Math.PI*1.94);ctx.lineTo(6,-20+bodyBob);ctx.closePath();ctx.fill();

 // Cap / helmet with clear brim in the facing direction.
 ctx.fillStyle=s.helmet;ctx.beginPath();ctx.ellipse(0,-24+bodyBob,11.4,7.5,0,Math.PI,Math.PI*2);ctx.fill();
 ctx.fillStyle=s.accent;ctx.globalAlpha=.65;ctx.fillRect(5,-24+bodyBob,11,3);ctx.globalAlpha=1;
 ctx.strokeStyle="rgba(255,255,255,.11)";ctx.lineWidth=1;ctx.beginPath();ctx.arc(0,-23+bodyBob,9.5,Math.PI,Math.PI*1.82);ctx.stroke();

 // Headset.
 ctx.strokeStyle="#11161b";ctx.lineWidth=2.8;ctx.beginPath();ctx.arc(0,-22+bodyBob,10.5,Math.PI*.86,Math.PI*1.68);ctx.stroke();
 ctx.fillStyle="#0b0f13";ctx.beginPath();ctx.arc(-8.7,-20+bodyBob,3.8,0,Math.PI*2);ctx.fill();

 // Face cue and brim shadow.
 ctx.fillStyle="rgba(38,26,23,.48)";ctx.beginPath();ctx.ellipse(8,-18.5+bodyBob,2.4,1.6,0,0,Math.PI*2);ctx.fill();

 // Arms dynamically brace the weapon.
 const armSwing=moving?gait*(running?2.4:1.2):0;
 ctx.strokeStyle=s.cloth;ctx.lineWidth=8.5;ctx.lineCap="round";
 ctx.beginPath();ctx.moveTo(8,-4+bodyBob);ctx.lineTo(19,-9+bodyBob-armSwing);ctx.stroke();
 ctx.beginPath();ctx.moveTo(8,7+bodyBob);ctx.lineTo(20,10+bodyBob+armSwing);ctx.stroke();
 ctx.strokeStyle=skin;ctx.lineWidth=5.2;
 ctx.beginPath();ctx.moveTo(18,-9+bodyBob-armSwing);ctx.lineTo(28,-3+bodyBob);ctx.stroke();
 ctx.beginPath();ctx.moveTo(19,10+bodyBob+armSwing);ctx.lineTo(29,4+bodyBob);ctx.stroke();
 ctx.fillStyle="#11161b";ctx.beginPath();ctx.arc(28,-3+bodyBob,3.9,0,Math.PI*2);ctx.arc(29,4+bodyBob,3.9,0,Math.PI*2);ctx.fill();

 // Weapon angle can still follow the exact aim direction inside the snapped 8-way body.
 ctx.save();ctx.translate(26,bodyBob-.5);ctx.rotate(dirDelta);
 drawWeaponModel(weapon,0,0,role==="sniper"?.43:.39,shooting);
 ctx.restore();

 if(shooting){
  ctx.fillStyle="rgba(255,204,95,.20)";ctx.beginPath();ctx.arc(47,bodyBob,12,0,Math.PI*2);ctx.fill();
 }
 if(showLaser){
  ctx.save();ctx.rotate(dirDelta);ctx.strokeStyle=role==="sniper"?"#80ff9f":"#ff5c5c";ctx.lineWidth=1;ctx.globalAlpha=.48;
  ctx.beginPath();ctx.moveTo(42,0);ctx.lineTo(role==="sniper"?126:84,0);ctx.stroke();ctx.restore();
 }
 ctx.restore();
}
function drawPlayer(){
 if(player.inCar||player.dead)return;
 const moving=keys.w||keys.a||keys.s||keys.d||keys.arrowup||keys.arrowdown||keys.arrowleft||keys.arrowright||Math.hypot(touchMove.x,touchMove.y)>.1;
 const running=moving&&!!keys.shift;
 const bob=moving?Math.sin(player.walk)*1.4:0,step=moving?Math.sin(player.walk)*4.2:0;
 const recoil=player.hitT>0?player.hitKick*(.65+.35*Math.sin(performance.now()/24)):0;
 if(tacticalPlayerEnabled()){
  const gun=playerGunPose();
  if(window.playerArt.draw(ctx,{
   x:player.x,y:player.y,angle:player.angle,gunAngle:gun.screenAngle,
   weapon:player.weapon,shooting:player.shootCd>Math.max(0,weapons[player.weapon].fire-.065),
   moving,running,phase:player.walk,hit:player.hitT>0
  },drawWeaponModel))return;
 }

 drawTopDownCharacter({
  x:player.x-Math.cos(player.angle)*recoil,
  y:player.y-Math.sin(player.angle)*recoil,
  angle:player.angle,outfit:characterStyle.outfit,skin:characterStyle.skin,hair:characterStyle.hair,
  weapon:player.weapon,shooting:player.shootCd>.10,step,bob,hit:player.hitT>0,role:"player",
  moving,running,phase:player.walk
 });
}
function drawRemotePlayers(only=null){
 const now=performance.now();
 for(const [id,p] of only?[only]:remotePlayers){
  if(now-p.seen>6000){remotePlayers.delete(id);continue}
  p.renderX+=(p.x-p.renderX)*.38;p.renderY+=(p.y-p.renderY)*.38;
  const rxp=p.renderX,ryp=p.renderY;
  ctx.save();const lift=unprojectVector(0,-buildingHeight(p.roof));ctx.translate(lift.x,lift.y);
  if(p.inCar){drawVehicle(rxp,ryp,p.angle||0,"#42b9ff",58,30)}
  else{
   drawTopDownCharacter({
    x:rxp,y:ryp,angle:p.angle||0,outfit:"#3f9ee8",skin:"#d7b08c",hair:"#151a21",
    weapon:p.weapon||"pistol",shooting:!!p.shooting,role:"player",
    moving:Math.hypot((p.x??rxp)-rxp,(p.y??ryp)-ryp)>.5,phase:performance.now()/120
   });
  }
  ctx.save();ctx.translate(rxp,ryp);undoProjection(ctx);ctx.font="700 11px system-ui";ctx.textAlign="center";ctx.fillStyle="#dff5ff";ctx.fillText(p.name||"Jogador",0,-65);
  const hp=Math.max(0,Math.min(100,Number(p.health??100)));ctx.fillStyle="#111";ctx.fillRect(-18,-58,36,4);ctx.fillStyle="#65ff8b";ctx.fillRect(-18,-58,36*hp/100,4);ctx.restore();ctx.restore();
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
 if(player.inCar||!started||bossPhaseIntro>0)return;const x=worldToScreenX(mouse.x,mouse.y),y=worldToScreenY(mouse.y,mouse.x)-buildingHeight(mouse.layer)*getViewZoom();ctx.strokeStyle="#ffffffdd";ctx.lineWidth=2;ctx.beginPath();ctx.arc(x,y,9,0,Math.PI*2);ctx.moveTo(x-15,y);ctx.lineTo(x-5,y);ctx.moveTo(x+5,y);ctx.lineTo(x+15,y);ctx.moveTo(x,y-15);ctx.lineTo(x,y-5);ctx.moveTo(x,y+5);ctx.lineTo(x,y+15);ctx.stroke()
}
function hud(){
 ctx.setTransform(1,0,0,1,0,0);

 // Compact player HUD.
 const px=18,py=18,pw=190,ph=82;
 ctx.fillStyle="#061018c8";ctx.fillRect(px,py,pw,ph);ctx.strokeStyle="#2d4758";ctx.strokeRect(px+.5,py+.5,pw-1,ph-1);
 ctx.fillStyle="#8ea0ad";ctx.font="700 9px system-ui";ctx.fillText(player.inCar?"VEÍCULO":"STATUS",px+12,py+17);
 ctx.textAlign="right";ctx.fillStyle=fps>=50?"#8fe3a1":fps>=30?"#ffd36a":"#ff7c86";ctx.font="800 9px system-ui";ctx.fillText(fps+" FPS",px+pw-10,py+17);ctx.textAlign="left";
 ctx.fillStyle="#fff";ctx.font="900 18px system-ui";ctx.fillText(player.inCar?Math.round(Math.abs(car.speed)*.22)+" km/h":"A PÉ",px+12,py+39);
 ctx.fillStyle="#263640";ctx.fillRect(px+12,py+49,122,7);
 ctx.fillStyle=player.health>55?"#65ff8b":player.health>25?"#ffd45c":"#ff626e";ctx.fillRect(px+12,py+49,122*(player.health/player.maxHealth),7);
 ctx.fillStyle="#cbd7df";ctx.font="800 9px system-ui";ctx.fillText(Math.ceil(player.health)+" HP",px+140,py+56);
 if(!player.inCar){
  ctx.fillStyle=player.reloading?"#ffd45c":"#dbe7ef";ctx.font="800 10px system-ui";
  ctx.fillText(player.reloading?"RECARREGANDO":player.ammo+" / "+player.reserve+"  "+weapons[player.weapon].name,px+12,py+73);
  if(player.roof!==null){ctx.fillStyle="#7ee8ff";ctx.fillText("TELHADO",px+128,py+17)}
  else if(player.hidden){ctx.fillStyle="#71e69a";ctx.fillText("OCULTO",px+132,py+17)}
 }

 const bossTop=getBoss();
 if(bossTop){
  const bw=Math.min(460,canvas.width*.38),bx=(canvas.width-bw)/2,by=16;
  ctx.fillStyle="#071018d8";ctx.fillRect(bx,by,bw,34);ctx.strokeStyle="#263845";ctx.strokeRect(bx+.5,by+.5,bw-1,33);
  ctx.fillStyle="#fff";ctx.font="900 11px system-ui";ctx.textAlign="center";ctx.fillText("GOLIAS • FASE "+(bossTop.phase||1),canvas.width/2,by+13);
  ctx.fillStyle="#263640";ctx.fillRect(bx+12,by+20,bw-24,6);ctx.fillStyle="#ff3045";ctx.fillRect(bx+12,by+20,(bw-24)*(bossTop.hp/bossTop.maxHp),6);ctx.textAlign="left";
 }

 // Vehicle HUD only while driving or damaged enough to matter.
 if(player.inCar||car.health<100){
  const rw=170,rh=58,rx=canvas.width-rw-18,ry=18;
  ctx.fillStyle="#061018c8";ctx.fillRect(rx,ry,rw,rh);ctx.strokeStyle="#2d4758";ctx.strokeRect(rx+.5,ry+.5,rw-1,rh-1);
  ctx.fillStyle="#fff";ctx.font="800 9px system-ui";ctx.fillText(car.health<=0?"QUEBRADO":"CARRO",rx+10,ry+14);
  ctx.fillStyle="#263640";ctx.fillRect(rx+10,ry+22,150,6);ctx.fillStyle=car.health>40?"#65ff8b":"#e66";ctx.fillRect(rx+10,ry+22,150*car.health/100,6);
  ctx.fillStyle="#263640";ctx.fillRect(rx+10,ry+40,150,6);ctx.fillStyle="#24d9ff";ctx.fillRect(rx+10,ry+40,150*car.nitro/100,6);
 }

 // Small lower-left match info.
 const alive=targets.filter(t=>t.hp>0).length,boxW=205,boxH=60,bx=18,by=canvas.height-boxH-18;
 ctx.fillStyle="#061018bf";ctx.fillRect(bx,by,boxW,boxH);
 ctx.fillStyle="#fff";ctx.font="800 10px system-ui";
 if(gameMode==="solo"){
  const boss=getBoss(),normalLeft=enemies.filter(e=>e.alive&&!e.boss).length;
  ctx.fillText("SOLO  •  KILLS "+kills,bx+11,by+17);
  ctx.fillStyle=boss?"#ff626e":bossDefeated?"#65ff8b":"#ff8b8b";
  ctx.fillText(boss?"GOLIAS "+Math.ceil(boss.hp)+" / "+boss.maxHp:bossDefeated?"BOSS DERROTADO":"INIMIGOS "+normalLeft,bx+11,by+35);
 }else{
  ctx.fillText(connectionStatus==="connected"?"ONLINE • "+kills+" KILLS":"OFFLINE",bx+11,by+17);
 }
 ctx.fillStyle="#9fb0bd";ctx.fillText("ALVOS "+alive,bx+11,by+52);

 // Smaller minimap.
 const mw=132,mh=82,mx=canvas.width-mw-18,my=canvas.height-mh-18;
 ctx.fillStyle="#061018d0";ctx.fillRect(mx,my,mw,mh);ctx.fillStyle="#344048";
 ctx.fillStyle="#202c38";
 for(const y of streets.horizontal)ctx.fillRect(mx,my+(y-streets.width/2)/H*mh,mw,streets.width/H*mh);
 for(const x of streets.vertical)ctx.fillRect(mx+(x-streets.width/2)/W*mw,my,streets.width/W*mw,mh);
 ctx.fillStyle="#344048";
 buildings.forEach(b=>ctx.fillRect(mx+b.x/W*mw,my+b.y/H*mh,b.w/W*mw,b.h/H*mh));
 ctx.save();ctx.font="700 5px system-ui";ctx.fillStyle="#b7c8d2";ctx.textAlign="center";
 ctx.fillText("CENTRO",mx+1435/W*mw,my+1180/H*mh);
 ctx.fillText("IND.",mx+2700/W*mw,my+980/H*mh);
 ctx.fillText("PORTO",mx+3620/W*mw,my+820/H*mh);
 ctx.fillText("AEROP.",mx+3200/W*mw,my+2380/H*mh);
 ctx.restore();
 if(!missionDone){ctx.fillStyle="#ffd65b";ctx.beginPath();ctx.arc(mx+mission.x/W*mw,my+mission.y/H*mh,3,0,Math.PI*2);ctx.fill()}
 ctx.fillStyle="#65ff8b";ctx.beginPath();ctx.arc(mx+player.x/W*mw,my+player.y/H*mh,3.3,0,Math.PI*2);ctx.fill();
 if(gameMode==="solo"){for(const e of enemies){if(!e.alive)continue;ctx.fillStyle=e.boss?"#ff2d3f":"#ff8b8b";ctx.beginPath();ctx.arc(mx+e.x/W*mw,my+e.y/H*mh,e.boss?3.6:2.2,0,Math.PI*2);ctx.fill()}}

 if(gameMode==="multi"){
  const rows=[{name:playerName,kills},...Array.from(ranking.values())].sort((a,b)=>b.kills-a.kills).slice(0,3);
  const rw=150,rh=24+rows.length*18,rx2=canvas.width-rw-18,ry2=86;
  ctx.fillStyle="#061018c8";ctx.fillRect(rx2,ry2,rw,rh);ctx.fillStyle="#fff";ctx.font="900 9px system-ui";ctx.fillText("RANK",rx2+10,ry2+15);
  rows.forEach((p,i)=>{ctx.fillStyle=i===0?"#ffd45c":"#dce7ee";ctx.font="700 9px system-ui";ctx.fillText((i+1)+". "+p.name,rx2+10,ry2+34+i*18);ctx.textAlign="right";ctx.fillText(String(p.kills),rx2+rw-10,ry2+34+i*18);ctx.textAlign="left"});
 }

 const ladderNear=player.roof===null&&ladders.find(l=>Math.abs(player.x-(l.x+l.w/2))<=48&&player.y>=l.y-4&&player.y<=l.y+l.h+28);
 if(ladderNear){ctx.fillStyle="#081119d8";ctx.fillRect(canvas.width/2-76,canvas.height-78,152,24);ctx.fillStyle="#7ee8ff";ctx.font="900 9px system-ui";ctx.fillText("SUBA PELA ESCADA",canvas.width/2-52,canvas.height-62)}
 const near=!player.inCar&&car.health>0&&Math.hypot(player.x-car.x,player.y-car.y)<82;
 if(near){ctx.fillStyle="#081119d8";ctx.fillRect(canvas.width/2-70,canvas.height-48,140,24);ctx.fillStyle="#dfffe6";ctx.font="900 9px system-ui";ctx.fillText("E  ENTRAR NO CARRO",canvas.width/2-50,canvas.height-32)}

 if(player.dead){ctx.fillStyle="#140307b8";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="900 38px system-ui";ctx.fillText("VOCÊ FOI DERRUBADO",canvas.width/2,canvas.height/2-10);ctx.fillStyle="#ff9ba3";ctx.font="800 16px system-ui";ctx.fillText("Renasce em "+Math.max(1,Math.ceil(player.respawnT))+"...",canvas.width/2,canvas.height/2+22);ctx.textAlign="left"}
 if(paused){ctx.fillStyle="#030609aa";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="900 36px system-ui";ctx.fillText("PAUSADO",canvas.width/2,canvas.height/2);ctx.textAlign="left"}
 if(flash>0){ctx.fillStyle="rgba(255,90,90,"+Math.min(.28,flash*.2)+")";ctx.fillRect(0,0,canvas.width,canvas.height)}
 drawBossPhaseIntro();drawCrosshair();
}
function drawWorldLighting(){
 // Cool night tint.
 ctx.save();ctx.fillStyle="rgba(18,28,24,.06)";ctx.fillRect(0,0,W,H);ctx.restore();

 ctx.save();ctx.globalCompositeOperation="screen";
 // Street lamps at intersections and road edges.
 const lamps=streets.vertical.flatMap(x=>streets.horizontal.map(y=>[x+streets.width/2+12,y-streets.width/2-12]));
 for(const [x,y] of lamps){
  ctx.save();ctx.translate(x,y);undoProjection(ctx);ctx.fillStyle="#333c36";ctx.fillRect(-2,-48,4,48);ctx.fillStyle="#a4afa0";ctx.fillRect(-7,-50,14,4);ctx.restore();
  const cone=ctx.createRadialGradient(x,y+18,2,x,y+45,105);cone.addColorStop(0,"rgba(255,213,154,.38)");cone.addColorStop(.45,"rgba(255,165,92,.13)");cone.addColorStop(1,"rgba(255,140,70,0)");
  ctx.fillStyle=cone;ctx.beginPath();ctx.arc(x,y+45,105,0,Math.PI*2);ctx.fill();
 }
 // Building entrance glow.
 for(let i=0;i<buildings.length;i++){
  const b=buildings[i],x=b.x+b.w*.5,y=b.y+b.h-4;
  const g=ctx.createRadialGradient(x,y,3,x,y,82);g.addColorStop(0,"rgba(255,187,104,.28)");g.addColorStop(1,"rgba(255,150,70,0)");
  ctx.fillStyle=g;ctx.beginPath();ctx.arc(x,y,82,0,Math.PI*2);ctx.fill();
 }
 // Tree moon highlights.
 for(const t of trees){const g=ctx.createRadialGradient(t.x-10,t.y-62,1,t.x-10,t.y-62,34);g.addColorStop(0,"rgba(125,176,210,.10)");g.addColorStop(1,"rgba(100,150,190,0)");ctx.fillStyle=g;ctx.beginPath();ctx.arc(t.x-10,t.y-62,34,0,Math.PI*2);ctx.fill()}
 ctx.restore();

 // Ambient mist/smoke patches.
 ctx.save();ctx.globalAlpha=.11;
 for(let i=0;i<12;i++){
  const x=180+(i*239)%(W-360),y=210+(i*173)%(H-420),r=34+(i%4)*18;
  const g=ctx.createRadialGradient(x,y,2,x,y,r);g.addColorStop(0,"rgba(190,205,220,.55)");g.addColorStop(1,"rgba(190,205,220,0)");
  ctx.fillStyle=g;ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fill();
 }
 ctx.restore();
}
function render(){
 ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle='#202b28';ctx.fillRect(0,0,canvas.width,canvas.height);
 ctx.save();const z=getViewZoom();ctx.translate(viewOffsetX(),viewOffsetY());ctx.transform(ISO.a*z,ISO.b*z,ISO.c*z,ISO.d*z,0,0);ctx.translate(-cam.x,-cam.y);
 road();drawBushes(true);drawWeaponPickups();drawMission();drawTargets();
 for(const s of skids){ctx.globalAlpha=Math.max(0,s.t*.4);ctx.save();ctx.translate(s.x,s.y);ctx.rotate(s.a);ctx.fillStyle='#090a0b';ctx.fillRect(-18,-12,36,3);ctx.fillRect(-18,9,36,3);ctx.restore()}ctx.globalAlpha=1;
 drawWorldLighting();
 const queue=[],add=(depth,draw)=>queue.push({depth,draw});
 buildings.forEach((b,i)=>add(b.x+b.w+b.y+b.h,()=>{
  drawBuildings(i);drawLadders(i);
  if(player.roof===i)elevated(i,drawPlayer);
  for(const e of enemies)if(e.alive&&e.roof===i)elevated(i,()=>drawEnemies(e));
 }));
 for(const t of trees)add(t.x+t.y,()=>drawTrees(t));
 for(const e of enemies)if(e.alive&&(e.roof===null||e.roof===undefined))add(e.x+e.y,()=>drawEnemies(e));
 for(const t of traffic)add(t.x+t.y,()=>drawVehicle(t.x,t.y,t.a,t.c,54,27));
 add(car.x+car.y,()=>drawVehicle(car.x,car.y,car.angle,car.health<=0?'#3a3a3a':car.health>40?'#65ff8b':'#d86770'));
 if(player.roof===null)add(player.x+player.y,drawPlayer);
 for(const entry of remotePlayers){const p=entry[1],roof=buildings[p.roof];add(roof?roof.x+roof.w+roof.y+roof.h+.5:p.x+p.y,()=>drawRemotePlayers(entry));}
 queue.sort((a,b)=>a.depth-b.depth).forEach(o=>o.draw());
 drawBossDeathWorld();drawBushes(false);
 bullets.forEach(b=>{const a=Math.atan2(b.vy,b.vx);ctx.save();const visual=projectileVisualPoint(b);ctx.translate(visual.x,visual.y);ctx.rotate(a);const col=b.color||"#ffe36e";ctx.shadowColor=col;ctx.shadowBlur=10;ctx.strokeStyle=col;ctx.lineWidth=4;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(-14,0);ctx.lineTo(4,0);ctx.stroke();ctx.shadowBlur=0;ctx.fillStyle="#fff8d2";ctx.beginPath();ctx.arc(5,0,2.4,0,Math.PI*2);ctx.fill();ctx.restore()});
 remoteBullets.forEach(b=>{const a=Math.atan2(b.vy,b.vx);ctx.save();const visual=projectileVisualPoint(b);ctx.translate(visual.x,visual.y);ctx.rotate(a);ctx.shadowColor=b.color||"#7ee8ff";ctx.shadowBlur=12;ctx.strokeStyle=b.color||"#7ee8ff";ctx.lineWidth=6;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(-18,0);ctx.lineTo(7,0);ctx.stroke();ctx.shadowBlur=0;ctx.fillStyle="#fff";ctx.beginPath();ctx.arc(8,0,3,0,Math.PI*2);ctx.fill();ctx.restore()});
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
   if(!window.worldArt?.effect(ctx,"explosion",m.x,m.y,m.r*2.2,m.t/.35)){
    ctx.fillStyle="rgba(255,92,28,"+(m.t/.35)+")";ctx.beginPath();ctx.arc(m.x,m.y,m.r*(1.2-m.t/.7),0,Math.PI*2);ctx.fill();
   }
  }
  ctx.restore();
 });
 enemyBullets.forEach(b=>{
  const a=Math.atan2(b.vy,b.vx);
  ctx.save();const visual=projectileVisualPoint(b);ctx.translate(visual.x,visual.y);ctx.rotate(a);
  ctx.strokeStyle=b.phase2?"#ffcf33":b.boss?"#ff00aa":"#ff3b3b";ctx.lineWidth=b.phase2?7:b.boss?6:4;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(b.phase2?-20:-14,0);ctx.lineTo(4,0);ctx.stroke();
  ctx.fillStyle="#fff3a3";ctx.beginPath();ctx.arc(5,0,4.5,0,Math.PI*2);ctx.fill();
  ctx.shadowColor="#ff3b3b";ctx.shadowBlur=12;ctx.fillStyle="#ff6565";ctx.beginPath();ctx.arc(5,0,3,0,Math.PI*2);ctx.fill();ctx.restore();
 });
 ctx.fillStyle="#d9b761";shells.forEach(s=>ctx.fillRect(s.x,s.y,3,2));
 sparks.forEach(s=>{ctx.fillStyle="#ffd76b";ctx.fillRect(s.x,s.y,3,3)});damageChunks.forEach(p=>{ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.rot);ctx.globalAlpha=Math.max(0,Math.min(1,p.t/(p.maxT||.7)));ctx.fillStyle=p.dark?"#6b171d":"#c92f39";ctx.fillRect(-p.r,-p.r*.55,p.r*2,p.r*1.1);ctx.restore()});ctx.globalAlpha=1;hitMarks.forEach(h=>{ctx.save();ctx.globalAlpha=Math.max(.15,Math.min(1,h.t/.25));ctx.strokeStyle="#fff";ctx.lineWidth=2;ctx.shadowColor="#ff4d5a";ctx.shadowBlur=8;ctx.beginPath();ctx.moveTo(h.x-9,h.y-9);ctx.lineTo(h.x-3,h.y-3);ctx.moveTo(h.x+9,h.y-9);ctx.lineTo(h.x+3,h.y-3);ctx.moveTo(h.x-9,h.y+9);ctx.lineTo(h.x-3,h.y+3);ctx.moveTo(h.x+9,h.y+9);ctx.lineTo(h.x+3,h.y+3);ctx.stroke();ctx.restore()});
 ctx.restore();hud();drawBossDeathOverlay()
}
let fps=60,fpsFrames=0,fpsAccum=0,last=performance.now();
function loop(t){
 const dt=Math.min(.033,(t-last)/1000);last=t;
 fpsFrames++;fpsAccum+=dt;
 if(fpsAccum>=.5){fps=Math.round(fpsFrames/fpsAccum);fpsFrames=0;fpsAccum=0}
 update(dt);render();requestAnimationFrame(loop)
}
requestAnimationFrame(loop);
for(const btn of document.querySelectorAll("[data-key]")){const k=btn.dataset.key;const down=e=>{e.preventDefault();keys[k]=true},up=e=>{e.preventDefault();keys[k]=false};btn.addEventListener("pointerdown",down);btn.addEventListener("pointerup",up);btn.addEventListener("pointercancel",up);btn.addEventListener("pointerleave",up)}
for(const btn of document.querySelectorAll('[data-action="e"]'))btn.addEventListener("click",toggleCar);
function bindJoystick(id,axis){
 const el=document.getElementById(id);if(!el)return;
 const knob=el.querySelector(".stick-knob");let active=null;
 const reset=()=>{axis.x=0;axis.y=0;knob.style.left="50%";knob.style.top="50%";active=null};
 el.style.touchAction="none";
  el.addEventListener("pointerdown",e=>{if(active!==null)return;e.preventDefault();active=e.pointerId;el.setPointerCapture(active);move(e)});
 function move(e){if(e.pointerId!==active)return;const r=el.getBoundingClientRect(),radius=r.width*.34;
  const dx=e.clientX-(r.left+r.width/2),dy=e.clientY-(r.top+r.height/2),len=Math.hypot(dx,dy),scale=Math.min(1,radius/(len||1));
  const deadzone=.12,rawX=dx*scale/radius,rawY=dy*scale/radius;
   const strength=Math.hypot(rawX,rawY),adjusted=strength<=deadzone?0:(strength-deadzone)/(1-deadzone);
   axis.x=strength?rawX/strength*adjusted:0;axis.y=strength?rawY/strength*adjusted:0;
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
