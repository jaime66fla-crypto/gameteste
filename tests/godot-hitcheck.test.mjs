// Conferência de acertos (src/godot-hitcheck.js): alcance, cabeça plausível e taxa de tiros na cabeça.
import test from 'node:test';
import assert from 'node:assert/strict';

const { HitCheck, WEAPON_RANGE, HEADSHOT_WATCH, stanceOf } = await import('../src/godot-hitcheck.js');

const shooter = (p = [0, 0, 0]) => ({ id: 'a', name: 'Atirador', p });
const victim = (p = [20, 0, 0], stance = 'stand') => ({ id: 'b', p, stance });

test('out of weapon range is refused; in range passes', () => {
	const hc = new HitCheck();
	assert.equal(hc.check({ attacker: shooter(), target: victim([WEAPON_RANGE.shotgun + 30, 0, 0]), weapon: 'shotgun', zone: 'chest' }).ok, false);
	assert.equal(hc.check({ attacker: shooter(), target: victim([WEAPON_RANGE.shotgun - 5, 0, 0]), weapon: 'shotgun', zone: 'chest' }).ok, true);
	assert.equal(hc.check({ attacker: shooter(), target: victim([600, 0, 0]), weapon: 'sniper', zone: 'chest' }).ok, true);
	assert.equal(hc.check({ attacker: shooter(), target: victim(), weapon: 'laser', zone: 'chest' }).ok, false, 'unknown weapon');
});

test('a head hit must be where the head can be for the target stance', () => {
	const hc = new HitCheck();
	const hit = (stance, point) => hc.check({ attacker: shooter(), target: victim([20, 0, 0], stance), weapon: 'rifle', zone: 'head', point }).zone;
	assert.equal(hit('stand', [20, 1.7, 0]), 'head');
	assert.equal(hit('stand', [20, 0.3, 0]), 'chest', 'head at the feet of a standing player');
	assert.equal(hit('prone', [20, 0.35, 0.8]), 'head', 'lying down: head low and ahead');
	assert.equal(hit('prone', [20, 1.7, 0]), 'chest', 'head at standing height of a prone player');
	assert.equal(hit('crouch', [20, 1.15, 0]), 'head');
	assert.equal(hit('stand', [26, 1.7, 0]), 'chest', 'point far from the target');
	assert.equal(hit('stand', null), 'head', 'old clients without a point: no point check');
});

test('too many head hits: the player is flagged and later heads count as chest', () => {
	const hc = new HitCheck();
	const a = shooter();
	let zone = '';
	for (let i = 0; i < HEADSHOT_WATCH.minHits; i++) {
		zone = hc.check({ attacker: a, target: victim(), weapon: 'rifle', zone: 'head', point: [20, 1.7, 0] }).zone;
	}
	assert.equal(hc.flagged('a'), true);
	assert.equal(zone, 'chest');
	assert.equal(hc.check({ attacker: a, target: victim(), weapon: 'rifle', zone: 'arm' }).zone, 'arm', 'other zones untouched');
	hc.reset();
	assert.equal(hc.flagged('a'), false);
});

test('a normal mix of hits is not flagged', () => {
	const hc = new HitCheck();
	const zones = ['chest', 'head', 'chest', 'arm', 'leg', 'head', 'chest', 'pelvis', 'chest', 'head'];
	for (let i = 0; i < 60; i++) hc.check({ attacker: shooter(), target: victim(), weapon: 'rifle', zone: zones[i % zones.length], point: [20, 1.7, 0] });
	assert.equal(hc.flagged('a'), false);
});

test('zombies only get the range check (headshots on them are normal)', () => {
	const hc = new HitCheck();
	for (let i = 0; i < 40; i++) {
		const r = hc.check({ attacker: shooter(), target: victim(), weapon: 'rifle', zone: 'head', point: [20, 0.1, 0], player: false });
		assert.equal(r.zone, 'head');
	}
	assert.equal(hc.flagged('a'), false);
});

test('stance comes from the state packet', () => {
	assert.equal(stanceOf({ pr: true, c: true }), 'prone');
	assert.equal(stanceOf({ c: true }), 'crouch');
	assert.equal(stanceOf({}), 'stand');
});
