const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('public/game.js','utf8');
const projection=source.slice(source.indexOf('const VIEW_TILT='),source.indexOf('const keys='));
const context={window:{},canvas:{width:1200,height:700},player:{x:480,y:440,weapon:'pistol'},cam:{x:480,y:440}};
vm.createContext(context);vm.runInContext(projection,context);
vm.runInContext(`globalThis.api={projectVector,unprojectVector,screenToWorldPoint,worldToScreenX,worldToScreenY,screenAlignedInput,buildingHeight,undoProjection}`,context);
const p=context.api,near=(a,b)=>assert(Math.abs(a-b)<1e-8,`${a} != ${b}`);
// Both street axes must form a 2:1 diamond with opposite horizontal slopes.
near(p.projectVector(100,0).x,84);near(p.projectVector(100,0).y,42);
near(p.projectVector(0,100).x,-84);near(p.projectVector(0,100).y,42);
for(const weapon of ['pistol','rifle']){
 context.player.weapon=weapon;
 for(const [x,y] of [[0,0],[480,440],[2800,1900],[-50,200],[1278,1061]]){
  const q=p.screenToWorldPoint(p.worldToScreenX(x,y),p.worldToScreenY(y,x));near(q.x,x);near(q.y,y);
 }
}
// PC and analog input must travel toward the screen direction, with equal world speed.
for(const [x,y] of [[1,0],[0,1],[-1,0],[0,-1],[1,1],[-1,-1],[.2,.1]]){
 const v=p.screenAlignedInput(x,y),screen=p.projectVector(v.x,v.y);
 near(screen.x*y-screen.y*x,0);assert(screen.x*x+screen.y*y>0);
 near(Math.hypot(v.x,v.y),Math.min(1,Math.hypot(x,y)));
}
// Upright sprites cancel the projection and roof height only changes screen Y.
let inv;p.undoProjection({transform(...v){inv=v}});
for(const [x,y] of [[1,0],[0,1],[15,-40]]){
 const q=p.projectVector(inv[0]*x+inv[2]*y,inv[1]*x+inv[3]*y);near(q.x,x);near(q.y,y);
}
const h=p.buildingHeight(3),lift=p.projectVector(...Object.values(p.unprojectVector(0,-h)));near(lift.x,0);near(lift.y,-h);
console.log('Isometric street geometry, pointer round trips, zoom, eight input directions, sprite proportions and roof elevation passed.');
// Existing ladder-only roof access and wall collisions must survive the new input basis.
context.W=2800;context.H=1900;context.playSound=()=>{};
const movement=source.slice(source.indexOf('const buildings='),source.indexOf('const traffic='));
vm.runInContext(movement+'\n'+source.match(/function collides\([^\n]+/)[0]+'\nglobalThis.move=tryRoofMovement;globalThis.blocked=collides;',context);
Object.assign(context.player,{x:95,y:350,r:16,speed:190,roof:null});
for(let i=0;i<100;i++)context.move(0,-1,.033,1);
assert.equal(context.player.roof,null);assert(context.player.y>=326);assert(!context.blocked(context.player.x,context.player.y,16));
Object.assign(context.player,{x:260,y:340,roof:null});context.move(0,-1,.033,1);assert.equal(context.player.roof,0);
context.move(0,1,.033,1);assert.equal(context.player.roof,null);assert(context.player.y>310);
console.log('Wall collision and ladder-only rooftop entry/exit passed.');
