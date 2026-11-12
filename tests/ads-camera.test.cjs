const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const THREE = require('../public/vendor/three-r128.min.js');
// Only replace the browser renderer/DOM; camera, transforms, inventory and physics are real.
THREE.WebGLRenderer = class { constructor() { this.shadowMap = {}; } setPixelRatio() {} setSize() {} render() {} };
const ctx2d = new Proxy({ createLinearGradient: () => ({ addColorStop() {} }), createRadialGradient: () => ({ addColorStop() {} }) }, { get: (o, k) => o[k] || (() => {}) });
function element() { return { style: {}, setAttribute() {}, classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } }, addEventListener() {}, appendChild() {}, getContext: () => ctx2d }; }
const elements = new Map();
const context = { THREE, window: { addEventListener() {} }, document: { body: element(), getElementById(id) { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); }, createElement: element, addEventListener() {} }, addEventListener() {}, devicePixelRatio: 1, innerWidth: 1280, innerHeight: 720, requestAnimationFrame() {}, console, setTimeout() {}, clearTimeout() {}, performance: { now: () => 1000 }, location: { host: 'game.test', protocol: 'https:' }, WebSocket: class {}, localStorage: { getItem() { return null; }, setItem() {} } };
vm.createContext(context);
for (const path of ['operator-avatar.js', 'combat-bots.js', 'cover-controller.js', 'weapon-loot.js', 'full3d.js']) {
 vm.runInContext(fs.readFileSync('public/' + path, 'utf8'), context);
}
const a = vm.runInContext('({player,camera,controller,thirdPersonCamera,mainAvatar,pistolWeapon,weaponLoot,houseParkour,updateCamera,updateAdsViewModel})', context);
a.houseParkour.solidBoxes = [];
a.thirdPersonCamera._cameraCollision = (focus, desired) => desired;
a.thirdPersonCamera.getGroundHeight = () => -100;
a.pistolWeapon.equip();

test('ADS preserves all four headings and follows mouse yaw instead of stale weapon sights', () => {
 for (const [yaw, direction] of [[0, [0, 0, -1]], [Math.PI / 2, [-1, 0, 0]], [Math.PI, [0, 0, 1]], [-Math.PI / 2, [1, 0, 0]]]) {
  a.controller.keys.aiming = false;
  a.player.position.set(0, 0, 0);
  a.thirdPersonCamera.yaw = yaw;
  a.thirdPersonCamera.pitch = 0;
  a.updateCamera(1 / 60);
  a.controller.keys.aiming = true;
  for (let i = 0; i < 90; i++) a.updateCamera(1 / 60);
  const actual = a.camera.getWorldDirection(new THREE.Vector3());
  assert(actual.dot(new THREE.Vector3(...direction)) > .999, 'ADS must retain heading ' + yaw);
 }
});

test('ADS WASD moves the player and camera together in the chosen heading', () => {
 a.thirdPersonCamera.yaw = Math.PI / 2;
 a.thirdPersonCamera.pitch = 0;
 a.player.position.set(0, 0, 0);
 a.controller.clearInput();
 a.controller.keys.aiming = true;
 for (let i = 0; i < 90; i++) a.updateCamera(1 / 60);
 a.controller._onKeyChange('KeyW', true);
 const before = a.player.position.clone();
 const eyeBefore = a.camera.position.clone();
 for (let i = 0; i < 60; i++) { a.controller.update(1 / 60); a.updateCamera(1 / 60); }
 assert(a.player.position.x < before.x - 4, 'W must travel over four metres toward the current aim');
 assert(Math.abs(a.player.position.z - before.z) < .01, 'W must not redirect toward a fixed north');
 assert(Math.abs((a.camera.position.x - eyeBefore.x) - (a.player.position.x - before.x)) < .01, 'Camera must follow actual player displacement');
 a.controller.clearInput();
});

test('ADS hides the world avatar, restores it on release and keeps the dedicated gun', () => {
 a.thirdPersonCamera.modeIndex = 1;
 a.controller.keys.aiming = true;
 a.updateAdsViewModel(1 / 60);
 a.updateCamera(1 / 60);
 assert.equal(a.mainAvatar.group.visible, false, 'Body and world weapon must not clip across the sight');
 assert(a.camera.children.some(o => o.name === 'ADS_VIEWMODEL' && o.visible), 'ADS gun remains visible');
 a.controller.keys.aiming = false;
 a.updateCamera(1 / 60);
 a.updateAdsViewModel(1 / 60);
 assert.equal(a.mainAvatar.group.visible, true);
 assert(!a.camera.children.some(o => o.name === 'ADS_VIEWMODEL' && o.visible));
});

test('ADS follows vertical mouse aim, recovers recoil and keeps its selected optic zoom', () => {
 a.controller.clearInput();
 a.controller.keys.aiming = true;
 a.thirdPersonCamera.yaw = 0;
 a.thirdPersonCamera.pitch = -.3;
 a.weaponLoot.slots[0] = { id: 'smg', ammo: 24 };
 a.weaponLoot.activeSlot = 0;
 a.weaponLoot.applyActive();
 a.thirdPersonCamera.addShotRecoil();
 for (let i = 0; i < 120; i++) a.updateCamera(1 / 60);
 const direction = a.camera.getWorldDirection(new THREE.Vector3());
 assert(direction.y > .29 && direction.z < -.95, 'Looking up must keep looking up during ADS');
 assert(a.thirdPersonCamera.recoilPitch < .00001, 'ADS recoil must recover instead of accumulating');
 assert(Math.abs(a.camera.fov - 38) < .01, 'Optic FOV must converge without fighting third-person zoom');
});

test('all WASD directions work during ADS and releasing it preserves the heading', () => {
 a.thirdPersonCamera.yaw = Math.PI;
 a.thirdPersonCamera.pitch = 0;
 for (const [key, axis, sign] of [['KeyW', 'z', 1], ['KeyS', 'z', -1], ['KeyA', 'x', 1], ['KeyD', 'x', -1]]) {
  a.controller.clearInput();
  a.player.position.set(0, 0, 0);
  a.controller.keys.aiming = true;
  a.updateCamera(1 / 60);
  a.controller._onKeyChange(key, true);
  for (let i = 0; i < 60; i++) { a.controller.update(1 / 60); a.updateCamera(1 / 60); }
  assert(a.player.position[axis] * sign > 4, key + ' must move in its camera-relative direction');
 }
 a.controller.clearInput();
 a.updateCamera(1 / 60);
 assert(a.camera.getWorldDirection(new THREE.Vector3()).z > .999, 'Release must not rotate toward north');
});
