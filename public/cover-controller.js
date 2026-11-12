/* Straight-wall cover. Exposure moves the real body; there is no immunity flag. */
(() => {
'use strict';
class CoverController {
 constructor({player,boxes,terrainHeight=()=>0}){
  Object.assign(this,{player,boxes,terrainHeight});
  this.active=false;this.surface=null;this.anchor=new THREE.Vector3();
  this.side=1;this.low=false;this.isPeeking=false;this.peekBlend=0;this.speed=0;
  this.wallOffset=.5;this.margin=.48;this.acquireRange=1.2;
 }
 get canShoot(){return !this.active||(this.isPeeking&&this.peekBlend>.92);}
 canFireFrom(point){
  if(!this.canShoot)return false;
  return !this.active||!this.boxes().some(b=>point.x>=b.minX-.01&&point.x<=b.maxX+.01&&point.y>=b.minY-.01&&point.y<=b.maxY+.01&&point.z>=b.minZ-.01&&point.z<=b.maxZ+.01);
 }
 blocked(point){
  const foot=this.terrainHeight(point.x,point.z);
  return this.boxes().some(b=>point.x+.43>b.minX&&point.x-.43<b.maxX&&point.z+.43>b.minZ&&point.z-.43<b.maxZ&&b.maxY>foot+.1&&b.minY<foot+1.8);
 }
 clearPath(from,to){
  const count=Math.max(1,Math.ceil(from.distanceTo(to)/.12));
  for(let i=1;i<=count;i++){if(this.blocked(from.clone().lerp(to,i/count)))return false;}
  return true;
 }
 findNearby(){
  const p=this.player.position;let best=null;
  for(const box of this.boxes()){
   if(box.minY>p.y+.4||box.maxY-p.y<.95)continue;
   const faces=[
    {normal:new THREE.Vector3(0,0,1),axis:'x',planeAxis:'z',plane:box.maxZ,min:box.minX,max:box.maxX},
    {normal:new THREE.Vector3(0,0,-1),axis:'x',planeAxis:'z',plane:box.minZ,min:box.minX,max:box.maxX},
    {normal:new THREE.Vector3(1,0,0),axis:'z',planeAxis:'x',plane:box.maxX,min:box.minZ,max:box.maxZ},
    {normal:new THREE.Vector3(-1,0,0),axis:'z',planeAxis:'x',plane:box.minX,min:box.minZ,max:box.maxZ}
   ];
   for(const face of faces){
    if(face.max-face.min<1.1)continue;
    // Only approach a face from its outside; never snap through the wall.
    if((p[face.planeAxis]-face.plane)*face.normal[face.planeAxis]<.1)continue;
    const point=p.clone();point[face.axis]=THREE.MathUtils.clamp(p[face.axis],face.min+this.margin,face.max-this.margin);
    point[face.planeAxis]=face.plane+face.normal[face.planeAxis]*this.wallOffset;
    point.y=this.terrainHeight(point.x,point.z);
    const distance=p.distanceTo(point);
    if(distance>this.acquireRange||best&&distance>=best.distance||!this.clearPath(p,point))continue;
    best={...face,box,point,distance,tangent:new THREE.Vector3(face.normal.z,0,-face.normal.x)};
   }
  }
  return best;
 }
 toggle(){
  if(this.active){this.exit();return true;}
  const surface=this.findNearby();if(!surface)return false;
  this.active=true;this.surface=surface;this.anchor.copy(surface.point);this.player.position.copy(this.anchor);
  this.low=surface.box.maxY-this.anchor.y<1.35;this.side=1;this.peekBlend=0;this.isPeeking=false;
  return true;
 }
 exit(){this.active=false;this.surface=null;this.low=false;this.isPeeking=false;this.peekBlend=0;this.speed=0;}
 facingYaw(aimYaw){
  if(!this.active||this.isPeeking)return aimYaw;
  const direction=this.surface.tangent.clone().multiplyScalar(this.side).addScaledVector(this.surface.normal,.35);
  return Math.atan2(direction.x,direction.z);
 }
 shoulderSign(yaw){
  if(!this.active||this.low)return 1;
  const right=new THREE.Vector3(Math.cos(yaw),0,-Math.sin(yaw));
  return this.surface.tangent.dot(right)*this.side>=0?1:-1;
 }
 update(dt,{left=false,right=false,backward=false,aiming=false,grounded=true,canStand=true}={}){
  this.speed=0;if(!this.active)return;
  if(!grounded||backward||!this.boxes().includes(this.surface.box)){this.exit();return;}
  const face=this.surface;
  if(!aiming&&this.peekBlend<.02){
   const direction=Number(right)-Number(left);
   if(direction){
    this.side=direction;
    const next=this.anchor.clone().addScaledVector(face.tangent,direction*2*dt);
    next[face.axis]=THREE.MathUtils.clamp(next[face.axis],face.min+this.margin,face.max-this.margin);
    next.y=this.terrainHeight(next.x,next.z);
    if(this.clearPath(this.anchor,next)){this.speed=dt>0?next.distanceTo(this.anchor)/dt:0;this.anchor.copy(next);}
   }
  }
  const peek=this.anchor.clone(),corner=this.anchor.clone();let allowed=false;
  if(this.low){allowed=canStand;}
  else{
   const toMin=this.anchor[face.axis]-(face.min+this.margin),toMax=(face.max-this.margin)-this.anchor[face.axis];
   if(Math.min(toMin,toMax)<.7){
    const endSign=toMax<=toMin?1:-1;
    this.side=endSign/face.tangent[face.axis];
    corner[face.axis]=endSign>0?face.max+.55:face.min-.55;
    peek.copy(corner).addScaledVector(face.normal,-.65);
    allowed=this.clearPath(this.anchor,corner)&&this.clearPath(corner,peek);
   }
  }
  this.isPeeking=Boolean(aiming&&allowed);
  this.peekBlend=THREE.MathUtils.lerp(this.peekBlend,this.isPeeking?1:0,1-Math.exp(-12*dt));
  // Clear the edge before stepping forward; retract in the reverse order.
  if(!this.low&&this.peekBlend>.65)this.player.position.copy(corner).lerp(peek,(this.peekBlend-.65)/.35);
  else this.player.position.copy(this.anchor).lerp(corner,this.low?0:this.peekBlend/.65);
 }
}
window.CoverController=CoverController;
})();
