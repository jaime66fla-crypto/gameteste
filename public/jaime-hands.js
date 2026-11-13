/* Jaime articulated hands, built to match the 18-bone OperatorAvatar wrist rig.
   FBX "Rigged Hand" reference: open fingers in locomotion and curled fingers on grips.
   The source FBX mesh is not yet converted; do not label these as imported FBX geometry. */
(()=>{
'use strict';
function attach(THREE,avatar){
 const material=new THREE.MeshStandardMaterial({color:0xc48d6f,roughness:.83,metalness:0});
 const nail=new THREE.MeshStandardMaterial({color:0xdba997,roughness:.66,metalness:0});
 const crease=new THREE.MeshStandardMaterial({color:0xa97359,roughness:.93,metalness:0});
 const sphere=(parent,rx,ry,rz,x,y,z,mat=material)=>{
  const mesh=new THREE.Mesh(new THREE.SphereGeometry(1,12,9),mat);
  mesh.position.set(x,y,z);mesh.scale.set(rx,ry,rz);mesh.castShadow=true;mesh.receiveShadow=true;
  parent.add(mesh);return mesh;
 };
 const fingers=[];
 for(const handIndex of [8,11]){
  const bone=avatar.bones[handIndex];
  const side=handIndex===8?-1:1;
  const palm=new THREE.Group();palm.name=handIndex===8?'JAIME_RIGHT_ARTICULATED_HAND':'JAIME_LEFT_ARTICULATED_HAND';
  bone.add(palm);palm.position.y=-.006;
  sphere(palm,.044,.047,.026,0,-.044,0);
  // Fingers grow toward -Y (the existing editor wrist local axis).
  const fingersForHand=[];
  const lengths=[.038,.045,.042,.035];
  for(let i=0;i<4;i++){
   const x=(i-1.5)*.019;
   const base=new THREE.Group();base.position.set(x,-.071,.003);palm.add(base);
   const firstLen=lengths[i]*.56,secondLen=lengths[i]*.44;
   sphere(base,.010,firstLen*.60,.010,0,-firstLen*.48,.002);
   const knuckle=sphere(base,.011,.010,.011,0,-firstLen,.002);
   const tipGroup=new THREE.Group();tipGroup.position.set(0,-firstLen,0);base.add(tipGroup);
   sphere(tipGroup,.0085,secondLen*.61,.009,0,-secondLen*.45,.002);
   sphere(tipGroup,.009,.009,.009,0,-secondLen,.002);
   const nailMesh=sphere(tipGroup,.006,secondLen*.23,.002,0,-secondLen*.82,.010,nail);
   fingersForHand.push({base,tipGroup,rest:(i-1.5)*.035});
  }
  // Opposable thumb: two segments set at the side of the palm.
  const thumb=new THREE.Group();thumb.position.set(side*.036,-.031,.005);
  thumb.rotation.z=side*.68;palm.add(thumb);
  sphere(thumb,.012,.022,.012,0,-.017,0);
  const thumbTip=new THREE.Group();thumbTip.position.set(0,-.036,0);thumb.add(thumbTip);
  sphere(thumbTip,.010,.020,.010,0,-.013,.002);
  sphere(thumbTip,.010,.009,.010,0,-.030,.002);
  sphere(thumbTip,.007,.008,.003,0,-.029,.012,nail);
  // Subtle folds at the hand base to avoid a mitten-like silhouette.
  for(let i=0;i<3;i++)sphere(palm,.010,.004,.006,(i-1)*.02,-.074,.022,crease);
  fingers.push({side,root:palm,segments:fingersForHand,thumb,thumbTip});
 }
 avatar.articulatedHands=fingers;
 return fingers;
}
function update(avatar,THREE,dt,armed,aiming,reload=0){
 if(!avatar.articulatedHands)return;
 const hold=armed?Math.max(.25,aiming?.85:.56):0;
 const release=Math.min(1,Math.max(0,reload))*0.32;
 const grip=THREE.MathUtils.clamp(hold-release,0,1);
 const rate=1-Math.exp(-13*Math.max(0,Math.min(dt,.05)));
 for(const hand of avatar.articulatedHands){
  for(let i=0;i<hand.segments.length;i++){
   const finger=hand.segments[i];
   finger.base.rotation.x=THREE.MathUtils.lerp(finger.base.rotation.x,grip*(.53+i*.035),rate);
   finger.tipGroup.rotation.x=THREE.MathUtils.lerp(finger.tipGroup.rotation.x,grip*.70,rate);
   finger.base.rotation.z=THREE.MathUtils.lerp(finger.base.rotation.z,finger.rest*(1-grip),rate);
  }
  hand.thumb.rotation.z=THREE.MathUtils.lerp(hand.thumb.rotation.z,hand.side*(.68-.18*grip),rate);
  hand.thumbTip.rotation.x=THREE.MathUtils.lerp(hand.thumbTip.rotation.x,grip*.55,rate);
 }
}
window.JaimeArticulatedHands={attach,update};
})();