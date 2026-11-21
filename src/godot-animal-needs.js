import world from '../godot/data/survival_world.json' with { type: 'json' };
import catalog from '../godot/data/survival_items.json' with { type: 'json' };
import { terrainHeight } from './godot-terrain.js';
import { treeSeed, branchSpot } from './godot-tree-branches.js';

const RULES = catalog.animal_needs;
const FOOD = catalog.animal_food;
const TREES = world.resources.filter((r) => r.kind === 'tree');
const clamp = (n, fallback) => Number.isFinite(n) ? Math.max(0, Math.min(100, n)) : fallback;
const round = (n) => Math.round(n * 10) / 10;
const flat = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);

export function ensureAnimalNeeds(animal, now = Date.now()) {
 animal.hunger = clamp(animal.hunger, RULES.initial_hunger);
 animal.thirst = clamp(animal.thirst, RULES.initial_thirst);
 if (!Number.isFinite(animal.needsAt)) animal.needsAt = now;
 return animal;
}

export function animalSnapshot(animal, now = Date.now()) {
 ensureAnimalNeeds(animal, now);
 return {id:animal.id,kind:animal.kind,hp:animal.hp,p:animal.p,hunger:round(animal.hunger),thirst:round(animal.thirst),fed:Math.max(0,((animal.fedUntil||0)-now)/1000)};
}

export function tickAnimalNeeds(room, now = Date.now()) {
 const changed=[];
 for(const animal of Object.values(room.state.animals||{})) {
  ensureAnimalNeeds(animal,now);
  const dt=Math.max(0,Math.min(RULES.max_tick_seconds,(now-animal.needsAt)/1000));
  animal.needsAt=now;
  animal.hunger=Math.max(0,animal.hunger-RULES.hunger_per_second*dt);
  animal.thirst=Math.max(0,animal.thirst-RULES.thirst_per_second*dt);
  if(dt>0&&(animal.hunger===0||animal.thirst===0)) animal.hp=Math.max(0,animal.hp-RULES.starve_per_second*dt);
  if(animal.hp<=0){
   delete room.state.animals[animal.id];
   room.broadcast({t:'adead',id:animal.id,by:'nature',zone:'chest'});
  } else changed.push(animalSnapshot(animal,now));
 }
 if(changed.length) room.broadcast({t:'aneeds',l:changed});
}

export function treeFruit(tree) {
 const seed=treeSeed(tree);
 if(seed%FOOD.apple_mod===FOOD.apple_remainder)return 'apple';
 return FOOD.oak_variants.includes(seed%5)?'acorn':'';
}

export function dropTreeFruit(room,now=Date.now()) {
 const s=room.state;s.fruits||={};s.fruitNext||={};
 for(const fruit of Object.values(s.fruits))if(fruit.expires<=now){delete s.fruits[fruit.id];room.broadcast({t:'fruit_gone',id:fruit.id});}
 const anchors=[...room.living(),...Object.values(s.animals||{})];
 let available=FOOD.limit-Object.keys(s.fruits).length;
 let born=0;
 for(const tree of TREES){
  if(available<=0||born>=FOOD.batch)break;
  const kind=treeFruit(tree);
  if(!kind||(s.depleted[tree.id]||0)>now||!anchors.some(a=>flat(a.p,tree.p)<FOOD.active_range))continue;
  const id='fruit_'+tree.id;
  if(s.fruits[id])continue;
  s.fruitNext[tree.id]??=now+(treeSeed(tree)%8)*1500;
  if(s.fruitNext[tree.id]>now)continue;
  const p=branchSpot(tree,now+35000);
  if(!p||room.branchBlocked(p)){s.fruitNext[tree.id]=now+10000;continue;}
  p[1]=round(terrainHeight(p[0],p[2])+.08);
  const fruit={id,kind,tree:tree.id,p,expires:now+FOOD.lifetime_ms};
  s.fruits[id]=fruit;s.fruitNext[tree.id]=now+FOOD.regrow_ms;
  available--;born++;room.broadcast({t:'fruit',r:fruit});
 }
}

function sourceAt(room,animal,id,now) {
 if(typeof id!=='string')return null;
 if(/^water:\d+$/.test(id)){
  const pond=world.ponds[Number(id.slice(6))];
  if(!pond||animal.thirst>RULES.thirst_threshold)return null;
  return {type:'water',p:[pond.x,0,pond.z],radius:pond.r+1.5,seconds:RULES.drink_seconds};
 }
 const diet=catalog.animals[animal.kind]?.food;
 if(animal.hunger>RULES.hunger_threshold)return null;
 if(/^grass:\d+$/.test(id)){
  const patch=world.grass[Number(id.slice(6))];
  if(diet!=='grass'||!patch)return null;
  return {type:'grass',p:[patch.x,terrainHeight(animal.p[0],animal.p[2]),patch.z],radius:patch.r,seconds:RULES.eat_seconds};
 }
 const fruit=Object.hasOwn(room.state.fruits||{},id)?room.state.fruits[id]:null;
 if(!fruit||fruit.expires<=now||fruit.kind!==diet)return null;
 return {type:fruit.kind,p:fruit.p,radius:1.8,seconds:RULES.eat_seconds,fruit};
}

export function animalForage(room,d,now=Date.now()) {
 const animal=Object.hasOwn(room.state.animals||{},d.a)?room.state.animals[d.a]:null;
 if(!animal||animal.hp<=0)return;
 ensureAnimalNeeds(animal,now);
 const source=sourceAt(room,animal,d.source,now);
 if(!source||flat(animal.p,source.p)>source.radius||Math.abs(animal.p[1]-source.p[1])>2.5)return;
 if(d.phase==='start'){
  animal.forageSource=d.source;animal.forageAt=now;return;
 }
 if(d.phase!=='finish'||animal.forageSource!==d.source)return;
 const waited=now-(animal.forageAt||0);
 if(waited<source.seconds*1000-100||waited>source.seconds*1000+6000)return;
 animal.forageSource='';animal.forageAt=0;
 if(source.type==='water')animal.thirst=Math.min(100,animal.thirst+RULES.drink_restore);
 else animal.hunger=Math.min(100,animal.hunger+RULES.food_restore);
 if(source.fruit){delete room.state.fruits[d.source];room.broadcast({t:'fruit_gone',id:d.source});}
 room.broadcast({t:'aneeds',l:[animalSnapshot(animal,now)]});
 room.save();
}
