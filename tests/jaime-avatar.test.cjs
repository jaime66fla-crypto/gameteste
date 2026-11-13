const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const THREE=require('../public/vendor/three-r128.min.js');
const c={THREE,window:{THREE}};vm.createContext(c);for(const f of ['operator-motion','operator-avatar','operator-detail'])vm.runInContext(fs.readFileSync('public/'+f+'.js','utf8'),c);
test('Jaime is the primary character built from the supplied editor with distinct surface textures',()=>{
 const a=new c.window.OperatorAvatar();
 assert.equal(a.characterName,'Jaime');assert.equal(a.group.userData.visualVariant,'jaime-textured');assert.equal(a.body.geometry.userData.source,'avatar_editor.html');
 const mats=a.body.material;
 for(const index of [0,1,3,5,7]){assert(mats[index].map?.isTexture,'Surface has an albedo texture: '+index);assert(mats[index].bumpMap?.isTexture,'Surface has relief: '+index);}
 assert.notEqual(mats[0].map,mats[5].map,'Skin must not reuse cloth weave');
 assert.notEqual(mats[0].map,mats[1].map,'Vest has its own woven surface');
 const box=new THREE.Box3().setFromObject(a.group);assert(box.max.y-box.min.y>1.7&&box.max.y-box.min.y<1.95);
 assert.equal(a.skeleton.bones.length,18);assert(a.body.isSkinnedMesh);
 const html=fs.readFileSync('public/index.html','utf8');assert(html.includes('JAIME • SEU PERSONAGEM'));
});
test('visible palms stay on the weapon grips after retargeting the source joints',()=>{
 const a=new c.window.OperatorAvatar();for(const weapon of ['pistol','rifle']){
  a.setWeapon(weapon);for(let i=0;i<120;i++)a.update(1/60,{armed:true,grounded:true,aiming:true});a.group.updateMatrixWorld(true);a.skeleton.update();
  for(const grip of a.weaponGripTargets){
   const pos=a.body.geometry.attributes.position,skin=a.body.geometry.attributes.skinIndex,center=new THREE.Vector3(),v=new THREE.Vector3();let count=0;
   for(let i=0;i<pos.count;i++)if(skin.getX(i)===grip.bone){v.fromBufferAttribute(pos,i);a.body.boneTransform(i,v);center.add(v.applyMatrix4(a.body.matrixWorld));count++;}
   assert(count>0);center.divideScalar(count);const target=a.group.localToWorld(grip.point.clone());assert(center.distanceTo(target)<.05,weapon+' visible palm misses grip by '+center.distanceTo(target));
  }
 }
});
