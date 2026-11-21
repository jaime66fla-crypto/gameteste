import test from 'node:test';
import assert from 'node:assert/strict';
import world from '../godot/data/survival_world.json' with { type: 'json' };
import { terrainHeight, mountainIntersects } from '../src/godot-terrain.js';
import { GodotSurvival } from '../src/godot-survival.js';

test('mountains preserve the old map and have walkable slopes', () => {
	assert.equal(world.mountains.length, 4);
	for (const m of world.mountains) {
		assert.ok(Math.max(Math.abs(m.x), Math.abs(m.z)) - m.r >= 300);
		assert.ok(Math.max(Math.abs(m.x), Math.abs(m.z)) + m.r < world.half_size);
		assert.ok(m.h * Math.PI / (2 * m.r) < 0.95);
		assert.equal(terrainHeight(m.x, m.z), m.h);
		assert.ok(Math.abs(terrainHeight(m.x + m.r / 2, m.z) - m.h / 2) < 1e-6);
		assert.equal(terrainHeight(m.x + m.r, m.z), 0);
	}
	for (const [x, z] of world.spawns) assert.equal(terrainHeight(x, z), 0);
});

test('server prevents foundations buried in mountain slopes', () => {
	const m = world.mountains[0];
	const i = Math.floor(m.x / 3);
	const j = Math.floor(m.z / 3);
	assert.ok(mountainIntersects([m.x - 1, m.z - 1, m.x + 1, m.z + 1]));
	assert.equal(mountainIntersects([-3, -3, 3, 3]), false);
	const result = GodotSurvival.prototype.groundFree.call({}, { kind: 'foundation', i, j, k: 0 });
	assert.match(result, /terreno plano/);
});
