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

// --- Minérios (era do metal): veios de ferro em grupos e rochas de salitre raras -----
// Gerados por último para não mudar os ids nem as posições do resto do mapa.
for (let v = 0; v < 9; v++) {
	const base = pick(rocks);
	for (let i = 0; i < 4; i++) {
		for (let tries = 0; tries < 12; tries++) {
			const a = rand() * Math.PI * 2;
			const d = between(3, 12);
			if (place('ore', base.p[0] + Math.cos(a) * d, base.p[2] + Math.sin(a) * d, 1.5)) break;
		}
	}
}
scatter('ore', 14, 1.5, (x, z) => !inClearing(x, z));
scatter('saltpeter', 22, 1.4, (x, z) => !inClearing(x, z));

// --- Cidades abandonadas (era da sucata): três, nas pontas do mapa ---------------
// Geradas depois da natureza para não mudar ids nem posições do resto; o que cair
// dentro de uma cidade ou de uma estrada é tirado no fim.
// Prédios são ocos com a porta na parede +Z (o jogo monta igual aos mapas antigos),
// então as casas ficam no lado norte (-Z) de cada rua, com a porta virada para ela.
const buildings = [];
const containers = [];
const roads = [];
const vehicles = [];
const towns = [];
let containerSeq = 0;
const addContainer = (type, x, z, y = 0) => containers.push({ id: 'k' + containerSeq++, type, p: [r1(x), r1(y), r1(z)] });
// Paredes em tons escuros e gastos (estilo urbano escuro do resto do jogo).
const HOUSE_COLORS = ['#5c564d', '#4f5552', '#5a5148', '#4b4f4a', '#605a50', '#474c50', '#55504a'];
const CITY_SPECIALS = {
	garage: { label: 'Oficina', kind: 'garage', w: 13, d: 10, h: 4.5, color: '#4a4a46', inside: [['toolbox', -4.8, -4.2], ['toolbox', 0, -4.2], ['car_trunk', 4.6, -2.6], ['fuel', -5.2, 1.2]] },
	police: { label: 'Delegacia', kind: 'police', w: 12, d: 10, h: 3.8, color: '#3f4a55', inside: [['gun_locker', -4.6, -4.2], ['gun_locker', 0, -4.2], ['cabinet', 4.6, -4.2], ['medcab', 4.8, 0.2]] },
	pharmacy: { label: 'Farmácia', kind: 'shop', w: 11, d: 9, h: 3.6, color: '#5d6466', inside: [['medcab', -4, -3.7], ['medcab', 0, -3.7], ['shelf', 4, -3.7], ['shelf', -4.2, 0.6]] },
	market: { label: 'Mercado', kind: 'shop', w: 13, d: 10, h: 3.8, color: '#5a5040', inside: [['shelf', -5, -4.2], ['shelf', 0, -4.2], ['shelf', 5, -4.2], ['fridge', -5.6, 0.4], ['cabinet', 5.4, 0.4]] },
	school: { label: 'Escola', kind: 'shop', w: 14, d: 10, h: 3.8, color: '#575247', inside: [['cabinet', -5.4, -4.2], ['wardrobe', 0, -4.2], ['cabinet', 5.4, -4.2], ['medcab', -5.6, 0.4]] },
};
const CITY_PLANS = [
	{ name: 'Vila Ferrugem', angle: Math.PI * 0.5, specials: { '0,0': 'garage', '2,3': 'police', '1,1': 'market' } },
	{ name: 'Pedra Branca', angle: Math.PI * (0.5 + 2 / 3), specials: { '1,0': 'garage', '0,3': 'pharmacy', '2,2': 'school' } },
	{ name: 'Porto Cinza', angle: Math.PI * (0.5 + 4 / 3), specials: { '2,1': 'garage', '1,2': 'police', '0,0': 'pharmacy' } },
];
const STREET_GAP = 24; // entre as ruas (eixo Z)
const HOUSE_X = [-36, -18, 18, 36]; // casas de cada rua; a avenida passa no meio (x = 0)
const CITY_HALF_X = 46;
const CITY_HALF_Z = STREET_GAP + 16;
const CAR_KINDS = ['sedan', 'pickup', 'hatch'];
const CAR_COLORS = ['#5a2420', '#253a52', '#6b6a62', '#33452f', '#6a5e40', '#8e8a80', '#232323'];

/** Centro da cidade: na direção `angle`, o mais longe do meio que couber, longe de lagos e nascimentos. */
function cityCenter(angle) {
	for (let tries = 0; tries < 400; tries++) {
		const a = angle + (tries % 2 ? 1 : -1) * Math.floor(tries / 2) * 0.02;
		const dist = HALF - 62 - (tries % 7) * 6;
		const x = Math.cos(a) * dist;
		const z = Math.sin(a) * dist;
		if (Math.abs(x) > HALF - CITY_HALF_X - 10 || Math.abs(z) > HALF - CITY_HALF_Z - 10) continue;
		const pondHit = ponds.some((p) => Math.abs(p.x - x) < CITY_HALF_X + p.r + 6 && Math.abs(p.z - z) < CITY_HALF_Z + p.r + 6);
		const spawnHit = spawns.some(([sx, sz]) => Math.abs(sx - x) < CITY_HALF_X + 25 && Math.abs(sz - z) < CITY_HALF_Z + 25);
		if (!pondHit && !spawnHit) return [Math.round(x), Math.round(z)];
	}
	throw new Error('cidade não coube no mapa');
}

function addCar(x, z, yaw) {
	addResource('car', x, z, { yaw: r1(yaw) });
}

for (const [ci, plan] of CITY_PLANS.entries()) {
	const [cx, cz] = cityCenter(plan.angle);
	towns.push({ name: plan.name, center: [cx, cz] });
	// Ruas leste-oeste e a avenida norte-sul no meio.
	const streetZ = [cz - STREET_GAP, cz, cz + STREET_GAP].map((z) => z + 8);
	for (const z of streetZ) roads.push({ from: [cx - CITY_HALF_X, z], to: [cx + CITY_HALF_X, z], width: 7 });
	roads.push({ from: [cx, cz - CITY_HALF_Z], to: [cx, cz + CITY_HALF_Z + 8], width: 8 });
	let n = 1;
	streetZ.forEach((sz, row) => {
		HOUSE_X.forEach((dx, col) => {
			const x = cx + dx + between(-1, 1);
			const special = CITY_SPECIALS[plan.specials[`${row},${col}`]];
			if (special) {
				const z = sz - 3.5 - special.d / 2 - 1.2;
				buildings.push({ name: `${plan.name} — ${special.label}`, kind: special.kind, center: [r1(x), r1(z)], size: [special.w, special.d], height: special.h, color: special.color });
				for (const [type, ox, oz] of special.inside) addContainer(type, x + ox, z + oz);
				return;
			}
			const w = pick([8, 9, 10]);
			const d = pick([8, 9]);
			const z = sz - 3.5 - d / 2 - 1.2;
			const back = z - d / 2 + 0.75;
			buildings.push({ name: `${plan.name} — Casa ${n++}`, kind: 'house', center: [r1(x), r1(z)], size: [w, d], height: 3.2, color: pick(HOUSE_COLORS) });
			addContainer('fridge', x - w / 2 + 0.9, back);
			addContainer('cabinet', x, back);
			addContainer('wardrobe', x + w / 2 - 0.9, back + 1.6);
			const roll = rand();
			if (roll < 0.25) addContainer('medcab', x - w / 2 + 0.9, back + 2.4);
			else if (roll < 0.5) addContainer('toolbox', x - w / 2 + 0.9, back + 2.4);
		});
		// Carros velhos largados do lado sul da rua (sem casas); um em cada três com porta-malas.
		for (const dx of [-38, -24, -10, 14, 28, 40]) {
			if (rand() < 0.3) continue;
			const x = cx + dx + between(-2, 2);
			const z = sz + 5.2;
			const yaw = (rand() < 0.5 ? Math.PI * 0.5 : -Math.PI * 0.5) + between(-0.35, 0.35);
			addCar(x, z, yaw);
			if (rand() < 0.35) addContainer('car_trunk', x + Math.sin(yaw) * 2.7, z + Math.cos(yaw) * 2.7);
		}
	});
	// Um carro que ainda funciona por cidade (raro): estacionado na avenida.
	const vz = cz + STREET_GAP * 0.5 + 8;
	vehicles.push({ id: 'v' + ci, kind: CAR_KINDS[ci % 3], color: CAR_COLORS[(ci * 3) % CAR_COLORS.length], p: [r1(cx + 5.6), 0, r1(vz)], yaw: 0 });
}

const segmentDistance = (px, pz, [ax, az], [bx, bz]) => {
	const dx = bx - ax;
	const dz = bz - az;
	const t = Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz || 1)));
	return Math.hypot(px - (ax + t * dx), pz - (az + t * dz));
};
const inCity = (x, z, margin) => towns.some(({ center: [cx, cz] }) => Math.abs(x - cx) < CITY_HALF_X + margin && Math.abs(z - cz) < CITY_HALF_Z + 8 + margin);
const onRoad = (x, z, margin) => roads.some((r) => segmentDistance(x, z, r.from, r.to) < r.width / 2 + margin);
// Rodovia velha ligando as três cidades: sai pela ponta da avenida (norte ou sul,
// a mais perto da outra cidade), anda 16 m reto e segue até a outra, desviando de
// lagos e de cidades por um ponto do meio deslocado para o lado.
const avenueExit = ([cx, cz], [tx, tz]) => {
	const north = tz < cz;
	const end = north ? [cx, cz - CITY_HALF_Z] : [cx, cz + CITY_HALF_Z + 8];
	return [end, [end[0], end[1] + (north ? -16 : 16)]];
};
const segmentClear = (a, b, width) => !ponds.some((p) => segmentDistance(p.x, p.z, a, b) < p.r + width / 2 + 3)
	&& !towns.some(({ center: [cx, cz] }) => {
		for (let t = 0.04; t < 0.97; t += 0.02) {
			const x = a[0] + (b[0] - a[0]) * t;
			const z = a[1] + (b[1] - a[1]) * t;
			if (Math.abs(x - cx) < CITY_HALF_X + 2 && Math.abs(z - cz) < CITY_HALF_Z + 6) return true;
		}
		return false;
	});
const highways = [];
for (let i = 0; i < towns.length; i++) {
	const a = towns[i].center;
	const b = towns[(i + 1) % towns.length].center;
	const [aEnd, aOut] = avenueExit(a, b);
	const [bEnd, bOut] = avenueExit(b, a);
	let path = null;
	for (let k = 0; k < 40 && !path; k++) {
		const offset = (k % 2 ? 1 : -1) * Math.ceil(k / 2) * 12;
		const len = Math.hypot(bOut[0] - aOut[0], bOut[1] - aOut[1]);
		const mid = [(aOut[0] + bOut[0]) / 2 - ((bOut[1] - aOut[1]) / len) * offset, (aOut[1] + bOut[1]) / 2 + ((bOut[0] - aOut[0]) / len) * offset];
		const points = offset === 0 ? [aOut, bOut] : [aOut, mid, bOut];
		if (points.slice(1).every((p, j) => segmentClear(points[j], p, 6))) path = points;
	}
	if (!path) throw new Error('rodovia sem caminho livre');
	const all = [aEnd, ...path, bEnd].map(([x, z]) => [r1(x), r1(z)]);
	for (let j = 1; j < all.length; j++) {
		const r = { from: all[j - 1], to: all[j], width: 6 };
		roads.push(r);
		highways.push(r);
	}
}
for (const r of highways) {
	const length = Math.hypot(r.to[0] - r.from[0], r.to[1] - r.from[1]);
	const nx = -(r.to[1] - r.from[1]) / length;
	const nz = (r.to[0] - r.from[0]) / length;
	for (let t = 0.12; t < 0.9; t += between(0.07, 0.13)) {
		const side = rand() < 0.5 ? -1 : 1;
		const x = r.from[0] + (r.to[0] - r.from[0]) * t + nx * side * (r.width / 2 + 2.2);
		const z = r.from[1] + (r.to[1] - r.from[1]) * t + nz * side * (r.width / 2 + 2.2);
		if (inCity(x, z, 6) || inWater(x, z, 3)) continue;
		addCar(x, z, Math.atan2(r.to[0] - r.from[0], r.to[1] - r.from[1]) + between(-0.6, 0.6));
	}
}
// Tira a natureza de dentro das cidades e de cima das estradas (os carros ficam).
const before = resources.length;
for (let i = resources.length - 1; i >= 0; i--) {
	const res = resources[i];
	if (res.kind === 'car' || res.kind === 'pond') continue;
	const [x, , z] = res.p;
	if (inCity(x, z, 4) || onRoad(x, z, res.kind === 'tree' ? 2.2 : 1.2)) resources.splice(i, 1);
}
const cleared = before - resources.length;
const keptGrass = grass.filter((g) => !inCity(g.x, g.z, g.r) && !roads.some((r) => segmentDistance(g.x, g.z, r.from, r.to) < r.width / 2 + g.r * 0.7));
grass.length = 0;
grass.push(...keptGrass);
// Zumbis: as cidades têm zumbis até de dia ('day'); no resto, só à noite.
const zombie_zones = towns.map(({ center: [x, z] }) => ({ x, z, r: 50, weight: 4, day: true }));

const world = {
	_comment: 'Gerado por scripts/gen-survival-world.mjs (não edite à mão). Coordenadas em metros, [x, z] no chão; p = [x, y, z]. Natureza no mapa todo e três cidades abandonadas nas pontas (carros velhos = sucata). Portas dos prédios na parede +Z.',
	seed: SEED,
	half_size: HALF,
	ponds,
	resources,
	spawns,
	grass,
	// Cidades: zumbis também de dia; no mato, só à noite em volta dos jogadores.
	zombie_zones,
	towns,
	buildings,
	roads,
	containers,
	vehicles,
	parkour: [],
	parkour_bases: [],
};
writeFileSync(new URL('../godot/data/survival_world.json', import.meta.url), JSON.stringify(world, null, 1) + '\n');
const count = (kind) => resources.filter((r) => r.kind === kind).length;
console.log(`${count('tree')} árvores, ${count('rock')} rochas, ${count('bush')} arbustos, ${count('stick')} galhos, ${count('pebble')} pedrinhas, ${count('fiber')} capins, ${count('herb')} ervas, ${count('ore')} veios de ferro, ${count('saltpeter')} rochas de salitre, ${towns.length} cidades (${buildings.length} prédios, ${containers.length} recipientes, ${count('car')} carros velhos, ${vehicles.length} que andam; ${cleared} recursos tirados), ${ponds.length} lagos, ${grass.length} manchas de grama alta, ${spawns.length} nascimentos`);
