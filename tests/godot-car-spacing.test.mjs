import test from 'node:test';
import assert from 'node:assert/strict';
import world from '../godot/data/survival_world.json' with {type:'json'};
test('parked wrecks and drivable cars have clearance for the largest car model',()=>{
 const cars=[...world.vehicles,...world.resources.filter(r=>r.kind==='car')];
 for(let i=0;i<cars.length;i++)for(let j=i+1;j<cars.length;j++){
  const a=cars[i],b=cars[j];const distance=Math.hypot(a.p[0]-b.p[0],a.p[2]-b.p[2]);
  assert.ok(distance>=6,`${a.id} overlaps ${b.id}: only ${distance.toFixed(2)} m between centers`);
 }
});
