// Construção da Sobrevivência: peças numa grade de 3 m (fundação, paredes,
// piso/teto, escada, telhado, porta) e peças livres (fogueira, baú, cama).
// Só a geometria e as regras de apoio moram aqui; o Durable Object
// (godot-survival.js) cuida de materiais, dono, rede e armazenamento.
// O jogo repete as mesmas contas em godot/scripts/survival/building_rules.gd.
//
// Grade: a célula (i, j) cobre x ∈ [i·S, (i+1)·S] e z ∈ [j·S, (j+1)·S].
// Andar k: o chão fica em base + story·k (k = 0 é o topo da fundação).
// Bordas: 'h' (i, j) é o lado z = j·S de x = i·S a (i+1)·S; 'v' (i, j) é o
// lado x = i·S de z = j·S a (j+1)·S.
//
// Terreno com relevo: cada peça da grade tem um degrau `b` (inteiro, LIFT m
// cada) somado à altura do andar. A fundação fica logo acima do ponto mais
// alto do chão embaixo dela e ganha um pilar de pedra até o ponto mais baixo;
// o que vai em cima herda o mesmo degrau. Peças com degraus diferentes não se
// apoiam umas nas outras.

export const EDGE_KINDS = ['wall', 'doorway', 'window'];
const FLOORS = ['floor']; // pisos que seguram parede/escada/peça livre (telhado não)
const MAX_LEVEL = 6;
const MAX_CELL = 400; // |i|, |j| (o mundo tem ~240 m de meia largura)
export const LIFT = 0.25; // altura de um degrau `b`
export const MAX_LIFT = 160; // |b| (40 m)
export const MAX_PILLAR = 8; // altura máxima do topo da fundação até o chão mais baixo
const FREE_R = 0.5; // raio padrão do pé de uma peça livre

/** Degrau da peça (peças antigas não têm: 0). */
export const liftOf = (p) => (Number.isInteger(p?.b) ? p.b : 0);

export class BuildGrid {
	constructor(rules, defs, ground = () => 0) {
		this.ground = ground; // altura do chão em (x, z)
		this.S = rules.cell;
		this.H = rules.story;
		this.base = rules.base;
		this.defs = defs;
		this.pieces = new Map(); // id -> peça
		this.slots = new Map(); // chave do lugar -> id
	}

	// ------------------------------------------------------------ geometria ---

	top(k, b = 0) {
		return this.base + this.H * k + LIFT * b;
	}

	/** Chão mais baixo e mais alto num retângulo (amostras 5×5). */
	groundSpan(x0, z0, x1, z1) {
		let lo = Infinity;
		let hi = -Infinity;
		for (let a = 0; a <= 4; a++) {
			for (let c = 0; c <= 4; c++) {
				const h = this.ground(x0 + ((x1 - x0) * a) / 4, z0 + ((z1 - z0) * c) / 4);
				lo = Math.min(lo, h);
				hi = Math.max(hi, h);
			}
		}
		return [lo, hi];
	}

	cellGround(i, j) {
		const { S } = this;
		return this.groundSpan(i * S, j * S, (i + 1) * S, (j + 1) * S);
	}

	/** Menor degrau de uma fundação em (i, j): topo `base` acima do chão mais alto. */
	foundationLift(i, j) {
		return Math.max(-MAX_LIFT, Math.ceil(this.cellGround(i, j)[1] / LIFT - 1e-6));
	}

	/** Chão sob o pé de uma peça livre. */
	freeGround(p) {
		const r = this.defs[p.kind]?.r || FREE_R;
		return this.groundSpan(p.p[0] - r, p.p[2] - r, p.p[0] + r, p.p[2] + r);
	}

	static cellKey(i, j, k) {
		return `c:${i}:${j}:${k}`;
	}

	static edgeKey(o, i, j, k) {
		return `e:${o}:${i}:${j}:${k}`;
	}

	slotOf(p) {
		const slot = this.defs[p.kind]?.slot;
		if (slot === 'cell') return BuildGrid.cellKey(p.i, p.j, p.k);
		if (slot === 'edge') return BuildGrid.edgeKey(p.o, p.i, p.j, p.k);
		if (slot === 'door') return `d:${p.o}:${p.i}:${p.j}:${p.k}`;
		if (slot === 'stairs') return `s:${p.i}:${p.j}:${p.k}`;
		return null; // peça livre: sem lugar fixo
	}

	at(key) {
		const id = this.slots.get(key);
		return id ? this.pieces.get(id) : null;
	}

	/** As duas células encostadas numa borda. */
	static edgeCells(o, i, j) {
		return o === 'h' ? [[i, j - 1], [i, j]] : [[i - 1, j], [i, j]];
	}

	/** As quatro bordas de uma célula. */
	static cellEdges(i, j) {
		return [['h', i, j], ['h', i, j + 1], ['v', i, j], ['v', i + 1, j]];
	}

	/** Centro da peça (alcance de quem constrói e de quem bate). */
	center(p) {
		const { S } = this;
		const slot = this.defs[p.kind]?.slot;
		if (slot === 'free') return p.p;
		if (slot === 'edge' || slot === 'door') {
			const x = p.o === 'h' ? (p.i + 0.5) * S : p.i * S;
			const z = p.o === 'h' ? p.j * S : (p.j + 0.5) * S;
			return [x, this.top(p.k, liftOf(p)) + (slot === 'door' ? 1.1 : this.H / 2), z];
		}
		const y = slot === 'stairs' ? this.top(p.k, liftOf(p)) + this.H / 2 : this.top(p.k, liftOf(p)) - 0.2;
		return [(p.i + 0.5) * S, y, (p.j + 0.5) * S];
	}

	/** Distância (no chão) de um ponto até a peça; null se a altura não bate. */
	distance(p, point) {
		const { S } = this;
		const slot = this.defs[p.kind]?.slot;
		const [x, y, z] = point;
		if (slot === 'free') return Math.abs(y - p.p[1]) > 3 ? null : Math.hypot(x - p.p[0], z - p.p[2]);
		// Piso/teto: dá para bater de baixo (dentro de casa) e de cima.
		const t = this.top(p.k, liftOf(p));
		const low = slot === 'cell' ? t - this.H - 0.3 : t - 2.2;
		const high = t + (slot === 'cell' ? 2.4 : this.H + 0.5);
		if (y < low || y > high) return null;
		if (slot === 'edge' || slot === 'door') {
			const [ax, az, bx, bz] = p.o === 'h' ? [p.i * S, p.j * S, (p.i + 1) * S, p.j * S] : [p.i * S, p.j * S, p.i * S, (p.j + 1) * S];
			const t = Math.max(0, Math.min(1, ((x - ax) * (bx - ax) + (z - az) * (bz - az)) / (S * S)));
			return Math.hypot(x - (ax + (bx - ax) * t), z - (az + (bz - az) * t));
		}
		const dx = Math.max(p.i * S - x, 0, x - (p.i + 1) * S);
		const dz = Math.max(p.j * S - z, 0, z - (p.j + 1) * S);
		return Math.hypot(dx, dz);
	}

	// --------------------------------------------------------------- apoio ---

	/** Parede/vão na borda (no degrau `b`; null = qualquer degrau). */
	edgeAt(o, i, j, k, b = null) {
		const piece = this.at(BuildGrid.edgeKey(o, i, j, k));
		return piece && EDGE_KINDS.includes(piece.kind) && (b === null || liftOf(piece) === b) ? piece : null;
	}

	floorAt(i, j, k, b = null) {
		const piece = this.at(BuildGrid.cellKey(i, j, k));
		if (!piece || (b !== null && liftOf(piece) !== b)) return null;
		return (k === 0 ? piece.kind === 'foundation' : FLOORS.includes(piece.kind)) ? piece : null;
	}

	/** Paredes do andar de baixo que seguram o piso/telhado da célula. */
	wallsUnder(i, j, k, b = null) {
		return BuildGrid.cellEdges(i, j).map(([o, a, c]) => this.edgeAt(o, a, c, k - 1, b)).filter(Boolean);
	}

	/**
	 * Quem segura a peça (lista vazia = cai). Piso/telhado em balanço: vale um
	 * piso vizinho do mesmo andar que esteja apoiado em parede (uma célula só).
	 */
	supporters(p) {
		const slot = this.defs[p.kind]?.slot;
		const lift = liftOf(p);
		if (p.kind === 'foundation') return ['ground'];
		if (slot === 'cell') {
			if (p.k < 1) return [];
			const walls = this.wallsUnder(p.i, p.j, p.k, lift);
			if (walls.length) return walls;
			const out = [];
			for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
				const n = this.floorAt(p.i + di, p.j + dj, p.k, lift);
				if (n && n.kind === 'floor' && this.wallsUnder(n.i, n.j, n.k, lift).length) out.push(n);
			}
			return out;
		}
		if (slot === 'edge') {
			const out = [];
			if (p.k > 0) {
				const below = this.edgeAt(p.o, p.i, p.j, p.k - 1, lift);
				if (below) out.push(below);
			}
			for (const [a, b] of BuildGrid.edgeCells(p.o, p.i, p.j)) {
				const f = this.floorAt(a, b, p.k, lift);
				if (f) out.push(f);
			}
			return out;
		}
		if (slot === 'door') {
			const frame = this.at(BuildGrid.edgeKey(p.o, p.i, p.j, p.k));
			return frame?.kind === 'doorway' && liftOf(frame) === lift ? [frame] : [];
		}
		if (slot === 'stairs') {
			const f = this.floorAt(p.i, p.j, p.k, lift);
			return f ? [f] : [];
		}
		// Peça livre presa na parede (tocha): a parede/vão encostado nela.
		if (p.wall) return this.wallBehind(p.p);
		// Peça livre: em cima de uma fundação/piso, ou no chão (apoiada no ponto
		// mais alto embaixo dela, nunca enterrada nem dentro de uma fundação).
		const f = this.cellUnder(p.p);
		if (f && Math.abs(this.top(f.k, liftOf(f)) - p.p[1]) < 0.3) return [f];
		const [lo, hi] = this.freeGround(p);
		if (p.p[1] < lo - 0.1 || p.p[1] > hi + 0.25) return [];
		const found = this.floorAt(Math.floor(p.p[0] / this.S), Math.floor(p.p[2] / this.S), 0);
		return found && this.top(0, liftOf(found)) > p.p[1] - 0.3 ? [] : ['ground'];
	}

	/** Parede/vão encostado num ponto (tocha presa na parede): [parede] ou []. */
	wallBehind(point) {
		const [x, y, z] = point;
		for (const o of ['h', 'v']) {
			const i = o === 'h' ? Math.floor(x / this.S) : Math.round(x / this.S);
			const j = o === 'h' ? Math.round(z / this.S) : Math.floor(z / this.S);
			const gap = o === 'h' ? Math.abs(z - j * this.S) : Math.abs(x - i * this.S);
			if (gap > 0.3) continue;
			for (let k = 0; k <= MAX_LEVEL; k++) {
				const w = this.edgeAt(o, i, j, k);
				const t = w ? this.top(k, liftOf(w)) : 0;
				if (w && y >= t && y < t + this.H) return [w];
			}
		}
		return [];
	}

	/** Fundação/piso embaixo de um ponto (o mais alto que não passa do ponto). */
	cellUnder(point) {
		const i = Math.floor(point[0] / this.S);
		const j = Math.floor(point[2] / this.S);
		let best = null;
		for (let k = 0; k <= MAX_LEVEL; k++) {
			const f = this.floorAt(i, j, k);
			if (f && this.top(k, liftOf(f)) <= point[1] + 0.3) best = f;
		}
		return best;
	}

	/**
	 * Confere se a peça pode ir para lá (lugar livre, apoio, regras de cada tipo).
	 * Devolve o motivo em texto, ou '' se pode. `owns(piece)` diz se quem
	 * constrói pode se apoiar nessa peça (dono ou autorizado).
	 */
	check(p, owns = () => true) {
		const def = this.defs[p.kind];
		if (!def) return 'Peça desconhecida.';
		if (def.slot !== 'free') {
			if (![p.i, p.j].every((n) => Number.isInteger(n) && Math.abs(n) <= MAX_CELL)) return 'Fora da grade.';
			if (!Number.isInteger(p.k) || p.k < 0 || p.k > MAX_LEVEL) return 'Alto demais.';
			if ((def.slot === 'edge' || def.slot === 'door') && p.o !== 'h' && p.o !== 'v') return 'Borda inválida.';
		}
		if (def.slot === 'cell' && p.kind === 'foundation' && p.k !== 0) return 'A fundação vai no chão.';
		if (def.slot === 'cell' && p.kind !== 'foundation' && p.k < 1) return 'Piso e telhado vão em cima das paredes.';
		if (def.slot !== 'free') {
			if (p.b !== undefined && !(Number.isInteger(p.b) && Math.abs(p.b) <= MAX_LIFT)) return 'Altura inválida.';
			if (p.kind === 'foundation') {
				const [lo, hi] = this.cellGround(p.i, p.j);
				const t = this.top(0, liftOf(p));
				if (t < hi + 0.15) return 'A fundação ficaria enterrada.';
				if (t - lo > MAX_PILLAR) return 'Alto demais: o pilar não chega ao chão.';
			}
		}
		const key = this.slotOf(p);
		if (key && this.slots.has(key)) return 'Já tem uma peça aí.';
		if (def.slot === 'cell' && p.k >= 1 && this.at(`s:${p.i}:${p.j}:${p.k - 1}`)) return 'A escada passa por aqui.';
		if (def.slot === 'stairs' && this.at(BuildGrid.cellKey(p.i, p.j, p.k + 1))) return 'Tem um piso em cima: a escada não passa.';
		if (def.slot === 'edge' && p.k > 0) {
			// Parede em cima de telhado não: o telhado é a última peça.
			for (const [a, b] of BuildGrid.edgeCells(p.o, p.i, p.j)) {
				const roof = this.at(BuildGrid.cellKey(a, b, p.k));
				if (roof?.kind === 'roof' && !this.edgeAt(p.o, p.i, p.j, p.k - 1)) return 'Não dá para construir em cima do telhado.';
			}
		}
		const sup = this.supporters(p);
		if (!sup.length) {
			return {
				cell: 'Precisa de paredes embaixo (ou um piso vizinho apoiado).', edge: 'Precisa de fundação, piso ou parede embaixo.',
				door: 'Precisa de uma parede com porta.', stairs: 'Precisa de fundação ou piso embaixo.', free: 'Precisa de chão firme.',
			}[def.slot];
		}
		if (!sup.some((s) => s === 'ground' || owns(s))) return 'Essa construção é de outro jogador.';
		return '';
	}

	add(p) {
		this.pieces.set(p.id, p);
		const key = this.slotOf(p);
		if (key) this.slots.set(key, p.id);
	}

	/** Tira a peça e tudo o que só ela segurava. Devolve as peças que caíram (a primeira é ela). */
	remove(id) {
		const first = this.pieces.get(id);
		if (!first) return [];
		const gone = [];
		const queue = [first];
		const drop = (p) => {
			this.pieces.delete(p.id);
			const key = this.slotOf(p);
			if (key && this.slots.get(key) === p.id) this.slots.delete(key);
			gone.push(p);
		};
		drop(first);
		while (queue.length) {
			const p = queue.shift();
			for (const d of this.dependents(p)) {
				if (!this.pieces.has(d.id) || this.supporters(d).length) continue;
				drop(d);
				queue.push(d);
			}
		}
		return gone;
	}

	/**
	 * Degrau de uma peça da grade que veio sem `b` (cliente antigo): a fundação
	 * fica logo acima do chão; o resto copia o degrau de quem pode segurá-la.
	 */
	guessLift(p) {
		if (p.kind === 'foundation') return this.foundationLift(p.i, p.j);
		const near = [];
		const add = (piece) => piece && near.push(liftOf(piece));
		const slot = this.defs[p.kind]?.slot;
		if (slot === 'cell' || slot === 'stairs') {
			for (const [o, a, c] of BuildGrid.cellEdges(p.i, p.j)) add(this.at(BuildGrid.edgeKey(o, a, c, p.k - 1)));
			add(this.at(BuildGrid.cellKey(p.i, p.j, p.k)));
			for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) add(this.at(BuildGrid.cellKey(p.i + di, p.j + dj, p.k)));
		} else if (slot === 'edge' || slot === 'door') {
			add(this.at(BuildGrid.edgeKey(p.o, p.i, p.j, p.k)));
			add(this.at(BuildGrid.edgeKey(p.o, p.i, p.j, p.k - 1)));
			for (const [a, c] of BuildGrid.edgeCells(p.o, p.i, p.j)) add(this.at(BuildGrid.cellKey(a, c, p.k)));
		}
		for (const b of near) if (this.supporters({ ...p, b }).length) return b;
		return near.length ? near[0] : 0;
	}

	/**
	 * Construções salvas antes do relevo (sem `b`): cada grupo de células
	 * encostadas sobe junto até a fundação mais alta ficar fora do chão, e as
	 * peças livres no chão vão para cima dele. Devolve as peças mudadas.
	 */
	liftLegacy() {
		const changed = [];
		const cols = new Map(); // "i:j" -> peças antigas da grade nessa coluna (bordas nas duas)
		const touch = (i, j, piece) => {
			const key = `${i}:${j}`;
			if (!cols.has(key)) cols.set(key, []);
			cols.get(key).push(piece);
		};
		for (const p of this.pieces.values()) {
			if (p.b !== undefined || this.defs[p.kind]?.slot === 'free') continue;
			if (p.o) for (const [a, c] of BuildGrid.edgeCells(p.o, p.i, p.j)) touch(a, c, p);
			else touch(p.i, p.j, p);
		}
		const colLift = new Map();
		for (const start of cols.keys()) {
			if (colLift.has(start)) continue;
			const group = [start];
			colLift.set(start, 0);
			for (let n = 0; n < group.length; n++) {
				const [i, j] = group[n].split(':').map(Number);
				for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
					const key = `${i + di}:${j + dj}`;
					if (cols.has(key) && !colLift.has(key)) {
						colLift.set(key, 0);
						group.push(key);
					}
				}
			}
			let lift = 0;
			for (const key of group) {
				const [i, j] = key.split(':').map(Number);
				if (cols.get(key).some((p) => p.kind === 'foundation')) lift = Math.max(lift, this.foundationLift(i, j));
			}
			for (const key of group) {
				colLift.set(key, lift);
				for (const p of cols.get(key)) {
					if (p.b !== undefined) continue;
					p.b = lift;
					changed.push(p);
				}
			}
		}
		for (const p of this.pieces.values()) {
			if (p.b !== undefined || this.defs[p.kind]?.slot !== 'free' || !p.p) continue;
			const lift = colLift.get(`${Math.floor(p.p[0] / this.S)}:${Math.floor(p.p[2] / this.S)}`) || 0;
			let y = p.p[1];
			if (lift) y += lift * LIFT; // em cima de piso ou presa na parede: sobe com a casa
			else if (y < 0.25) y = Math.max(y, this.freeGround(p)[1]); // no chão: em cima do relevo
			p.p = [p.p[0], Math.round(y * 100) / 100, p.p[2]];
			p.b = 0;
			changed.push(p);
		}
		return changed;
	}

	/** Peças que podem ter perdido o apoio quando `p` sumiu. */
	dependents(p) {
		const out = [];
		const push = (piece) => piece && out.push(piece);
		const slot = this.defs[p.kind]?.slot;
		const cellPieces = (i, j, k) => {
			for (const [o, a, b] of BuildGrid.cellEdges(i, j)) push(this.at(BuildGrid.edgeKey(o, a, b, k)));
			push(this.at(`s:${i}:${j}:${k}`));
			for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) push(this.at(BuildGrid.cellKey(i + di, j + dj, k)));
		};
		if (slot === 'cell') cellPieces(p.i, p.j, p.k);
		if (slot === 'edge') {
			push(this.at(BuildGrid.edgeKey(p.o, p.i, p.j, p.k + 1)));
			push(this.at(`d:${p.o}:${p.i}:${p.j}:${p.k}`));
			for (const [a, b] of BuildGrid.edgeCells(p.o, p.i, p.j)) {
				push(this.at(BuildGrid.cellKey(a, b, p.k + 1)));
				for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) push(this.at(BuildGrid.cellKey(a + di, b + dj, p.k + 1)));
			}
		}
		if (slot === 'cell' || slot === 'edge') {
			for (const piece of this.pieces.values()) if (this.defs[piece.kind]?.slot === 'free') push(piece);
		}
		return out;
	}
}
