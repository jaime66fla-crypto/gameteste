import world from '../godot/data/survival_world.json' with { type: 'json' };
import { terrainHeight } from './godot-terrain.js';

export const BRANCH_LIMIT = 64;
export const BRANCH_LIFETIME_MS = 10 * 60 * 1000;
export const BRANCH_TREES = world.resources.filter((r) => r.kind === 'tree');
const RADII = { tree: 0.7, rock: 1.5, ore: 1.5, saltpeter: 1.5, bush: 0.9, car: 3 };
const blockers = new Map();
for (const r of world.resources) {
	if (!RADII[r.kind]) continue;
	const key = `${Math.floor(r.p[0] / 4)},${Math.floor(r.p[2] / 4)}`;
	if (!blockers.has(key)) blockers.set(key, []);
	blockers.get(key).push(r);
}

export function treeSeed(tree) {
	return Number.parseInt(tree.id.replace(/\D/g, ''), 10) || 0;
}

export function branchPeriod(tree) {
	return 90000 + (treeSeed(tree) % 61) * 1000;
}

export function branchSpot(tree, now) {
	for (let i = 0; i < 8; i++) {
		const angle = (treeSeed(tree) * 2.39996 + i * Math.PI / 4 + Math.floor(now / 90000)) % (Math.PI * 2);
		const radius = 1.7 + (i % 3) * 0.35;
		const x = Math.round((tree.p[0] + Math.cos(angle) * radius) * 10) / 10;
		const z = Math.round((tree.p[2] + Math.sin(angle) * radius) * 10) / 10;
		if (Math.abs(x) > world.half_size - 2 || Math.abs(z) > world.half_size - 2) continue;
		if (world.ponds.some((p) => Math.hypot(x - p.x, z - p.z) < p.r + 0.5)) continue;
		if (world.buildings.some((b) => Math.abs(x - b.center[0]) < b.size[0] / 2 + 1 && Math.abs(z - b.center[1]) < b.size[1] / 2 + 1)) continue;
		let blocked = false;
		for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) {
			for (const r of blockers.get(`${Math.floor(x / 4) + dx},${Math.floor(z / 4) + dz}`) || []) {
				if (Math.hypot(x - r.p[0], z - r.p[2]) < RADII[r.kind] + 0.2) blocked = true;
			}
		}
		if (!blocked) return [x, terrainHeight(x, z) + 0.025, z];
	}
	return null;
}
