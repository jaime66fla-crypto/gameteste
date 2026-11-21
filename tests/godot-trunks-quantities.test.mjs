import test from 'node:test';
import assert from 'node:assert/strict';
import { GodotSurvival, carryLimit, inventoryWeight } from '../src/godot-survival.js';
function setup() {
 const saved = new Map();
 const room = new GodotSurvival({ storage: {get:async()=>null,put:async(k,v)=>saved.set(k,structuredClone(v))},blockConcurrencyWhile:fn=>fn(),getWebSockets:()=>[],waitUntil:()=>{} },{});
 room.broadcast=()=>{};room.sendInv=()=>{};room.save=()=>saved.set('world',structuredClone(room.state));
 const me={id:'test',inv:{wood:40,stone:20},p:[0,0,0],back:''};
 return {room,me,saved};
}
test('trunk stores exact quantities, persists items and blocks distant or occupied access',()=>{
 const {room,me,saved}=setup();const v=Object.values(room.vehicles())[0];me.p=[...v.p];const k='trunk:'+v.id;
 let confirmed;room.sendTo=(_id,data)=>confirmed=data;room.sendInv=GodotSurvival.prototype.sendInv;
 let packet;const reply=p=>packet=p;const note=()=>{};
 room.search(me,{k},reply,note);assert.equal(packet?.store,true);
 room.store(me,{k,item:'wood',n:12,op:'stack1'},reply,note);assert.equal(v.items.wood,12);assert.equal(me.inv.wood,28);assert.equal(confirmed.op,'stack1');
 room.take(me,{k,item:'wood',n:5},reply,note);assert.equal(v.items.wood,7);assert.equal(me.inv.wood,33);
 assert.equal(saved.get('world').vehicles[v.id].items.wood,7);
 me.p=[v.p[0]+50,v.p[1],v.p[2]];room.take(me,{k,item:'wood',n:2},reply,note);assert.equal(v.items.wood,7);
 me.p=[...v.p];v.driver='other';room.store(me,{k,item:'wood',n:3},reply,note);assert.equal(v.items.wood,7);
 v.driver=null;v.items={wood:179};room.store(me,{k,item:'wood',n:10},reply,note);assert.equal(v.items.wood,180);assert.equal(me.inv.wood,32);
});
test('invalid explicit quantity never discards the full stack',()=>{
 const {room,me}=setup();
 for(const n of [0,-2,1.5,'3',null]) room.drop(me,{item:'wood',n},()=>{});
 assert.equal(me.inv.wood,40);
 room.drop(me,{item:'wood',n:3},()=>{});assert.equal(me.inv.wood,37);
});
test('base capacity allows a useful building supply run with tools',()=>{
 assert.equal(carryLimit(''),60);
 assert.ok(inventoryWeight({wood:35,stone:30,stone_axe:1,stone_pick:1})<carryLimit(''));
});
