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

export const EDGE_KINDS = ['wall', 'doorway', 'window'];
const FLOORS = ['floor']; // pisos que seguram parede/escada/peça livre (telhado não)
const MAX_LEVEL = 6;
const MAX_CELL = 400; // |i|, |j| (o mundo tem ~240 m de meia largura)

export class BuildGrid {
	constructor(rules, defs) {
		this.S = rules.cell;
		this.H = rules.story;
		this.base = rules.base;
		this.defs = defs;
		this.pieces = new Map(); // id -> peça
		this.slots = new Map(); // chave do lugar -> id
	}

	// ------------------------------------------------------------ geometria ---

	top(k) {
		return this.base + this.H * k;
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
			return [x, this.top(p.k) + (slot === 'door' ? 1.1 : this.H / 2), z];
		}
		const y = slot === 'stairs' ? this.top(p.k) + this.H / 2 : this.top(p.k) - 0.2;
		return [(p.i + 0.5) * S, y, (p.j + 0.5) * S];
	}

	/** Distância (no chão) de um ponto até a peça; null se a altura não bate. */
	distance(p, point) {
		const { S } = this;
		const slot = this.defs[p.kind]?.slot;
		const [x, y, z] = point;
		if (slot === 'free') return Math.abs(y - p.p[1]) > 3 ? null : Math.hypot(x - p.p[0], z - p.p[2]);
		// Piso/teto: dá para bater de baixo (dentro de casa) e de cima.
		const low = slot === 'cell' ? this.top(p.k) - this.H - 0.3 : this.top(p.k) - 2.2;
		const high = this.top(p.k) + (slot === 'cell' ? 2.4 : this.H + 0.5);
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

	edgeAt(o, i, j, k) {
		const piece = this.at(BuildGrid.edgeKey(o, i, j, k));
		return piece && EDGE_KINDS.includes(piece.kind) ? piece : null;
	}

	floorAt(i, j, k) {
		const piece = this.at(BuildGrid.cellKey(i, j, k));
		if (!piece) return null;
		return (k === 0 ? piece.kind === 'foundation' : FLOORS.includes(piece.kind)) ? piece : null;
	}

	/** Paredes do andar de baixo que seguram o piso/telhado da célula. */
	wallsUnder(i, j, k) {
		return BuildGrid.cellEdges(i, j).map(([o, a, b]) => this.edgeAt(o, a, b, k - 1)).filter(Boolean);
	}

	/**
	 * Quem segura a peça (lista vazia = cai). Piso/telhado em balanço: vale um
	 * piso vizinho do mesmo andar que esteja apoiado em parede (uma célula só).
	 */
	supporters(p) {
		const slot = this.defs[p.kind]?.slot;
		if (p.kind === 'foundation') return ['ground'];
		if (slot === 'cell') {
			if (p.k < 1) return [];
			const walls = this.wallsUnder(p.i, p.j, p.k);
			if (walls.length) return walls;
			const out = [];
			for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
				const n = this.floorAt(p.i + di, p.j + dj, p.k);
				if (n && n.kind === 'floor' && this.wallsUnder(n.i, n.j, n.k).length) out.push(n);
			}
			return out;
		}
		if (slot === 'edge') {
			const out = [];
			if (p.k > 0) {
				const below = this.edgeAt(p.o, p.i, p.j, p.k - 1);
				if (below) out.push(below);
			}
			for (const [a, b] of BuildGrid.edgeCells(p.o, p.i, p.j)) {
				const f = this.floorAt(a, b, p.k);
				if (f) out.push(f);
			}
			return out;
		}
		if (slot === 'door') {
			const frame = this.at(BuildGrid.edgeKey(p.o, p.i, p.j, p.k));
			return frame?.kind === 'doorway' ? [frame] : [];
		}
		if (slot === 'stairs') {
			const f = this.floorAt(p.i, p.j, p.k);
			return f ? [f] : [];
		}
		// Peça livre: no chão (y ≈ 0) ou em cima de uma fundação/piso.
		if (p.p[1] < 0.25) return this.cellUnder(p.p) ? [] : ['ground'];
		const f = this.cellUnder(p.p);
		return f && Math.abs(this.top(f.k) - p.p[1]) < 0.3 ? [f] : [];
	}

	/** Fundação/piso embaixo de um ponto (o mais alto que não passa do ponto). */
	cellUnder(point) {
		const i = Math.floor(point[0] / this.S);
		const j = Math.floor(point[2] / this.S);
		let best = null;
		for (let k = 0; k <= MAX_LEVEL; k++) {
			const f = this.floorAt(i, j, k);
			if (f && this.top(k) <= point[1] + 0.3) best = f;
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
