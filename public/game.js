const canvas=document.getElementById("gameCanvas"),ctx=canvas.getContext("2d"),W=2800,H=1900;
const keys={},cam={x:0,y:0},player={x:340,y:650,r:16,speed:190,inCar:false,angle:0},car={x:530,y:670,angle:0,speed:0,acc:430,max:470,turn:2.5,health:100,nitro:100};
let started=false,paused=false,missionDone=false,flash=0,skids=[],sparks=[];
const mission={x:2440,y:1560,r:48};
const buildings=[
{x:80,y:70,w:360,h:240},{x:700,y:70,w:300,h:250},{x:1280,y:60,w:300,h:270},{x:1840,y:80,w:270,h:235},{x:2380,y:70,w:320,h:250},
{x:80,y:570,w:350,h:250},{x:710,y:570,w:300,h:240},{x:1270,y:570,w:300,h:250},{x:1840,y:570,w:270,h:245},{x:2380,y:570,w:320,h:250},
{x:80,y:1070,w:350,h:230},{x:710,y:1070,w:300,h:230},{x:1270,y:1070,w:300,h:230},{x:1840,y:1070,w:270,h:230},{x:2380,y:1070,w:320,h:230},
{x:80,y:1580,w:350,h:230},{x:710,y:1580,w:300,h:230},{x:1270,y:1580,w:300,h:230},{x:1840,y:1580,w:270,h:230},{x:2380,y:1580,w:320,h:230}
];
const traffic=[
{x:100,y:440,a:0,s:95,c:"#f06b6b"},{x:2500,y:950,a:Math.PI,s:115,c:"#69a7ff"},{x:1145,y:140,a:Math.PI/2,s:82,c:"#ffd35f"},{x:1705,y:1650,a:-Math.PI/2,s:90,c:"#d77cff"}
];
const trees=[];for(let x=470;x<W;x+=250)for(let y=330;y<H;y+=330)trees.push({x:x+Math.random()*50,y:y+Math.random()*55});
const mouse={x:0,y:0};
addEventListener("keydown",e=>{const k=e.key.toLowerCase();keys[k]=true;if(k==="e")toggleCar();if(k==="p")togglePause();if([" ","arrowup","arrowdown","arrowleft","arrowright"].includes(k))e.preventDefault()},{passive:false});
addEventListener("keyup",e=>keys[e.key.toLowerCase()]=false);
canvas.addEventListener("mousemove",e=>{const r=canvas.getBoundingClientRect();mouse.x=cam.x+(e.clientX-r.left)*canvas.width/r.width;mouse.y=cam.y+(e.clientY-r.top)*canvas.height/r.height});
document.getElementById("startBtn").onclick=()=>{started=true;document.getElementById("startOverlay").classList.add("hidden");canvas.focus()};
document.getElementById("pauseBtn").onclick=togglePause;
document.getElementById("restartBtn").onclick=()=>location.reload();
document.getElementById("fullscreenBtn").onclick=()=>{const el=document.getElementById("gameWrap");document.fullscreenElement?document.exitFullscreen():el.requestFullscreen?.()};
function togglePause(){if(!started)return;paused=!paused;document.getElementById("pauseBtn").textContent=paused?"Continuar":"Pausar"}
function toggleCar(){if(!started||paused)return;if(player.inCar){player.inCar=false;player.x=car.x+Math.cos(car.angle+Math.PI/2)*58;player.y=car.y+Math.sin(car.angle+Math.PI/2)*58}else if(Math.hypot(player.x-car.x,player.y-car.y)<82){player.inCar=true;player.x=car.x;player.y=car.y}}
function collides(x,y,r=20){if(x-r<0||y-r<0||x+r>W||y+r>H)return true;return buildings.some(b=>x+r>b.x&&x-r<b.x+b.w&&y+r>b.y&&y-r<b.y+b.h)}
function updateTraffic(dt){for(const t of traffic){t.x+=Math.cos(t.a)*t.s*dt;t.y+=Math.sin(t.a)*t.s*dt;if(t.a===0&&t.x>W+60)t.x=-60;if(t.a===Math.PI&&t.x<-60)t.x=W+60;if(t.a===Math.PI/2&&t.y>H+60)t.y=-60;if(t.a===-Math.PI/2&&t.y<-60)t.y=H+60}}
function update(dt){
 if(!started||paused)return;updateTraffic(dt);flash=Math.max(0,flash-dt*2);
 if(player.inCar){
  const throttle=(keys.w||keys.arrowup?1:0)-(keys.s||keys.arrowdown?1:0);let boost=1;
  if(keys.shift&&car.nitro>0&&throttle>0){boost=1.42;car.nitro=Math.max(0,car.nitro-31*dt)}else car.nitro=Math.min(100,car.nitro+10*dt);
  car.speed+=throttle*car.acc*boost*dt;if(!throttle)car.speed*=Math.pow(.25,dt);car.speed=Math.max(-230,Math.min(car.max*boost,car.speed));
  const steer=(keys.d||keys.arrowright?1:0)-(keys.a||keys.arrowleft?1:0);if(Math.abs(car.speed)>8)car.angle+=steer*car.turn*dt*(car.speed/car.max)*(keys[" "]?1.55:1);
  if(keys[" "])car.speed*=Math.pow(.34,dt);
  const ox=car.x,oy=car.y;car.x+=Math.cos(car.angle)*car.speed*dt;car.y+=Math.sin(car.angle)*car.speed*dt;
  if(collides(car.x,car.y,27)){car.x=ox;car.y=oy;car.speed*=-.24;car.health=Math.max(0,car.health-7);flash=.5;for(let i=0;i<10;i++)sparks.push({x:car.x,y:car.y,vx:(Math.random()-.5)*190,vy:(Math.random()-.5)*190,t:.45})}
  if((keys[" "]||Math.abs(steer)>.25)&&Math.abs(car.speed)>125)skids.push({x:car.x-Math.cos(car.angle)*25,y:car.y-Math.sin(car.angle)*25,a:car.angle,t:1});
  player.x=car.x;player.y=car.y;
 }else{
  const dx=(keys.d||keys.arrowright?1:0)-(keys.a||keys.arrowleft?1:0),dy=(keys.s||keys.arrowdown?1:0)-(keys.w||keys.arrowup?1:0),m=Math.hypot(dx,dy)||1,run=keys.shift?1.55:1;
  const nx=player.x+dx/m*player.speed*run*dt,ny=player.y+dy/m*player.speed*run*dt;if(!collides(nx,player.y,player.r))player.x=nx;if(!collides(player.x,ny,player.r))player.y=ny;
  player.angle=Math.atan2(mouse.y-player.y,mouse.x-player.x)
 }
 if(!missionDone&&Math.hypot(player.x-mission.x,player.y-mission.y)<70){missionDone=true;flash=1}
 skids.forEach(s=>s.t-=dt*.34);skids=skids.filter(s=>s.t>0);sparks.forEach(s=>{s.x+=s.vx*dt;s.y+=s.vy*dt;s.t-=dt});sparks=sparks.filter(s=>s.t>0);
 const tx=player.x-canvas.width/2,ty=player.y-canvas.height/2;cam.x+=(Math.max(0,Math.min(W-canvas.width,tx))-cam.x)*Math.min(1,dt*5.5);cam.y+=(Math.max(0,Math.min(H-canvas.height,ty))-cam.y)*Math.min(1,dt*5.5)
}
function road(){ctx.fillStyle="#263129";ctx.fillRect(0,0,W,H);ctx.fillStyle="#4b5255";for(const y of [390,900,1400])ctx.fillRect(0,y,W,100);for(const x of [535,1100,1660,2200])ctx.fillRect(x,0,90,H);ctx.strokeStyle="#d4c765";ctx.lineWidth=3;ctx.setLineDash([28,24]);ctx.beginPath();[440,950,1450].forEach(y=>{ctx.moveTo(0,y);ctx.lineTo(W,y)});[580,1145,1705,2245].forEach(x=>{ctx.moveTo(x,0);ctx.lineTo(x,H)});ctx.stroke();ctx.setLineDash([])}
function drawBuildings(){buildings.forEach((b,i)=>{ctx.fillStyle=i%3===0?"#273139":i%3===1?"#303b42":"#26343a";ctx.fillRect(b.x,b.y,b.w,b.h);ctx.strokeStyle="#52616a";ctx.lineWidth=4;ctx.strokeRect(b.x,b.y,b.w,b.h);ctx.fillStyle="#1c252a";for(let x=b.x+28;x<b.x+b.w-20;x+=67)for(let y=b.y+28;y<b.y+b.h-20;y+=58)ctx.fillRect(x,y,29,22)})}
function drawTrees(){trees.forEach(t=>{ctx.fillStyle="#342b20";ctx.fillRect(t.x-3,t.y,6,13);ctx.fillStyle="#315e3b";ctx.beginPath();ctx.arc(t.x,t.y-5,12,0,Math.PI*2);ctx.fill()})}
function drawVehicle(x,y,a,c,w=62,h=32){ctx.save();ctx.translate(x,y);ctx.rotate(a);ctx.fillStyle=c;ctx.fillRect(-w/2,-h/2,w,h);ctx.fillStyle="#17252b";ctx.fillRect(-5,-h/2+4,23,h-8);ctx.fillStyle="#eaf7ff";ctx.fillRect(w/2-6,-10,4,7);ctx.fillRect(w/2-6,3,4,7);ctx.restore()}
function drawPlayer(){if(player.inCar)return;ctx.save();ctx.translate(player.x,player.y);ctx.rotate(player.angle);ctx.fillStyle="#fff";ctx.beginPath();ctx.arc(0,0,player.r,0,Math.PI*2);ctx.fill();ctx.fillStyle="#65ff8b";ctx.fillRect(6,-3,19,6);ctx.restore()}
function drawMission(){if(missionDone)return;const p=.5+.5*Math.sin(performance.now()/260);ctx.strokeStyle="rgba(101,255,139,"+(.45+p*.45)+")";ctx.lineWidth=4;ctx.beginPath();ctx.arc(mission.x,mission.y,mission.r+p*8,0,Math.PI*2);ctx.stroke();ctx.fillStyle="#65ff8b22";ctx.beginPath();ctx.arc(mission.x,mission.y,mission.r,0,Math.PI*2);ctx.fill()}
function hud(){ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle="#061018dc";ctx.fillRect(20,20,220,74);ctx.strokeStyle="#273b49";ctx.strokeRect(20.5,20.5,219,73);ctx.fillStyle="#8ea0ad";ctx.font="700 11px system-ui";ctx.fillText(player.inCar?"VEÍCULO":"STATUS",35,43);ctx.fillStyle="#fff";ctx.font="900 25px system-ui";ctx.fillText(player.inCar?Math.round(Math.abs(car.speed)*.22)+" km/h":"A PÉ",35,72);
 const rx=canvas.width-248;ctx.fillStyle="#061018dc";ctx.fillRect(rx,20,228,110);ctx.fillStyle="#fff";ctx.font="800 12px system-ui";ctx.fillText("INTEGRIDADE",rx+16,43);ctx.fillStyle="#263640";ctx.fillRect(rx+16,53,196,9);ctx.fillStyle=car.health>40?"#65ff8b":"#e66";ctx.fillRect(rx+16,53,196*car.health/100,9);ctx.fillStyle="#fff";ctx.fillText("NITRO",rx+16,83);ctx.fillStyle="#263640";ctx.fillRect(rx+16,92,196,9);ctx.fillStyle="#24d9ff";ctx.fillRect(rx+16,92,196*car.nitro/100,9);
 const mw=190,mh=120,mx=canvas.width-210,my=canvas.height-140;ctx.fillStyle="#061018e8";ctx.fillRect(mx,my,mw,mh);ctx.fillStyle="#344048";buildings.forEach(b=>ctx.fillRect(mx+b.x/W*mw,my+b.y/H*mh,b.w/W*mw,b.h/H*mh));if(!missionDone){ctx.fillStyle="#ffd65b";ctx.beginPath();ctx.arc(mx+mission.x/W*mw,my+mission.y/H*mh,4,0,Math.PI*2);ctx.fill()}ctx.fillStyle="#65ff8b";ctx.beginPath();ctx.arc(mx+player.x/W*mw,my+player.y/H*mh,4.5,0,Math.PI*2);ctx.fill();
 const near=!player.inCar&&Math.hypot(player.x-car.x,player.y-car.y)<82;if(near){ctx.fillStyle="#081119e8";ctx.fillRect(canvas.width/2-105,canvas.height-93,210,38);ctx.fillStyle="#dfffe6";ctx.font="900 13px system-ui";ctx.fillText("E  ENTRAR NO VEÍCULO",canvas.width/2-83,canvas.height-68)}
 if(paused){ctx.fillStyle="#030609aa";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle="#fff";ctx.textAlign="center";ctx.font="900 44px system-ui";ctx.fillText("PAUSADO",canvas.width/2,canvas.height/2);ctx.textAlign="left"}
 if(flash>0){ctx.fillStyle="rgba(255,90,90,"+Math.min(.28,flash*.2)+")";ctx.fillRect(0,0,canvas.width,canvas.height)}
}
function render(){ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,canvas.width,canvas.height);ctx.save();ctx.translate(-cam.x,-cam.y);road();drawBuildings();drawTrees();drawMission();for(const s of skids){ctx.globalAlpha=Math.max(0,s.t*.4);ctx.save();ctx.translate(s.x,s.y);ctx.rotate(s.a);ctx.fillStyle="#090a0b";ctx.fillRect(-18,-12,36,3);ctx.fillRect(-18,9,36,3);ctx.restore()}ctx.globalAlpha=1;traffic.forEach(t=>drawVehicle(t.x,t.y,t.a,t.c,54,27));drawVehicle(car.x,car.y,car.angle,car.health>40?"#65ff8b":"#d86770");drawPlayer();sparks.forEach(s=>{ctx.fillStyle="#ffd76b";ctx.fillRect(s.x,s.y,3,3)});ctx.restore();hud()}
let last=performance.now();function loop(t){const dt=Math.min(.033,(t-last)/1000);last=t;update(dt);render();requestAnimationFrame(loop)}requestAnimationFrame(loop);
for(const btn of document.querySelectorAll("[data-key]")){const k=btn.dataset.key;const down=e=>{e.preventDefault();keys[k]=true},up=e=>{e.preventDefault();keys[k]=false};btn.addEventListener("pointerdown",down);btn.addEventListener("pointerup",up);btn.addEventListener("pointercancel",up);btn.addEventListener("pointerleave",up)}
for(const btn of document.querySelectorAll('[data-action="e"]'))btn.addEventListener("click",toggleCar);