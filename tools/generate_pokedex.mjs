#!/usr/bin/env node
// Genera Sources/PokeTokenBarCore/Resources/pokedex.json desde PokeAPI (Gen 1 + 2, #1-#251).
// Los hechos (nombre, tipos, cadena evolutiva, legendario) vienen de la API.
// La rareza se DERIVA con una regla explicita (ver tierFor) para que sea reproducible.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

const MAX_DEX = 251;
const API = "https://pokeapi.co/api/v2";
const OUT = resolve(import.meta.dirname, "../Sources/PokeTokenBarCore/Resources/pokedex.json");

async function getJSON(url, attempt = 0) {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${res.status} ${url}`);
    return await res.json();
  } catch (err) {
    if (attempt >= 4) throw err;
    await new Promise((r) => setTimeout(r, 400 * (attempt + 1)));
    return getJSON(url, attempt + 1);
  }
}

async function mapPool(items, limit, fn) {
  const out = new Array(items.length);
  let cursor = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (cursor < items.length) {
        const i = cursor++;
        out[i] = await fn(items[i], i);
      }
    })
  );
  return out;
}

const ids = Array.from({ length: MAX_DEX }, (_, i) => i + 1);

process.stderr.write("fetching species...\n");
const species = await mapPool(ids, 12, (id) => getJSON(`${API}/pokemon-species/${id}/`));
process.stderr.write("fetching pokemon...\n");
const mons = await mapPool(ids, 12, (id) => getJSON(`${API}/pokemon/${id}/`));

const chainURLs = [...new Set(species.map((s) => s.evolution_chain.url))];
process.stderr.write(`fetching ${chainURLs.length} evolution chains...\n`);
const chains = await mapPool(chainURLs, 12, (url) => getJSON(url));

const idOfName = new Map(species.map((s) => [s.name, s.id]));
const bstOf = new Map(mons.map((m) => [m.id, m.stats.reduce((a, s) => a + s.base_stat, 0)]));

// --- cadena evolutiva -> stage, base, evoluciones directas -----------------
const evolvesInto = new Map(ids.map((id) => [id, []]));
const stageOf = new Map();
const baseOf = new Map();
const familyOf = new Map(); // id -> [ids de toda la familia]

// `baseId` se resuelve por el camino y no por la raíz de la cadena: hay líneas
// cuya raíz es una cría de una generación posterior (Azurill -> Marill, Happiny
// -> Chansey, Munchlax -> Snorlax). Cortar la cadena entera por eso dejaba a
// Marill sin su Azumarill y a Chansey sin su Blissey.
function walk(node, stage, baseId, family) {
  const id = idOfName.get(node.species.name);
  let nextBase = baseId;
  let nextStage = stage;

  if (id && id <= MAX_DEX) {
    // El primer miembro dentro de rango del camino es la forma base.
    if (nextBase === null) {
      nextBase = id;
      nextStage = 0;
    }
    stageOf.set(id, nextStage);
    baseOf.set(id, nextBase);
    family.push(id);
    const kids = node.evolves_to
      .map((n) => idOfName.get(n.species.name))
      .filter((x) => x && x <= MAX_DEX);
    evolvesInto.set(id, kids);
  }

  for (const child of node.evolves_to) {
    // Mientras no haya base, los eslabones fuera de rango no cuentan etapa.
    walk(child, nextBase === null ? 0 : nextStage + 1, nextBase, family);
  }
}

for (const chain of chains) {
  const family = [];
  walk(chain.chain, 0, null, family);
  for (const id of family) familyOf.set(id, family);
}

// Especies fuera de Gen1/2 en la cadena (p.ej. baby/evos posteriores) ya filtradas arriba.
for (const id of ids) {
  if (!stageOf.has(id)) { stageOf.set(id, 0); baseOf.set(id, id); familyOf.set(id, [id]); }
}

// --- rareza ---------------------------------------------------------------
// legendary : la API lo marca (legendario o mitico)
// rare      : familia potente (mejor BST final >= 525) Y dificil de capturar (capture_rate <= 60)
//             -> cubre iniciales, pseudo-legendarios (Dratini, Larvitar), Snorlax, Lapras...
// uncommon  : familia decente (>= 480) o algo dificil (capture_rate <= 90) -> Gastly, Scyther...
// common    : el resto -> Rattata, Sentret...
function tierFor(sp) {
  if (sp.is_legendary || sp.is_mythical) return "legendary";
  const family = familyOf.get(sp.id) ?? [sp.id];
  const familyBest = Math.max(...family.map((id) => bstOf.get(id) ?? 0));
  const cr = sp.capture_rate;
  if (familyBest >= 525 && cr <= 60) return "rare";
  if (familyBest >= 480 || cr <= 90) return "uncommon";
  return "common";
}

const titleCase = (s) => s.split("-").map((p) => p.charAt(0).toUpperCase() + p.slice(1)).join("-");

const entries = ids.map((id, i) => {
  const sp = species[i];
  const mon = mons[i];
  const en = sp.names.find((n) => n.language.name === "en");
  const es = sp.names.find((n) => n.language.name === "es");
  return {
    id,
    name: en?.name ?? titleCase(sp.name),
    localizedName: es?.name ?? en?.name ?? titleCase(sp.name),
    slug: sp.name,
    generation: id <= 151 ? 1 : 2,
    types: mon.types.sort((a, b) => a.slot - b.slot).map((t) => t.type.name),
    baseStatTotal: bstOf.get(id),
    captureRate: sp.capture_rate,
    rarity: tierFor(sp),
    stage: stageOf.get(id),
    baseFormID: baseOf.get(id),
    evolvesInto: evolvesInto.get(id) ?? [],
    isLegendary: Boolean(sp.is_legendary || sp.is_mythical),
    isStarter: [1, 4, 7, 152, 155, 158].includes(baseOf.get(id)),
  };
});

const payload = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  source: "https://pokeapi.co/api/v2 (CC-BY / dominio publico para datos de juego)",
  pokemon: entries,
};

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(payload, null, 1) + "\n");

const counts = entries.reduce((acc, e) => ((acc[e.rarity] = (acc[e.rarity] ?? 0) + 1), acc), {});
process.stderr.write(`wrote ${entries.length} entries -> ${OUT}\n${JSON.stringify(counts)}\n`);
