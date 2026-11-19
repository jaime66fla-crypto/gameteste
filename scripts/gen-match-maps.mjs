// Generates godot/data/match_maps.json: the three online match maps, built
// from plain coloured blocks (simple "toy brick" look, no textures).
//   praca   — Eliminatória (8 players, one life): 8 buildings around a raised plaza.
//   cruz    — Mata-mata (8 players, respawn): 4 rotated quarters, sheltered spawn nooks.
//   equipes — Equipes 2x2 and 4x4 (same map): mirrored bases, three linked lanes.
// The Godot client builds the blocks (scripts/match_map.gd); the server
// (src/godot-match.js) reads only the spawns. Validated by godot/tests/match_layout.gd.
// Run: node scripts/gen-match-maps.mjs
import { writeFileSync } from 'node:fs';

// Colours (keys used by the parts list).
const PALETTE = {
	base: '#a3a2a5', // baseplate grey
	grass: '#62b04c',
	road: '#5b5d69',
	wall: '#f2f3f3',
	stone: '#8a8b90',
	roof: '#85868c',
	red: '#c4281c',
	blue: '#0d69ac',
	yellow: '#f5cd30',
	orange: '#da8541',
	wood: '#a05f35',
	teal: '#1fa39a',
	border: '#6b6c72',
};

const WALL_T = 0.5; // wall thickness
const DOOR_W = 2.4;
const DOOR_H = 2.7;
const ROOF_T = 0.25;

const round = (v) => Math.round(v * 100) / 100;

class Map {
	constructor(id, name, halfX, halfZ, ground) {
		Object.assign(this, { id, name, halfX, halfZ, ground });
		this.parts = []; // [x, y, z, sx, sy, sz, colour, flags]
		this.footprints = []; // [x, z, sx, sz] for the minimap
		this.spawns = [];
	}
	/** Block resting on y0 (default ground). flags: 'w' walkable top, 'f' floor only (no minimap). */
	box(x, z, sx, sz, h, colour, y0 = 0, flags = '') {
		this.parts.push([round(x), round(y0 + h / 2), round(z), round(sx), round(h), round(sz), colour, flags]);
		if (!flags.includes('f') && h >= 1.0) this.footprints.push([round(x), round(z), round(sx), round(sz)]);
	}
	/** Flat ground decal (road, plaza, base pad): solid, a few cm thick. */
	floor(x, z, sx, sz, colour, top = 0.04) {
		this.box(x, z, sx, sz, top + 0.06, colour, -0.06, 'f');
	}
	/**
	 * Hollow building with walls, door gaps and a flat roof (walkable).
	 * doors: list of sides 'n' (-Z), 's' (+Z), 'w' (-X), 'e' (+X), optional ':offset'.
	 */
	building(cx, cz, w, d, h, colour, doors) {
		const sides = {
			n: { along: 'x', fixed: cz - d / 2 + WALL_T / 2, len: w, c: cx },
			s: { along: 'x', fixed: cz + d / 2 - WALL_T / 2, len: w, c: cx },
			w: { along: 'z', fixed: cx - w / 2 + WALL_T / 2, len: d, c: cz },
			e: { along: 'z', fixed: cx + w / 2 - WALL_T / 2, len: d, c: cz },
		};
		const doorAt = {};
		for (const spec of doors) {
			const [side, off] = spec.split(':');
			doorAt[side] = Number(off || 0);
		}
		for (const [side, s] of Object.entries(sides)) {
			const segs = [];
			const lo = s.c - s.len / 2;
			const hi = s.c + s.len / 2;
			if (side in doorAt) {
				const dc = s.c + doorAt[side];
				segs.push([lo, dc - DOOR_W / 2], [dc + DOOR_W / 2, hi]);
				// Lintel above the door.
				this.wallSeg(s, dc - DOOR_W / 2, dc + DOOR_W / 2, h - DOOR_H, colour, DOOR_H);
			} else segs.push([lo, hi]);
			for (const [a, b] of segs) if (b - a > 0.05) this.wallSeg(s, a, b, h, colour, 0);
		}
		// Roof slab (players can stand on it) and a thin coloured trim.
		this.parts.push([round(cx), round(h + ROOF_T / 2), round(cz), round(w + 0.3), ROOF_T, round(d + 0.3), 'roof', 'w']);
		this.footprints.push([round(cx), round(cz), round(w), round(d)]);
		this.floor(cx, cz, w - WALL_T * 2, d - WALL_T * 2, 'stone', 0.05);
		return h + ROOF_T;
	}
	wallSeg(s, a, b, h, colour, y0) {
		const len = b - a;
		const mid = (a + b) / 2;
		if (s.along === 'x') this.parts.push([round(mid), round(y0 + h / 2), round(s.fixed), round(len), round(h), WALL_T, colour, '']);
		else this.parts.push([round(s.fixed), round(y0 + h / 2), round(mid), WALL_T, round(h), round(len), colour, '']);
	}
	/** Perimeter wall (3 m, visible) on every edge. The client adds the tall invisible barrier. */
	perimeter() {
		const t = 0.8;
		const { halfX: hx, halfZ: hz } = this;
		this.box(0, -hz + t / 2, hx * 2, t, 3, 'border', 0, 'f');
		this.box(0, hz - t / 2, hx * 2, t, 3, 'border', 0, 'f');
		this.box(-hx + t / 2, 0, t, hz * 2, 3, 'border', 0, 'f');
		this.box(hx - t / 2, 0, t, hz * 2, 3, 'border', 0, 'f');
	}
	/** Runs `draw(rot)` where rot(x, z) turns a point by k quarter-turns about the origin. */
	static rotations(count, draw) {
		for (let k = 0; k < count; k++) {
			const turns = (4 / count) * k;
			const rot = (x, z) => {
				let p = [x, z];
				for (let i = 0; i < turns; i++) p = [-p[1], p[0]];
				return p;
			};
			const swap = turns % 2 === 1;
			draw(rot, swap, turns);
		}
	}
	toJSON() {
		return {
			id: this.id,
			name: this.name,
			half_x: this.halfX,
			half_z: this.halfZ,
			map_half_size: Math.max(this.halfX, this.halfZ),
			ground: this.ground,
			spawns: this.spawns.map(([x, z]) => [round(x), round(z)]),
			...(this.teamSpawns ? { team_spawns: this.teamSpawns.map((t) => t.map(([x, z]) => [round(x), round(z)])) } : {}),
			buildings: [], // no door waypoints: bots route with the A* grid (bot_nav.gd)
			footprints: this.footprints,
			parts: this.parts,
		};
	}
}

/** Rotated helpers: box/building given in the "first quarter" frame. */
function rotatedBox(map, rot, swap, x, z, sx, sz, h, colour, y0 = 0, flags = '') {
	const [rx, rz] = rot(x, z);
	map.box(rx, rz, swap ? sz : sx, swap ? sx : sz, h, colour, y0, flags);
}
const SIDE_TURN = { n: 'e', e: 's', s: 'w', w: 'n' }; // one quarter-turn (x,z)->(-z,x)
function turnSide(side, turns) {
	let s = side;
	for (let i = 0; i < turns; i++) s = SIDE_TURN[s];
	return s;
}

// ------------------------------------------------------------ Praça central
function praca() {
	const m = new Map('praca', 'Praça central', 50, 50, 'grass');
	m.perimeter();
	// Paths from each building to the plaza.
	m.floor(0, 0, 6, 62, 'base');
	m.floor(0, 0, 62, 6, 'base');
	// Eight buildings around the plaza, doors toward the middle.
	const colours = ['red', 'blue', 'yellow', 'teal'];
	const edge = [[0, -36, ['s']], [36, 0, ['w']], [0, 36, ['n']], [-36, 0, ['e']]];
	edge.forEach(([x, z, doors], i) => {
		m.building(x, z, 10, 10, 4, colours[i], doors);
		const toward = Math.hypot(x, z);
		m.spawns.push([x - (x / toward) * 2, z - (z / toward) * 2]);
	});
	const corner = [[-28, -28, ['s', 'e']], [28, -28, ['s', 'w']], [28, 28, ['n', 'w']], [-28, 28, ['n', 'e']]];
	corner.forEach(([x, z, doors], i) => {
		const top = m.building(x, z, 10, 10, 4, colours[(i + 2) % 4], doors);
		// Crate steps to the roof on the outer side (1.4 m and 2.8 m, roof at 4.25 m).
		const sx = Math.sign(x);
		const sz = Math.sign(z);
		m.box(x + sx * 6, z - sz * 1.5, 1.6, 1.6, 1.4, 'wood');
		m.box(x + sx * 6, z + sz * 0.1, 1.6, 1.6, 2.8, 'wood');
		// Parapet on the roof, open on the crate side.
		m.box(x - sx * 4.95, z, 0.3, 10, 0.9, 'wall', top);
		m.box(x, z - sz * 4.95, 10, 0.3, 0.9, 'wall', top);
		m.spawns.push([x - sx * 1.5, z - sz * 1.5]);
	});
	// Raised plaza: 1.0 m deck over a 0.5 m step ring, low walls on top.
	m.box(0, 0, 18, 18, 0.5, 'stone', 0, 'wf');
	m.box(0, 0, 13, 13, 0.5, 'yellow', 0.5, 'w');
	for (const [x, z, sx, sz] of [[4, 0, 0.6, 3], [-4, 0, 0.6, 3], [0, 4, 3, 0.6], [0, -4, 3, 0.6]]) m.box(x, z, sx, sz, 1.2, 'wall', 1.0);
	// Cover between the ring of buildings and the plaza (same in every quarter).
	Map.rotations(4, (rot, swap) => {
		rotatedBox(m, rot, swap, 0, -21, 5, 1, 2.2, 'stone'); // blocks the door -> plaza line
		rotatedBox(m, rot, swap, -14, -14, 2.4, 2.4, 1.4, 'orange');
		rotatedBox(m, rot, swap, -19, -6, 1, 4, 1.2, 'stone');
		rotatedBox(m, rot, swap, -6, -19, 4, 1, 1.2, 'stone');
		rotatedBox(m, rot, swap, 11.5, -11.5, 2, 2, 1.4, 'wood');
		rotatedBox(m, rot, swap, -40, -14, 4, 1, 1.2, 'stone');
	});
	return m;
}

// --------------------------------------------------------------------- Cruz
function cruz() {
	const m = new Map('cruz', 'Cruz', 40, 40, 'grass');
	m.perimeter();
	m.floor(0, 0, 6, 80, 'road');
	m.floor(0, 0, 80, 6, 'road');
	m.floor(0, 0, 18, 18, 'base', 0.05);
	m.floor(0, 0, 5, 5, 'yellow', 0.06);
	Map.rotations(4, (rot, swap, turns) => {
		const B = (x, z, sx, sz, h, colour, y0 = 0, flags = '') => rotatedBox(m, rot, swap, x, z, sx, sz, h, colour, y0, flags);
		const building = (x, z, w, d, h, colour, doors) => {
			const [rx, rz] = rot(x, z);
			return m.building(rx, rz, swap ? d : w, swap ? w : d, h, colour, doors.map((s) => turnSide(s, turns)));
		};
		// Two buildings per quarter, joined by a roof bridge (4.25 m).
		const top = building(-29.4, -30.4, 11.6, 11.2, 4, 'red', ['e', 's']);
		building(-13.4, -15.2, 12.4, 12.8, 4, 'blue', ['n', 'w']);
		B(-19.6, -30, 8, 2, 0.25, 'roof', top - 0.25, 'w');
		B(-16, -25.4, 2, 9.4, 0.25, 'roof', top - 0.25, 'w');
		B(-16, -30, 0.6, 0.6, top - 0.25, 'stone', 0, 'f');
		// Crate steps up to the red roof.
		B(-22.4, -34.6, 1.6, 1.6, 1.4, 'wood');
		B(-22.4, -32.9, 1.6, 1.6, 2.8, 'wood');
		// Spawn nooks: three walls, open toward the quarter, back to the road.
		B(-36.2, -20.8, 5.2, 0.5, 2.4, 'teal');
		B(-36.2, -14, 5.2, 0.5, 2.4, 'teal');
		B(-38.6, -17.4, 0.5, 7.3, 2.4, 'teal');
		B(-20.8, -36.2, 0.5, 5.2, 2.4, 'teal');
		B(-14, -36.2, 0.5, 5.2, 2.4, 'teal');
		B(-17.4, -38.6, 7.3, 0.5, 2.4, 'teal');
		for (const [x, z] of [[-36.4, -17.4], [-17.4, -36.4]]) m.spawns.push(rot(x, z));
		// Cover inside the quarter.
		B(-29.5, -17.2, 1, 6.4, 1.2, 'stone');
		B(-11.5, -26.8, 1, 5.6, 2.2, 'stone');
		B(-29.4, -9.1, 6.8, 1, 1.2, 'stone');
		B(-23.4, -14.6, 2.8, 2.8, 1.4, 'orange');
		// Buses and barricades zig-zag along the avenue.
		B(-1.3, -31, 2.6, 6, 2.6, 'yellow');
		B(1.3, -21.4, 2.6, 6, 2.6, 'orange');
		B(-1.3, -13.2, 2.6, 4.8, 1.4, 'stone');
		// Centre building: one wall per quarter, door off the avenue axis.
		B(-2.8, -9, 12.4, 0.6, 3, 'wall');
		B(8.2, -9, 1.6, 0.6, 3, 'wall');
		B(-5.5, -5.5, 1.8, 1.8, 2.6, 'stone');
	});
	return m;
}

// ------------------------------------------------------------------ Equipes
function equipes() {
	const m = new Map('equipes', 'Equipes', 32, 40, 'grass');
	m.perimeter();
	m.floor(0, 0, 8, 60, 'base');
	m.teamSpawns = [[], []];
	Map.rotations(2, (rot, swap, turns) => {
		const half = turns / 2;
		const B = (x, z, sx, sz, h, colour, y0 = 0, flags = '') => rotatedBox(m, rot, swap, x, z, sx, sz, h, colour, y0, flags);
		const building = (x, z, w, d, h, colour, doors) => {
			const [rx, rz] = rot(x, z);
			return m.building(rx, rz, swap ? d : w, swap ? w : d, h, colour, doors.map((s) => turnSide(s, turns)));
		};
		const team = half === 0 ? 'blue' : 'red';
		// Base pad and its front wall (three openings).
		B(0, -35.2, 32, 7.2, 0.06, team, -0.02, 'wf');
		B(-8, -29.6, 8, 0.6, 2.4, team);
		B(8, -29.6, 8, 0.6, 2.4, team);
		// Spawns: the middle two are used in 2x2, all four in 4x4.
		for (const x of [-4, 4, -11.6, 11.6]) m.teamSpawns[half].push(rot(x, -35.2));
		// Two-storey-height building on the left with crate steps, linked by a bridge.
		const top = building(-23.8, -20.4, 10, 10.4, 4, 'yellow', ['n', 's', 'e']);
		building(-12.2, -17, 6, 12.4, 4, 'wall', ['w', 'e']);
		building(12.2, -17, 6, 12.4, 4, 'wall', ['w', 'e']);
		B(-17, -20.4, 3.6, 2, 0.25, 'roof', top - 0.25, 'w');
		B(-30.2, -24, 1.6, 1.6, 1.4, 'wood');
		B(-30.2, -22.3, 1.6, 1.6, 2.8, 'wood');
		// Cover in the three lanes.
		B(0, -24.3, 8, 1, 1.2, 'stone');
		B(-6.3, -15.4, 1, 4.4, 2.2, 'stone');
		B(6.3, -13.8, 1, 4.4, 2.2, 'stone');
		B(23, -23.6, 6, 2.4, 2.6, 'orange');
		B(24.4, -15.2, 2.4, 5.6, 2.6, 'teal');
		B(21, -7.8, 5.2, 2, 1.4, 'orange');
		B(-24.6, -9.9, 6.8, 1, 1.2, 'stone');
		B(-22.7, -4.2, 1, 3.6, 2.2, 'stone');
		B(-8.2, -6.3, 3.6, 1, 1.2, 'stone');
		B(-5.5, 0, 1, 2.4, 1.2, 'stone');
	});
	// Contested centre: a 1.2 m platform reached by a 0.6 m step.
	m.box(0, 0, 8.4, 8.4, 0.6, 'stone', 0, 'w');
	m.box(0, 0, 6.4, 6.4, 0.6, 'yellow', 0.6, 'w');
	// Team spawns double as generic spawns (index order: blue then red).
	m.spawns = [...m.teamSpawns[0], ...m.teamSpawns[1]];
	return m;
}

const maps = [praca(), cruz(), equipes()];
const out = {
	_comment: 'Generated by scripts/gen-match-maps.mjs — do not edit by hand. Online match maps: parts are [x, y_centre, z, sx, sy, sz, colour, flags] (flags: w = walkable top, f = floor/no minimap). Shared by the Godot client and src/godot-match.js (spawns only).',
	palette: PALETTE,
	modes: { elim: 'praca', dm: 'cruz', teams: 'equipes' },
	maps: Object.fromEntries(maps.map((m) => [m.id, m.toJSON()])),
};
writeFileSync(new URL('../godot/data/match_maps.json', import.meta.url), JSON.stringify(out) + '\n');
for (const m of maps) console.log(`${m.id}: ${m.parts.length} parts, ${m.spawns.length} spawns`);
