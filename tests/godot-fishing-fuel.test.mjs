import test from 'node:test';
import assert from 'node:assert/strict';
import { GodotSurvival } from '../src/godot-survival.js';
const make = () => {
 const g = Object.create(GodotSurvival.prototype);
 g.state = {createdAt:Date.now(),vehicles:{}};
 g.sent=[]; g.sendTo=(_,m)=>g.sent.push(m); g.sendInv=()=>{}; g.save=()=>{}; g.broadcast=()=>{};g.broadcastNear=()=>{};
 return g;
};
test('fishing rejects invalid casts and consumes each hook attempt',()=>{
 const g=make(), p={id:'p',p:[0,0,0],inv:{}};
 g.startFishing(p,{p:[0,0,0]},()=>{}); assert.equal(p.fishing,undefined);
 p.inv.fishing_rod=1;
 g.startFishing(p,{p:[100,0,100]},()=>{});assert.equal(p.fishing,undefined);
 p.fishing={origin:[0,0,0],p:[0,0,0],biteAt:Date.now()+5000};
 g.hookFishing(p,()=>{});assert.equal(p.fishing,undefined);assert.equal(p.inv.raw_fish,undefined);
});
test('fishing rewards once during bite; capacity, movement and late hooks fail',()=>{
 const g=make(), p={id:'p',p:[0,0,0],inv:{fishing_rod:1}};
 // A known river point is located using hydrology so validation remains real.
 return import('../src/godot-hydrology.js').then(({waterAt})=>{
 let target;for(let x=-100;x<100&&!target;x++)for(let z=-100;z<100;z++)if(waterAt(x,z)){target=[x,waterAt(x,z).surface,z];break;}
 p.p=[...target];
 g.startFishing(p,{p:target},()=>{});assert.ok(p.fishing);
 p.fishing.biteAt=Date.now()-10;g.hookFishing(p,()=>{});
 assert.equal(Object.values(p.inv).reduce((a,b)=>a+b,0),2);g.hookFishing(p,()=>{});assert.equal(Object.values(p.inv).reduce((a,b)=>a+b,0),2);
 for(const mode of ['late','moved','full','dead','vehicle','rod']){
 p.inv={fishing_rod:1};p.dead=false;p.vehicle='';p.p=[...target];g.startFishing(p,{p:target},()=>{});assert.ok(p.fishing);
 p.fishing.biteAt=Date.now()-(mode==='late'?3000:10);
 if(mode==='moved')p.p[0]+=2;if(mode==='full')p.inv.stone=100;if(mode==='dead')p.dead=true;if(mode==='vehicle')p.vehicle='v';if(mode==='rod')delete p.inv.fishing_rod;
 g.hookFishing(p,()=>{});assert.equal(p.fishing,undefined);assert.equal(Object.keys(p.inv).filter(k=>!['fishing_rod','stone'].includes(k)).length,0);
 }
 });
});
test('fuel consumes configured liters over cumulative kilometer, remains still and caps refill',()=>{
 for(const [kind,rate] of [['sedan',.14],['pickup',.18],['hatch',.11]]){
 const g=make(),p={id:'p',vehicle:'v',p:[0,0,0],inv:{gasoline:2}},v={id:'v',kind,driver:'p',p:[0,0,0],fuel:100,hp:100};g.state.vehicles.v=v;
 g.driveVehicle(p,{v:'v',p:[0,0,0]});assert.equal(v.fuel,100);
 for(let n=1;n<=100;n++)g.driveVehicle(p,{v:'v',p:[n*10,0,0]});assert.ok(Math.abs(v.fuel-(100-rate))<1e-9);
 const before=v.fuel;g.driveVehicle(p,{v:'v',p:[2000,0,0]});assert.equal(v.fuel,before);
 v.fuel=0;g.driveVehicle(p,{v:'v',p:[1001,0,0]});assert.deepEqual(v.p,[1000,0,0]);
 v.fuel=99.5;g.refuel(p,{v:'v'},()=>{});assert.equal(v.fuel,100);assert.equal(p.inv.gasoline,1);
 }
});

test('fishing allows bounded delivery grace while keeping advertised bite window', async()=>{
 const {waterAt}=await import('../src/godot-hydrology.js');
 const g=make();let target;
 for(let x=-100;x<100&&!target;x++)for(let z=-100;z<100;z++)if(waterAt(x,z)){target=[x,waterAt(x,z).surface,z];break;}
 const p={id:'p',p:target,inv:{fishing_rod:1}};
 const realNow=Date.now;Date.now=()=>100000;
 try {
  g.startFishing(p,{p:target},()=>{});
  assert.equal(g.sent.at(-1).window_ms,1800);
  p.fishing.biteAt=100000-2150;
  g.hookFishing(p,()=>{});
  assert.equal(Object.values(p.inv).reduce((a,b)=>a+b,0),2);
  p.inv={fishing_rod:1};g.startFishing(p,{p:target},()=>{});
  p.fishing.biteAt=100000-2151;
  g.hookFishing(p,()=>{});
  assert.deepEqual(p.inv,{fishing_rod:1});
  assert.equal(p.fishing,undefined);
 } finally {Date.now=realNow;}
});

test("rod crafts once from exact materials and equipped armor returns without duplication",()=>{const g=make(),p={id:"p",p:[0,0,0],inv:{stick:3,fiber:4,rope:2},back:"",head:"leather_cap"};g.craft(p,{recipe:"fishing_rod"},()=>{});assert.equal(p.inv.fishing_rod,1);assert.equal(p.inv.rope,undefined);g.craft(p,{recipe:"fishing_rod"},()=>{});assert.equal(p.inv.fishing_rod,1);g.unequip(p,{slot:"head"},()=>{});g.unequip(p,{slot:"head"},()=>{});assert.equal(p.head,"");assert.equal(p.inv.leather_cap,1);});
