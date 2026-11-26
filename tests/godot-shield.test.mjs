// Escudo no braço (src/godot-survival.js): a guarda alta (FIXA) segura o dano de frente.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

globalThis.WebSocketPair ??= class {};
const { shieldFactor } = await import('../src/godot-survival.js');
const catalog = JSON.parse(readFileSync(new URL('../godot/data/survival_items.json', import.meta.url), 'utf8'));

test('os dois escudos existem no catálogo e têm receita', () => {
	for (const id of ['wood_shield', 'tactical_shield']) {
		assert.ok(catalog.items[id]?.shield > 0, id);
		assert.ok(catalog.recipes.some((r) => r.gives[0] === id), id);
	}
});

test('guarda alta corta o dano de frente, não o de trás nem sem guarda', () => {
	// yaw 0: o personagem olha para -Z.
	const player = { p: [0, 0, 0], y: 0, shield: 'tactical_shield', guard: true };
	assert.equal(shieldFactor(player, [0, 0, -5]), 1 - catalog.items.tactical_shield.shield);
	assert.equal(shieldFactor(player, [0, 0, 5]), 1);
	assert.equal(shieldFactor(player, [5, 0, 0]), 1);
	assert.equal(shieldFactor({ ...player, guard: false }, [0, 0, -5]), 1);
	assert.equal(shieldFactor(player, null), 1);
	// Virado 90° (yaw π/2 olha para -X).
	assert.ok(shieldFactor({ ...player, y: Math.PI / 2, shield: 'wood_shield' }, [-4, 0, 0]) < 0.5);
});
