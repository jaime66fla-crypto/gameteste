import assert from 'node:assert/strict';
import fs from 'node:fs';
import {api as a,elements,globalListeners,THREE,loadAvatar} from './aim.test.mjs';
const threeUrl=import.meta.resolve(process.env.THREE_TEST_MODULE||'three');
const {FBXLoader}=await import(new URL('../examples/jsm/loaders/FBXLoader.js',threeUrl));
globalThis.window={URL:globalThis.URL};
const originalTextureLoad=THREE.TextureLoader.prototype.load;
THREE.TextureLoader.prototype.load=function(){return new THREE.Texture()};
const file=fs.readFileSync(new URL('../public/assets/models/erika-archer.fbx',import.meta.url));
const model=new FBXLoader().parse(file.buffer.slice(file.byteOffset,file.byteOffset+file.byteLength),'');
THREE.TextureLoader.prototype.load=originalTextureLoad;
loadAvatar(model);
const bones=a.player.userData.avatarBones,gun=a.player.userData.gun;
assert.equal(Object.keys(bones).length,18);
assert.equal(model.rotation.y,0,'Erika must face the +Z gameplay forward axis');
assert.equal(gun.parent,bones.spine2.bone,'Resting weapon must be mounted on the spine');
assert(!a.player.userData.avatarMixer,'Static FBX clips must not suppress pose animation');
for(const yaw of [0,Math.PI/2,Math.PI]){
 a.player.position.set(0,0,0);a.setYaw(yaw);a.setPitch(0);a.resetShot();
 elements.get('view').listeners.pointerdown({pointerType:'mouse',button:0});
 a.updateThirdPersonCamera(1,a.player);a.updateAimFromPointer();a.updateProceduralAvatar(1/30,true);a.updateWeaponPose();
 assert.equal(gun.parent,bones.handR.bone,'Raised weapon must be attached to the right hand');
 const wrist=bones.handR.bone.getWorldPosition(new THREE.Vector3());
 assert(gun.getWorldPosition(new THREE.Vector3()).distanceTo(wrist)<1e-6,'Weapon grip must coincide with the hand');
 const support=gun.localToWorld(new THREE.Vector3(.36,0,0));
 const left=bones.handL.bone.getWorldPosition(new THREE.Vector3());
 assert(left.distanceTo(support)<.025,`Support hand misses foregrip by ${left.distanceTo(support)}`);
 const facing=new THREE.Vector3(0,0,1).applyQuaternion(model.getWorldQuaternion(new THREE.Quaternion()));
 const target=a.aimPoint.clone().sub(a.player.position);target.y=0;target.normalize();
 assert(facing.dot(target)>.999,'Avatar must face the target, rather than the camera');
 globalListeners.pointerup({button:0});
}
a.setTime(200);a.updateProceduralAvatar(1,true);a.updateWeaponPose();
assert.equal(gun.parent,bones.spine2.bone);
assert.equal(a.player.userData.weaponPose,'rest');
console.log('PASS: real FBX facing; right-hand gun attachment; two-hand shooting pose in three headings; automatic return to back mount.');

export {a,model,bones,gun};
