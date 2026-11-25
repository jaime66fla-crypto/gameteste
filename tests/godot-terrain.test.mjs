import test from 'node:test';
import assert from 'node:assert/strict';
import world from '../godot/data/survival_world.json' with { type: 'json' };
import catalog from '../godot/data/survival_items.json' with { type: 'json' };
import { terrainHeight, mountainIntersects } from '../src/godot-terrain.js';
import { relief, reliefMask, waterAt } from '../src/godot-hydrology.js';
import { BuildGrid } from '../src/godot-building.js';
import { GodotSurvival } from '../src/godot-survival.js';

test('mountains preserve the old map and have walkable slopes', () => {
	assert.equal(world.mountains.length, 4);
	for (const m of world.mountains) {
		assert.ok(Math.max(Math.abs(m.x), Math.abs(m.z)) - m.r >= 300);
		assert.ok(Math.max(Math.abs(m.x), Math.abs(m.z)) + m.r < world.half_size);
		assert.ok(m.h * Math.PI / (2 * m.r) < 0.95);
		const bump = (x, z) => terrainHeight(x, z) - relief(x, z);
		assert.equal(bump(m.x, m.z), m.h);
		assert.ok(Math.abs(bump(m.x + m.r / 2, m.z) - m.h / 2) < 1e-6);
		assert.equal(bump(m.x + m.r, m.z), 0);
	}
});

test('relief: rolling hills outside towns, roads and water; never below the sea', () => {
	let hills = 0;
	let samples = 0;
	let steepest = 0;
	for (let x = -400; x <= 400; x += 4) {
		for (let z = -400; z <= 400; z += 4) {
			if (Math.hypot(x, z) > 400) continue;
			const r = relief(x, z);
			samples++;
			if (r > 1.5) hills++;
			assert.ok(r > -1.0, `relief stays above the sea plane (${x}, ${z}: ${r})`);
			steepest = Math.max(steepest, Math.hypot(relief(x + 1, z) - r, relief(x, z + 1) - r));
		}
	}
	assert.ok(hills / samples > 0.1, `visible hills (${hills / samples})`);
	assert.ok(steepest < 0.8, `walkable (${steepest})`);
	for (const t of world.towns) assert.equal(reliefMask(t.center[0], t.center[1]), 0, t.name);
	for (const b of world.buildings) {
		for (const [dx, dz] of [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]]) {
			assert.equal(relief(b.center[0] + dx * b.size[0], b.center[1] + dz * b.size[1]), 0, b.name);
		}
	}
	for (const road of world.roads) {
		for (let t = 0; t <= 1; t += 0.05) {
			const x = road.from[0] + (road.to[0] - road.from[0]) * t;
			const z = road.from[1] + (road.to[1] - road.from[1]) * t;
			assert.equal(relief(x, z), 0, 'roads stay flat');
		}
	}
	for (const b of [...world.ponds, ...world.hydrology.floodplains]) {
		for (let a = 0; a < Math.PI * 2; a += 0.3) {
			assert.ok(Math.abs(relief(b.x + Math.cos(a) * b.r * 1.3, b.z + Math.sin(a) * b.r * 1.3)) < 1e-9, 'lake shores stay as they were');
		}
	}
});

test('players spawn on top of the new ground', () => {
	for (let n = 0; n < 40; n++) {
		const p = GodotSurvival.prototype.newCharacter.call({}).p;
		assert.ok(p[1] >= terrainHeight(p[0], p[2]) + 0.1, 'above the ground');
		assert.equal(waterAt(p[0], p[2]), null);
	}
});

test('foundations go up mountain slopes on a pillar instead of being refused', () => {
	const m = world.mountains[0];
	const i = Math.floor((m.x - m.r / 2) / 3);
	const j = Math.floor(m.z / 3);
	assert.ok(mountainIntersects([i * 3, j * 3, i * 3 + 3, j * 3 + 3]));
	const grid = new BuildGrid(catalog.build_rules, catalog.builds, terrainHeight);
	assert.match(grid.check({ kind: 'foundation', i, j, k: 0, b: 0 }), /enterrada/);
	assert.equal(grid.check({ kind: 'foundation', i, j, k: 0, b: grid.foundationLift(i, j) }), '');
	assert.equal(GodotSurvival.prototype.groundFree.call({ state: { createdAt: Date.now() } }, { kind: 'foundation', i, j, k: 0 }), '');
});
