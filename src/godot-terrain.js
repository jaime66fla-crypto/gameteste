import world from '../godot/data/survival_world.json' with { type: 'json' };

import { groundHeight } from './godot-hydrology.js';

/** Same cosine slopes as the client collision mesh (mountain_terrain.gd). */
export function terrainHeight(x, z) {
	let height = 0;
	for (const m of world.mountains || []) {
		const distance = Math.hypot(x - m.x, z - m.z);
		if (distance < m.r) height = Math.max(height, m.h * 0.5 * (1 + Math.cos(Math.PI * distance / m.r)));
	}
	return groundHeight(x, z, height);
}

export function mountainIntersects(box) {
	return (world.mountains || []).some((m) => {
		const dx = Math.max(box[0] - m.x, 0, m.x - box[2]);
		const dz = Math.max(box[1] - m.z, 0, m.z - box[3]);
		return Math.hypot(dx, dz) < m.r;
	});
}
