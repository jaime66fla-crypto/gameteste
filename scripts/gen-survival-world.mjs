// Gera godot/data/survival_world.json: o mundo aberto do modo Sobrevivência.
// O jogo (scripts/survival/survival_world.gd) monta o cenário a partir deste
// arquivo e o servidor (src/godot-survival.js) usa as mesmas posições para
// conferir distâncias de coleta e nascimento.
//
//   node scripts/gen-survival-world.mjs
//
// Mundo só de natureza: florestas, clareiras, lagos, rochas, arbustos de frutas
// e coisas pequenas no chão (galhos, pedrinhas, capim de fibra, ervas). Nada
// pronto para saquear: tudo o que o jogador usa sai da coleta e da fabricação.
//
// A semente é fixa: rodar de novo gera exatamente o mesmo mapa.
import { writeFileSync } from 'node:fs';

const SEED = 20261120;
const HALF = 300; // 600 x 600 m

function mulberry32(a) {
	return () => {
		a |= 0;
		a = (a + 0x6d2b79f5) | 0;
		let t = Math.imul(a ^ (a >>> 15), 1 | a);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}
const rand = mulberry32(SEED);
const between = (a, b) => a + rand() * (b - a);
const pick = (list) => list[Math.floor(rand() * list.length)];
const r1 = (n) => Math.round(n * 10) / 10;

const resources = [];
const ponds = [];
let resourceSeq = 0;

function addResource(kind, x, z, extra = {}) {
	resources.push({ id: 'r' + resourceSeq++, kind, p: [r1(x), 0, r1(z)], yaw: r1(rand() * 6.28), ...extra });
}

// Grade de ocupação (4 m) para checar vizinhos rápido.
const CELL = 4;
const grid = new Map();
const cellKey = (x, z) => `${Math.floor(x / CELL)},${Math.floor(z / CELL)}`;
function occupy(x, z, radius) {
	const key = cellKey(x, z);
	if (!grid.has(key)) grid.set(key, []);
	grid.get(key).push([x, z, radius]);
}
function crowded(x, z, radius) {
	const cx = Math.floor(x / CELL);
	const cz = Math.floor(z / CELL);
	for (let i = -2; i <= 2; i++) {
		for (let j = -2; j <= 2; j++) {
			for (const [ox, oz, or] of grid.get(`${cx + i},${cz + j}`) || []) {
				if (Math.hypot(ox - x, oz - z) < radius + or) return true;
			}
		}
	}
	return false;
}
const inWater = (x, z, margin) => ponds.some((p) => Math.hypot(p.x - x, p.z - z) < p.r + margin);
const outside = (x, z, margin) => Math.abs(x) > HALF - margin || Math.abs(z) > HALF - margin;

/** Coisa sólida (árvore, rocha, arbusto): ocupa espaço. */
function place(kind, x, z, radius, extra) {
	if (outside(x, z, 6) || inWater(x, z, radius + 1.5) || crowded(x, z, radius)) return false;
	occupy(x, z, radius);
	addResource(kind, x, z, extra);
	return true;
}
/** Coisa pequena no chão (galho, pedrinha, fibra, erva): só não pode cair dentro de algo. */
function placeSmall(kind, x, z) {
	if (outside(x, z, 6) || inWater(x, z, 0.8) || crowded(x, z, 0.6)) return false;
	occupy(x, z, 0.3);
	addResource(kind, x, z);
	return true;
}

// --- Lagos: água para beber (segure E na margem) ---------------------------------
for (let tries = 0; ponds.length < 16 && tries < 2000; tries++) {
	const x = between(-HALF + 30, HALF - 30);
	const z = between(-HALF + 30, HALF - 30);
	const r = between(5, 13);
	if (ponds.some((p) => Math.hypot(p.x - x, p.z - z) < p.r + r + 45)) continue;
	ponds.push({ x: r1(x), z: r1(z), r: r1(r) });
}
for (const p of ponds) {
	occupy(p.x, p.z, p.r);
	resources.push({ id: 'r' + resourceSeq++, kind: 'pond', p: [p.x, 0, p.z], yaw: 0, r: p.r });
}

// --- Clareiras: onde os jogadores nascem (campo aberto perto de água) -------------
const clearings = [];
for (const p of ponds) {
	const a = rand() * Math.PI * 2;
	const d = p.r + between(10, 18);
	clearings.push({ x: p.x + Math.cos(a) * d, z: p.z + Math.sin(a) * d, r: between(14, 20) });
}
const inClearing = (x, z) => clearings.some((c) => Math.hypot(c.x - x, c.z - z) < c.r);

// --- Florestas: muitos aglomerados densos, mata rala entre eles --------------------
const forests = [];
for (let tries = 0; forests.length < 70 && tries < 3000; tries++) {
	const x = between(-HALF + 20, HALF - 20);
	const z = between(-HALF + 20, HALF - 20);
	if (inClearing(x, z) || inWater(x, z, 8)) continue;
	forests.push({ x, z, r: between(18, 42) });
}
for (const f of forests) {
	const trees = Math.floor(f.r * f.r * 0.055);
	for (let i = 0; i < trees; i++) {
		const a = rand() * Math.PI * 2;
		const d = Math.sqrt(rand()) * f.r;
		const x = f.x + Math.cos(a) * d;
		const z = f.z + Math.sin(a) * d;
		if (!inClearing(x, z)) place('tree', x, z, between(1.6, 2.4));
	}
}
function scatter(kind, count, radius, test = () => true) {
	for (let i = 0, tries = 0; i < count && tries < count * 50; tries++) {
		const x = between(-HALF + 8, HALF - 8);
		const z = between(-HALF + 8, HALF - 8);
		if (!test(x, z)) continue;
		if (place(kind, x, z, radius)) i++;
	}
}
scatter('tree', 500, 2.2, (x, z) => !inClearing(x, z));

// --- Pedreiras: grupos de rochas; mais algumas soltas ------------------------------
for (let q = 0; q < 12; q++) {
	const cx = between(-HALF + 30, HALF - 30);
	const cz = between(-HALF + 30, HALF - 30);
	for (let i = 0; i < 14; i++) {
		const a = rand() * Math.PI * 2;
		const d = Math.sqrt(rand()) * 16;
		place('rock', cx + Math.cos(a) * d, cz + Math.sin(a) * d, 1.6);
	}
}
scatter('rock', 110, 1.6);
scatter('bush', 240, 1.0);

// --- Chão: galhos perto das árvores, pedrinhas perto das rochas, fibra e ervas no campo ---
const trees = resources.filter((r) => r.kind === 'tree');
const rocks = resources.filter((r) => r.kind === 'rock');
function near(kind, list, count, min, max) {
	for (let i = 0, tries = 0; i < count && tries < count * 20; tries++) {
		const base = pick(list);
		const a = rand() * Math.PI * 2;
		const d = between(min, max);
		if (placeSmall(kind, base.p[0] + Math.cos(a) * d, base.p[2] + Math.sin(a) * d)) i++;
	}
}
near('stick', trees, 650, 1.2, 4.5);
near('pebble', rocks, 260, 1.4, 4.0);
function scatterSmall(kind, count) {
	for (let i = 0, tries = 0; i < count && tries < count * 30; tries++) {
		if (placeSmall(kind, between(-HALF + 8, HALF - 8), between(-HALF + 8, HALF - 8))) i++;
	}
}
scatterSmall('pebble', 200);
scatterSmall('fiber', 600);
scatterSmall('herb', 160);
// Cada clareira de nascimento tem o básico por perto: galhos, pedrinhas e fibra.
for (const c of clearings) {
	for (const kind of ['stick', 'stick', 'stick', 'pebble', 'pebble', 'fiber', 'fiber', 'fiber']) {
		for (let tries = 0; tries < 20; tries++) {
			const a = rand() * Math.PI * 2;
			const d = between(3, c.r);
			if (placeSmall(kind, c.x + Math.cos(a) * d, c.z + Math.sin(a) * d)) break;
		}
	}
}

// --- Grama alta: manchas para se esconder agachado (o jogo e os zumbis usam) -------
const grass = [];
for (let tries = 0; grass.length < 200 && tries < 8000; tries++) {
	const x = between(-HALF + 15, HALF - 15);
	const z = between(-HALF + 15, HALF - 15);
	const r = between(5, 12);
	if (inWater(x, z, r + 2) || inClearing(x, z)) continue;
	grass.push({ x: r1(x), z: r1(z), r: r1(r) });
}

// --- Nascimento dos jogadores: no meio das clareiras ------------------------------
const spawns = [];
const order = clearings.map((c, i) => [Math.atan2(c.z, c.x), i]).sort((a, b) => a[0] - b[0]);
for (const [, i] of order) {
	if (spawns.length >= 16) break;
	const c = clearings[i];
	for (let tries = 0; tries < 40; tries++) {
		const x = c.x + between(-4, 4);
		const z = c.z + between(-4, 4);
		if (outside(x, z, 12) || inWater(x, z, 3) || crowded(x, z, 1.5)) continue;
		spawns.push([r1(x), r1(z)]);
		break;
	}
}
while (spawns.length < 16) {
	const x = between(-HALF + 30, HALF - 30);
	const z = between(-HALF + 30, HALF - 30);
	if (!inWater(x, z, 3) && !crowded(x, z, 2)) spawns.push([r1(x), r1(z)]);
}

const world = {
	_comment: 'Gerado por scripts/gen-survival-world.mjs (não edite à mão). Coordenadas em metros, [x, z] no chão; p = [x, y, z]. Mundo só de natureza: nada para saquear, tudo é coletado e fabricado.',
	seed: SEED,
	half_size: HALF,
	ponds,
	resources,
	spawns,
	grass,
	// Sem cidades: zumbis só aparecem à noite, errando pelo mato em volta dos jogadores.
	zombie_zones: [],
	towns: [],
	buildings: [],
	roads: [],
	containers: [],
	vehicles: [],
	parkour: [],
	parkour_bases: [],
};
writeFileSync(new URL('../godot/data/survival_world.json', import.meta.url), JSON.stringify(world, null, 1) + '\n');
const count = (kind) => resources.filter((r) => r.kind === kind).length;
console.log(`${count('tree')} árvores, ${count('rock')} rochas, ${count('bush')} arbustos, ${count('stick')} galhos, ${count('pebble')} pedrinhas, ${count('fiber')} capins, ${count('herb')} ervas, ${ponds.length} lagos, ${grass.length} manchas de grama alta, ${spawns.length} nascimentos`);
