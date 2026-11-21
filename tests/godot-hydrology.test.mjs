import test from 'node:test';
import assert from 'node:assert/strict';
import { weatherAt, waterAt, basinState, riverSample, coastHeight } from '../src/godot-hydrology.js';
import { terrainHeight } from '../src/godot-terrain.js';
import world from '../godot/data/survival_world.json' with {type:'json'};
import { GodotSurvival } from '../src/godot-survival.js';
test('rain fills watercourses and temporary lakes, then dry weather drains them',()=>{
 const dry=weatherAt(0),storm=weatherAt(240000),flood=weatherAt(360000),drained=weatherAt(719999);
 assert.equal(dry.rain,0);assert.ok(storm.rain>.8);assert.ok(flood.wet>.9);assert.ok(drained.wet<.001);
 const basin=world.hydrology.floodplains[0];
 assert.equal(basinState(basin,0).radius,0);assert.ok(basinState(basin,flood.wet).radius>10);
 const [x,z]=world.hydrology.river.points[4];
 assert.ok(waterAt(x,z,1).surface>waterAt(x,z,0).surface);
 assert.ok(terrainHeight(x,z)<waterAt(x,z,0).surface-.4);
});
test('island slopes to a saltwater ocean outside the old map boundary',()=>{
 for(const [x,z] of [[490,0],[-490,0],[0,490],[0,-490],[480,480]]){
  assert.ok(coastHeight(x,z)<-1.1);assert.equal(waterAt(x,z,0).fresh,false);
 }
 assert.equal(waterAt(0,300,0),null);
 assert.ok(riverSample(85,-40).distance<.001);
});
test('weather is stable across reload and bounded for long lived worlds',()=>{
 for(let t=0;t<864000000;t+=137861){const a=weatherAt(t);assert.deepEqual(a,weatherAt(t));assert.ok(a.rain>=0&&a.rain<=1&&a.wet>=0&&a.wet<=1);}
});
test('server shares weather with joining clients, permits sea travel and only drinks fresh water',()=>{
 const ctx={storage:{get:async()=>null,put:async()=>{}},blockConcurrencyWhile:fn=>fn(),getWebSockets:()=>[],waitUntil:()=>{}};
 const room=new GodotSurvival(ctx,{});room.save=()=>{};room.sendStats=()=>{};room.broadcastNear=()=>{};
 room.state.createdAt=Date.now()-240000;
 assert.ok(room.clock().weather.rain>.8);
 const me={id:'me',p:[85,-1,-40],inv:{},thirst:30,dead:false};room.state.players.me=me;
 const socket={deserializeAttachment:()=>({id:'me'}),send:()=>{}};
 room.webSocketMessage(socket,JSON.stringify({t:'drink_water'}));assert.equal(me.thirst,50);
 room.webSocketMessage(socket,JSON.stringify({t:'drink_water'}));assert.equal(me.thirst,50,'drinking rate is limited');
 me.lastDrink=0;me.p=[490,-2,0];room.webSocketMessage(socket,JSON.stringify({t:'drink_water'}));assert.equal(me.thirst,50,'saltwater is not drinkable');
 room.webSocketMessage(socket,JSON.stringify({t:'s',p:[800,-2,0]}));assert.equal(me.p[0],800,'sea travel is not clipped to the old world');
 assert.equal(waterAt(490,310,1).fresh,false,'river becomes saltwater at its ocean mouth');
});
