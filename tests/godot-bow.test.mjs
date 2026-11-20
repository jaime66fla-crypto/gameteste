import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { HitCheck } from '../src/godot-hitcheck.js';
import { GodotMatch } from '../src/godot-match.js';
import { GodotSurvival } from '../src/godot-survival.js';
const catalog=JSON.parse(readFileSync(new URL('../godot/data/survival_items.json',import.meta.url)));
const shot={t:'shot',w:'bow',o:[0,1.6,0],e:[40,1.6,0],v:[40,0,0],a:'arrow-1'};
const hit={t:'hit',w:'bow',target:'target',zone:'chest',pt:[10,1.29375,0],a:'arrow-1'};
function fixture(Class) {
 const room=Object.create(Class.prototype), me={id:'archer',p:[0,0,0],inv:{bow:1,stone_arrow:1},credits:1000,buyUntil:Infinity}, target={id:'target',p:[10,0,0],hp:100};
 Object.assign(room,{hitCheck:new HitCheck(),hitLog:new Map(),sessions:new Map(),events:[]});
 room.match={phase:'running',host:me.id,players:{archer:me,target},mode:'dm'};
 room.state={host:me.id,players:{archer:me,target},zombies:{},animals:{}};
 room.broadcast=room.broadcastNear=(...args)=>room.events.push(args);
 room.save=room.sendInv=()=>{};
 room.damage=(a,b,n)=>b.hp-=n; room.applyHit=(a,id,n)=>room.state.players[id].hp-=n;
 const ws={deserializeAttachment:()=>({id:me.id})};
 return {room,me,target,say:d=>room.webSocketMessage(ws,JSON.stringify(d))};
}
test('ballistic launch rejects invalid speed, distant origin, duplicate ids and rapid releases',()=>{
 const hc=new HitCheck(),a={id:'a',p:[0,0,0]}; assert.equal(typeof hc.recordArrow,'function');
 const launch=(id,now,origin=shot.o,velocity=shot.v)=>hc.recordArrow({attacker:a,id,origin,velocity,now});
 assert.equal(launch('fast',1000,shot.o,[80,0,0]),false);
 assert.equal(launch('far',1000,[20,1,0]),false);
 assert.equal(launch('first',1000),true);
 assert.equal(launch('rapid',1050),false);
 assert.equal(launch('first',1500),false);
 const args={attacker:a,target:{p:[10,0,0]},id:'first',point:hit.pt,zone:'chest',now:1250};
 assert.equal(hc.checkArrow({...args,attacker:{...a,id:'thief'}}).ok,false);
 assert.equal(hc.checkArrow({...args,point:[10,8,0]}).ok,false);
 assert.equal(hc.checkArrow({...args,now:1000}).ok,false);
 assert.equal(hc.checkArrow(args).ok,true);
 assert.equal(hc.checkArrow(args).ok,false);
 assert.equal(launch('expired',2000),true);
 assert.equal(hc.checkArrow({...args,id:'expired',now:11000}).ok,false);
 hc.reset();assert.equal(launch('first',1000),true);
});
for(const [Class,label] of [[GodotMatch,'match'],[GodotSurvival,'survival']]) {
 test(`${label}: bow broadcasts velocity and deals one authoritative impact`,t=>{
  let now=1000;t.mock.method(Date,'now',()=>now);const f=fixture(Class);
  f.say(hit);assert.equal(f.target.hp,100);
  f.say(shot);assert.ok(f.room.events.some(args=>args.some(v=>v?.t==='shot'&&v.a===shot.a&&v.v?.[0]===40)));
  if(Class===GodotSurvival){f.say({t:'consume',ammo:'stone_arrow',n:1});assert.equal(f.me.inv.stone_arrow,undefined);}
  now=1250;f.say(hit);assert.equal(f.target.hp,45);f.say(hit);assert.equal(f.target.hp,45);
 });
 test(`${label}: unowned bow cannot launch`,()=>{const f=fixture(Class);delete f.me.inv.bow;f.say(shot);assert.equal(f.room.events.length,0);});
}
test('survival bow and arrows have enabled usable crafting recipes',()=>{
 assert.equal(catalog.items.bow.weapon,'bow');assert.equal(catalog.items.bow.ammo,'stone_arrow');
 for(const id of ['bow','stone_arrow']){assert.ok(!catalog.items[id].soon);assert.ok(!catalog.recipes.find(r=>r.id===id).soon);}
});
test('shop grants bow with twenty arrows and charges credits',()=>{
 const {room,me}=fixture(GodotMatch);room.hasShop=()=>true;delete me.inv.bow;room.buy(me,'bow',{});
 assert.equal(me.credits,400);assert.equal(me.inv.bow,true);assert.ok(room.events.some(args=>args[0]?.t==='bought'&&args[0].ammo===20));
});
for(const [Class,label] of [[GodotMatch,'match'],[GodotSurvival,'survival']]) {
 test(`${label}: bow draw state forwards sanitized pose and charge`,()=>{
  const f=fixture(Class); f.say({t:'s',p:[0,0,0],w:'bow',act:'bow_draw',tool:'bow',charge:0.65});
  const state=f.room.events.flat().find(v=>v?.t==='s');
  assert.equal(state.act,'bow_draw');assert.equal(state.tool,'bow');assert.equal(state.charge,0.65);
  f.say({t:'s',p:[0,0,0],w:'bow',act:'bow_carry',tool:'bow',charge:8});
  assert.equal(f.room.events.at(-1).find(v=>v?.t==='s').charge,1);
 });
}
test('bow follows gravity from recorded release even after archer moves',()=>{
 const hc=new HitCheck(),attacker={id:'a',p:[0,0,0]};
 hc.recordArrow({attacker,id:'arc',origin:[0,1.6,0],velocity:[40,0,0],now:1000});
 attacker.p=[-100,0,0];
 assert.equal(hc.checkArrow({attacker,target:{p:[40,-4,0]},id:'arc',point:[40,-3.3,0],zone:'chest',now:2000}).ok,true);
});
test('survival bow damages zombies and animals through the same validated flight',t=>{
 let now=1000;t.mock.method(Date,'now',()=>now);const f=fixture(GodotSurvival);
 f.room.applyHit=GodotSurvival.prototype.applyHit;
 f.room.state.zombies.zed={id:'zed',p:[10,0,0],hp:100};
 f.say(shot);now=1250;f.say({...hit,target:'zed'});assert.equal(f.room.state.zombies.zed.hp,45);
 now=1600;f.room.state.animals.deer={id:'deer',p:[10,0,0],hp:100};
 f.say({...shot,a:'arrow-2'});now=1850;f.say({...hit,target:'deer',a:'arrow-2'});assert.equal(f.room.state.animals.deer.hp,45);
});
