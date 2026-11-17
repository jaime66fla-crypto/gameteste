// Gera godot/data/survival_world.json: o mundo aberto do modo Sobrevivência.
// O jogo (scripts/survival/survival_world.gd) monta o cenário a partir deste
// arquivo e o servidor (src/godot-survival.js) usa as mesmas posições para
// conferir distâncias de saque, coleta e nascimento.
//
//   node scripts/gen-survival-world.mjs
//
// A semente é fixa: rodar de novo gera exatamente o mesmo mapa.
import { readFileSync, writeFileSync } from 'node:fs';

const SEED = 20261117;
const HALF = 240; // mapa de 480 x 480 m
const CENTER_CLEAR = 66; // cidade original do Campo de Fogo (±60 m) fica no meio
const layout = JSON.parse(readFileSync(new URL('../godot/data/match_layout.json', import.meta.url), 'utf8'));

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

const buildings = [];
const containers = [];
const resources = [];
const roads = [];
let containerSeq = 0;
let resourceSeq = 0;

function addContainer(type, x, z, y = 0) {
	containers.push({ id: 'k' + containerSeq++, type, p: [r1(x), r1(y), r1(z)] });
}

const HOUSE_COLORS = ['#b9a58a', '#9fb0a8', '#c2b49c', '#a89a8c', '#b7a07a', '#8f9e8a', '#c9b8a6'];

/**
 * Prédio oco com porta de 2 m no meio da parede +Z (igual aos prédios do mapa
 * original). `inside` lista os recipientes: [tipo, posição relativa].
 */
function addBuilding(name, kind, x, z, w, d, h, color, inside) {
	buildings.push({ name, kind, center: [r1(x), r1(z)], size: [w, d], height: h, color });
	for (const [type, dx, dz] of inside) addContainer(type, x + dx, z + dz);
}

/** Casa: geladeira e armário no fundo, guarda-roupa num canto; às vezes remédios ou ferramentas. */
function house(name, x, z) {
	const w = pick([8, 9, 10]);
	const d = pick([8, 9]);
	const backZ = -d / 2 + 0.75;
	const inside = [
		['fridge', -w / 2 + 0.9, backZ],
		['cabinet', 0, backZ],
		['wardrobe', w / 2 - 0.9, backZ + 1.6],
	];
	const roll = rand();
	if (roll < 0.3) inside.push(['medcab', -w / 2 + 0.9, backZ + 2.4]);
	else if (roll < 0.55) inside.push(['toolbox', -w / 2 + 0.9, backZ + 2.4]);
	addBuilding(name, 'house', x, z, w, d, 3.2, pick(HOUSE_COLORS), inside);
}

function town(name, cx, cz, cols, rows, extras = []) {
	let n = 1;
	for (let i = 0; i < cols; i++) {
		for (let j = 0; j < rows; j++) {
			const x = cx + (i - (cols - 1) / 2) * 17 + between(-1.5, 1.5);
			const z = cz + (j - (rows - 1) / 2) * 17 + between(-1.5, 1.5);
			if (extras.some((e) => Math.abs(e.x - x) < 14 && Math.abs(e.z - z) < 14)) continue;
			house(`${name} — Casa ${n++}`, x, z);
		}
	}
	for (const e of extras) addBuilding(e.name, e.kind, e.x, e.z, e.w, e.d, e.h, e.color, e.inside);
}

// --- Cidades -----------------------------------------------------------------
const towns = [
	{ name: 'Vila Rosário', x: -150, z: -150 },
	{ name: 'Bairro Novo', x: 40, z: -170 },
	{ name: 'Posto Rodovia', x: 168, z: -30 },
	{ name: 'Fazenda Boa Vista', x: -165, z: 145 },
	{ name: 'Base Militar', x: 170, z: 168 },
	{ name: 'Vila Pesqueira', x: -20, z: 172 },
	{ name: 'Hospital São Lucas', x: -172, z: -8 },
];

town('Vila Rosário', -150, -150, 3, 3, [
	{ name: 'Farmácia Rosário', kind: 'shop', x: -150, z: -150, w: 12, d: 10, h: 3.6, color: '#d9dfe3', inside: [['medcab', -4.5, -4.2], ['medcab', 0, -4.2], ['shelf', 4.5, -4.2], ['shelf', -4.8, 0.5]] },
]);
town('Bairro Novo', 40, -170, 4, 2, [
	{ name: 'Mercadinho Bom Preço', kind: 'shop', x: 40 + 8.5, z: -170, w: 14, d: 10, h: 3.8, color: '#c8a46a', inside: [['shelf', -5, -4.2], ['shelf', 0, -4.2], ['shelf', 5, -4.2], ['fridge', -6, 0], ['cabinet', 6, 0]] },
]);
// Posto: loja de conveniência e oficina, mais duas casas.
addBuilding('Posto Rodovia — Conveniência', 'shop', 168, -38, 12, 9, 3.6, '#e2d7b3', [['shelf', -4.5, -3.7], ['shelf', 0, -3.7], ['fridge', 4.6, -3.7], ['cabinet', 4.6, 0], ['fuel', -4.8, 0.2]]);
addBuilding('Posto Rodovia — Oficina', 'garage', 186, -38, 12, 10, 4.5, '#9a9488', [['toolbox', -4.6, -4.2], ['toolbox', 0, -4.2], ['car_trunk', 4.2, -2.5], ['fuel', -4.8, 1.0], ['fuel', 4.8, 1.6]]);
house('Posto Rodovia — Casa 1', 152, -14);
house('Posto Rodovia — Casa 2', 172, -10);
// Fazenda: sede, dois celeiros.
addBuilding('Fazenda Boa Vista — Sede', 'house', -165, 140, 14, 10, 3.6, '#c9a97c', [['fridge', -6, -4.2], ['cabinet', -2, -4.2], ['wardrobe', 6, -4.2], ['medcab', 6, 0]]);
addBuilding('Fazenda Boa Vista — Celeiro', 'barn', -145, 160, 16, 12, 6, '#8e3b2e', [['toolbox', -6.5, -5.2], ['toolbox', 6.5, -5.2], ['wardrobe', 0, -5.2], ['fuel', -6.8, 0]]);
addBuilding('Fazenda Boa Vista — Galpão', 'barn', -185, 162, 12, 10, 5, '#7c6650', [['toolbox', -4.5, -4.2], ['car_trunk', 3.5, -2]]);
// Base militar: alojamentos com caixas militares e armário de armas.
for (let i = 0; i < 3; i++) {
	addBuilding(`Base Militar — Alojamento ${i + 1}`, 'military', 152 + i * 18, 160, 12, 10, 3.6, '#6f7a5a', [
		['military', -4.6, -4.2],
		[i === 1 ? 'gun_locker' : 'military', 0, -4.2],
		['medcab', 4.6, -4.2],
	]);
}
addBuilding('Base Militar — Arsenal', 'military', 170, 184, 10, 8, 3.6, '#5d6650', [['gun_locker', -3.6, -3.2], ['gun_locker', 0, -3.2], ['military', 3.6, -3.2], ['fuel', -3.8, 0.4]]);
town('Vila Pesqueira', -20, 172, 3, 2, [
	{ name: 'Delegacia', kind: 'police', x: -20 + 17, z: 172 - 8.5, w: 12, d: 10, h: 3.6, color: '#7f93a8', inside: [['gun_locker', -4.6, -4.2], ['gun_locker', 0, -4.2], ['cabinet', 4.6, -4.2], ['medcab', 4.8, 0]] },
]);
addBuilding('Hospital São Lucas', 'hospital', -172, -8, 24, 16, 6, '#e6e8e6', [
	['medcab', -10.5, -7.2], ['medcab', -5, -7.2], ['medcab', 5, -7.2], ['medcab', 10.5, -7.2], ['cabinet', -10.5, 0], ['fridge', 10.5, 0],
]);

// Cidade do meio (mapa original): um recipiente por construção e na torre.
const CENTRAL_TYPES = { 'CASA 01': 'wardrobe', 'CASA 02': 'fridge', 'CASA 03': 'cabinet', 'CASA 04': 'medcab', MERCADO: 'shelf', OFICINA: 'toolbox', GALPAO: 'toolbox', ESCRITORIO: 'gun_locker' };
for (const b of layout.buildings) addContainer(CENTRAL_TYPES[b.name] || 'cabinet', b.loot[0], b.loot[1]);
if (layout.tower?.loot) addContainer('military', layout.tower.loot[0], layout.tower.loot[2], layout.tower.loot[1]);
layout.outdoor_loot.forEach(([x, z], i) => addContainer(i % 3 === 0 ? 'military' : 'car_trunk', x, z));

// --- Estradas: de cada cidade até a borda da cidade do meio ---------------------
for (const t of towns) {
	const len = Math.hypot(t.x, t.z);
	const edge = 62 / Math.max(Math.abs(t.x / len), Math.abs(t.z / len)); // até o anel do mapa original
	roads.push({ from: [r1((t.x / len) * edge), r1((t.z / len) * edge)], to: [t.x, t.z], width: 7 });
}
// Uma rodovia ligando cidades vizinhas em anel.
const ring = [0, 1, 2, 4, 5, 3, 6];
for (let i = 0; i < ring.length; i++) {
	const a = towns[ring[i]];
	const b = towns[ring[(i + 1) % ring.length]];
	roads.push({ from: [a.x, a.z], to: [b.x, b.z], width: 6 });
}

// --- Ocupação: evita árvores/pedras dentro de prédios e estradas -----------------
function segmentDistance(px, pz, [ax, az], [bx, bz]) {
	const dx = bx - ax;
	const dz = bz - az;
	const t = Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz || 1)));
	return Math.hypot(px - (ax + t * dx), pz - (az + t * dz));
}
function blocked(x, z, margin) {
	if (Math.abs(x) > HALF - 6 || Math.abs(z) > HALF - 6) return true;
	if (Math.abs(x) < CENTER_CLEAR + margin && Math.abs(z) < CENTER_CLEAR + margin) return true;
	for (const b of buildings) {
		if (Math.abs(x - b.center[0]) < b.size[0] / 2 + margin + 1.5 && Math.abs(z - b.center[1]) < b.size[1] / 2 + margin + 4) return true;
	}
	for (const r of roads) if (segmentDistance(x, z, r.from, r.to) < r.width / 2 + margin) return true;
	for (const res of resources) if (Math.hypot(res.p[0] - x, res.p[2] - z) < margin + 1.2) return true;
	for (const v of vehicles) if (Math.hypot(v.p[0] - x, v.p[2] - z) < margin + 4) return true;
	return false;
}
function addResource(kind, x, z, yaw = 0) {
	resources.push({ id: 'r' + resourceSeq++, kind, p: [r1(x), 0, r1(z)], yaw: r1(yaw) });
}

// Carros que funcionam (precisam de gasolina): no acostamento, perto das cidades,
// alinhados com a estrada. Dois por estrada que sai da cidade do meio.
const vehicles = [];
const VEHICLE_KINDS = ['sedan', 'pickup', 'hatch'];
const VEHICLE_COLORS = ['#8c1d18', '#1f3d6b', '#d8d4cc', '#2b2b2b', '#4f6a3c', '#b8892f', '#5d6770'];
towns.forEach((t, ti) => {
	const r = roads[ti]; // estradas do centro até cada cidade, na mesma ordem
	const length = Math.hypot(r.to[0] - r.from[0], r.to[1] - r.from[1]);
	const nx = -(r.to[1] - r.from[1]) / length;
	const nz = (r.to[0] - r.from[0]) / length;
	for (const [t0, side] of [[0.12, 1], [0.78, -1]]) {
		const x = r.from[0] + (r.to[0] - r.from[0]) * t0 + nx * side * (r.width / 2 + 1.6);
		const z = r.from[1] + (r.to[1] - r.from[1]) * t0 + nz * side * (r.width / 2 + 1.6);
		if (buildings.some((b) => Math.abs(x - b.center[0]) < b.size[0] / 2 + 4 && Math.abs(z - b.center[1]) < b.size[1] / 2 + 6)) continue;
		const yaw = Math.atan2(-(r.to[0] - r.from[0]), -(r.to[1] - r.from[1])); // frente (-Z) para a cidade
		vehicles.push({ id: 'v' + vehicles.length, kind: VEHICLE_KINDS[vehicles.length % 3], color: VEHICLE_COLORS[vehicles.length % VEHICLE_COLORS.length], p: [r1(x), 0, r1(z)], yaw: Math.round(yaw * 100) / 100 });
	}
});

// Carros abandonados ao longo das estradas (sucata); um em cada três tem porta-malas.
for (const r of roads) {
	const length = Math.hypot(r.to[0] - r.from[0], r.to[1] - r.from[1]);
	const count = Math.floor(length / 38);
	for (let i = 0; i < count; i++) {
		const t = between(0.1, 0.9);
		const side = rand() < 0.5 ? -1 : 1;
		const nx = -(r.to[1] - r.from[1]) / length;
		const nz = (r.to[0] - r.from[0]) / length;
		const x = r.from[0] + (r.to[0] - r.from[0]) * t + nx * side * (r.width / 2 + 2.2);
		const z = r.from[1] + (r.to[1] - r.from[1]) * t + nz * side * (r.width / 2 + 2.2);
		if (Math.abs(x) < CENTER_CLEAR + 4 && Math.abs(z) < CENTER_CLEAR + 4) continue;
		if (buildings.some((b) => Math.abs(x - b.center[0]) < b.size[0] / 2 + 4 && Math.abs(z - b.center[1]) < b.size[1] / 2 + 6)) continue;
		if (vehicles.some((v) => Math.hypot(v.p[0] - x, v.p[2] - z) < 9)) continue;
		const yaw = Math.atan2(r.to[0] - r.from[0], r.to[1] - r.from[1]) + between(-0.5, 0.5);
		addResource('car', x, z, yaw);
		if (resources.length % 3 === 0) addContainer('car_trunk', x - Math.sin(yaw) * 2.6, z - Math.cos(yaw) * 2.6);
	}
}
// Florestas: aglomerados de árvores, com rochas e arbustos de frutas espalhados.
const forests = [];
for (let f = 0; f < 34; f++) {
	let x;
	let z;
	let tries = 0;
	do {
		x = between(-HALF + 20, HALF - 20);
		z = between(-HALF + 20, HALF - 20);
	} while (blocked(x, z, 12) && ++tries < 60);
	if (tries >= 60) continue;
	const radius = between(14, 30);
	forests.push({ x: r1(x), z: r1(z), r: r1(radius) });
	const trees = Math.floor(radius * 1.4);
	for (let i = 0; i < trees; i++) {
		const a = rand() * Math.PI * 2;
		const d = Math.sqrt(rand()) * radius;
		const tx = x + Math.cos(a) * d;
		const tz = z + Math.sin(a) * d;
		if (!blocked(tx, tz, 1.5)) addResource('tree', tx, tz, rand() * 6.28);
	}
}
function scatter(kind, count, margin) {
	for (let i = 0, tries = 0; i < count && tries < count * 40; tries++) {
		const x = between(-HALF + 10, HALF - 10);
		const z = between(-HALF + 10, HALF - 10);
		if (blocked(x, z, margin)) continue;
		addResource(kind, x, z, rand() * 6.28);
		i++;
	}
}
scatter('tree', 300, 2);
scatter('rock', 80, 2);
scatter('bush', 70, 2);

// --- Grama alta: manchas onde dá para se esconder agachado (o jogo e os zumbis usam) ---
const grass = [];
function grassFree(x, z, r) {
	if (Math.abs(x) > HALF - 8 || Math.abs(z) > HALF - 8) return false;
	if (Math.abs(x) < CENTER_CLEAR + r && Math.abs(z) < CENTER_CLEAR + r) return false;
	for (const b of buildings) {
		if (Math.abs(x - b.center[0]) < b.size[0] / 2 + r + 2 && Math.abs(z - b.center[1]) < b.size[1] / 2 + r + 5) return false;
	}
	for (const road of roads) if (segmentDistance(x, z, road.from, road.to) < road.width / 2 + r * 0.7) return false;
	return true;
}
// Campos grandes entre as cidades e bordas das florestas.
for (let i = 0, tries = 0; grass.length < 150 && tries < 6000; tries++) {
	const nearForest = i % 3 === 0 && forests.length;
	let x;
	let z;
	if (nearForest) {
		const f = pick(forests);
		const a = rand() * Math.PI * 2;
		x = f.x + Math.cos(a) * (f.r + between(2, 10));
		z = f.z + Math.sin(a) * (f.r + between(2, 10));
	} else {
		x = between(-HALF + 15, HALF - 15);
		z = between(-HALF + 15, HALF - 15);
	}
	const r = between(5, 13);
	if (!grassFree(x, z, r)) continue;
	grass.push({ x: r1(x), z: r1(z), r: r1(r) });
	i++;
}

// --- Nascimento dos jogadores: campo aberto, longe das cidades -------------------
const spawns = [];
for (let i = 0, tries = 0; spawns.length < 16 && tries < 4000; tries++) {
	const a = (spawns.length / 16) * Math.PI * 2 + between(-0.15, 0.15);
	const d = between(95, 200);
	const x = Math.cos(a) * d;
	const z = Math.sin(a) * d;
	if (blocked(x, z, 6)) continue;
	if (towns.some((t) => Math.hypot(t.x - x, t.z - z) < 40)) continue;
	spawns.push([r1(x), r1(z)]);
	i++;
}

// --- Onde os zumbis aparecem (peso maior = mais zumbis) ---------------------------
const zombie_zones = [
	{ x: 0, z: 0, r: 55, weight: 3 },
	...towns.map((t) => ({ x: t.x, z: t.z, r: 30, weight: t.name.startsWith('Base') || t.name.startsWith('Hospital') ? 5 : 3 })),
	...forests.slice(0, 8).map((f) => ({ x: f.x, z: f.z, r: f.r, weight: 1 })),
];

const world = {
	_comment: 'Gerado por scripts/gen-survival-world.mjs (não edite à mão). Coordenadas em metros, [x, z] no chão; p = [x, y, z]. Portas dos prédios na parede +Z.',
	seed: SEED,
	half_size: HALF,
	center_town: { half_size: 60 },
	towns: towns.map((t) => ({ name: t.name, center: [t.x, t.z] })),
	buildings,
	roads,
	containers,
	resources,
	spawns,
	zombie_zones,
	grass,
	vehicles,
};
writeFileSync(new URL('../godot/data/survival_world.json', import.meta.url), JSON.stringify(world, null, 1) + '\n');
console.log(`${buildings.length} prédios, ${containers.length} recipientes, ${resources.length} recursos (${resources.filter((r) => r.kind === 'tree').length} árvores), ${grass.length} manchas de grama alta, ${vehicles.length} carros que funcionam, ${spawns.length} nascimentos, ${roads.length} estradas`);
