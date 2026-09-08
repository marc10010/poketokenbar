#!/usr/bin/env node
// Genera Sources/PokeTokenBarCore/Resources/zones.json.
//
// Los encuentros salen de PokeAPI (`/pokemon/{id}/encounters`) filtrados a las
// versiones de Gen 1 y 2. El agrupamiento de áreas a zonas jugables SÍ es
// nuestro: la API da 163 áreas distintas para los 251, demasiadas para ser
// zonas de un juego, así que se agrupan con las reglas de abajo y se revisan
// a mano.

import { writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const API = "https://pokeapi.co/api/v2";
const MAX_DEX = 251;
const GEN12 = new Set(["red", "blue", "yellow", "gold", "silver", "crystal"]);
const OUT = resolve(import.meta.dirname, "../Sources/PokeTokenBarCore/Resources/zones.json");
const DEX = resolve(import.meta.dirname, "../Sources/PokeTokenBarCore/Resources/pokedex.json");

// Área -> zona. El orden importa: gana la primera regla que casa, así que las
// específicas van antes que las rutas genéricas.
const RULES = [
  [/ruins-of-alph/, "ruinas-alfa"],
  [/union-cave/, "cueva-union"],
  [/national-park/, "parque-nacional"],
  [/dark-cave/, "cueva-oscura"],
  [/ice-path/, "senda-helada"],
  [/burned-tower/, "torre-quemada"],
  [/(tin-tower|bell-tower)/, "torre-campana"],
  [/whirl-islands/, "islas-remolino"],
  [/mt-mortar|mount-mortar/, "monte-mortar"],
  [/slowpoke-well/, "pozo-slowpoke"],
  [/lake-of-rage/, "lago-colera"],
  // Las rutas se parten por tramos: en una sola zona, Johto entero entraba de
  // golpe con 0 medallas (111 especies) y la puerta no gateaba nada.
  [/^johto-route-(29|30|31|32|33|34)\b/, "rutas-johto-sur"],
  [/^johto-route-(35|36|37|38|39)\b/, "rutas-johto-centro"],
  [/^johto-route-(4[0-5])\b/, "rutas-johto-costa"],
  [/^johto-route-(4[6-8])\b/, "rutas-johto-norte"],
  [/^(new-bark|cherrygrove|violet)/, "rutas-johto-sur"],
  [/^(azalea|goldenrod|ecruteak)/, "rutas-johto-centro"],
  [/^(olivine|cianwood|mahogany|blackthorn)/, "rutas-johto-costa"],
  [/roaming-johto/, "rutas-johto-norte"],
  [/^johto-/, "rutas-johto-centro"],

  [/viridian-forest/, "bosque-verde"],
  [/mt-moon|mount-moon/, "monte-moon"],
  [/rock-tunnel/, "tunel-roca"],
  [/power-plant/, "central-electrica"],
  [/safari-zone/, "zona-safari"],
  [/seafoam/, "islas-espuma"],
  [/cerulean-cave/, "cueva-celeste"],
  [/victory-road/, "calle-victoria"],
  [/pokemon-mansion|pokemon-tower|silph-co|rocket/, "guaridas"],
  [/digletts-cave/, "cueva-diglett"],
  [/dragons-den/, "guarida-dragon"],
  [/ilex-forest/, "bosque-encinar"],
  [/sprout-tower/, "torre-hojalata"],
  [/tohjo-falls/, "catarata-tohjo"],
  [/mt-silver|mount-silver/, "monte-plateado"],
  [/saffron-city-fighting-dojo|prize-corner|celadon-mansion|cinnabar-lab|silph/, "guaridas"],
  [/roaming-johto/, "rutas-johto"],
  // Ciudades y muelles: son puntos de pesca y surf de su región, así que caen
  // con sus rutas en vez de inventarse una zona por ciudad.
  [/^kanto-route-([1-9]|1[0-2])\b/, "rutas-kanto-sur"],
  [/^kanto-route-(1[3-9]|2[0-8])\b/, "rutas-kanto-norte"],
  [/^(pallet|viridian|pewter|cerulean|vermilion)/, "rutas-kanto-sur"],
  [/^(celadon|fuchsia|saffron|cinnabar)/, "rutas-kanto-norte"],
  [/^kanto-/, "rutas-kanto-sur"],
];

// Metadatos de cada zona: región y con qué se abre.
const ZONES = {
  "rutas-johto-sur":    { name: "Rutas del sur de Johto",  region: "johto", unlock: { medals: 0 } },
  "rutas-johto-centro": { name: "Rutas centrales de Johto", region: "johto", unlock: { medals: 2 } },
  "rutas-johto-costa":  { name: "Rutas de la costa",        region: "johto", unlock: { medals: 4 } },
  "rutas-johto-norte":  { name: "Rutas del norte de Johto", region: "johto", unlock: { medals: 6 } },
  "cueva-union":       { name: "Cueva Unión",      region: "johto", unlock: { medals: 1 } },
  "parque-nacional":   { name: "Parque Nacional",  region: "johto", unlock: { medals: 2 } },
  "pozo-slowpoke":     { name: "Pozo Slowpoke",    region: "johto", unlock: { medals: 2 } },
  "ruinas-alfa":       { name: "Ruinas Alfa",      region: "johto", unlock: { medals: 3 } },
  "cueva-oscura":      { name: "Cueva Oscura",     region: "johto", unlock: { medals: 4 } },
  "monte-mortar":      { name: "Monte Mortar",     region: "johto", unlock: { medals: 5 } },
  "lago-colera":       { name: "Lago de la Furia", region: "johto", unlock: { medals: 6 } },
  "senda-helada":      { name: "Senda Helada",     region: "johto", unlock: { medals: 7 } },
  "torre-quemada":     { name: "Torre Quemada",    region: "johto", unlock: { medals: 8 } },
  "torre-campana":     { name: "Torre Campana",    region: "johto", unlock: { medals: 8 } },
  "islas-remolino":    { name: "Islas Remolino",   region: "johto", unlock: { medals: 8 } },

  "bosque-encinar":    { name: "Bosque Encinar",   region: "johto", unlock: { medals: 1 } },
  "torre-hojalata":    { name: "Torre Hojalata",   region: "johto", unlock: { medals: 1 } },
  "catarata-tohjo":    { name: "Catarata Tohjo",   region: "johto", unlock: { medals: 8 } },
  "guarida-dragon":    { name: "Guarida Dragón",   region: "johto", unlock: { medals: 8 } },
  "monte-plateado":    { name: "Monte Plateado",   region: "kanto", unlock: { champion: true } },
  "cueva-diglett":     { name: "Cueva Diglett",    region: "kanto", unlock: { region: "kanto" } },
  "rutas-kanto-sur":   { name: "Rutas del sur de Kanto",  region: "kanto", unlock: { region: "kanto" } },
  "rutas-kanto-norte": { name: "Rutas del norte de Kanto", region: "kanto", unlock: { region: "kanto", medals: 12 } },
  "bosque-verde":      { name: "Bosque Verde",     region: "kanto", unlock: { region: "kanto" } },
  "monte-moon":        { name: "Monte Moon",       region: "kanto", unlock: { region: "kanto" } },
  "tunel-roca":        { name: "Túnel Roca",       region: "kanto", unlock: { region: "kanto", medals: 10 } },
  "guaridas":          { name: "Edificios y guaridas", region: "kanto", unlock: { region: "kanto", medals: 10 } },
  "central-electrica": { name: "Central Eléctrica", region: "kanto", unlock: { region: "kanto", medals: 12 } },
  "zona-safari":       { name: "Zona Safari",      region: "kanto", unlock: { region: "kanto", medals: 12 } },
  "islas-espuma":      { name: "Islas Espuma",     region: "kanto", unlock: { region: "kanto", medals: 14 } },
  "calle-victoria":    { name: "Calle Victoria",   region: "kanto", unlock: { region: "kanto", medals: 16 } },
  "cueva-celeste":     { name: "Cueva Celeste",    region: "kanto", unlock: { champion: true } },
};

async function get(url, attempt = 0) {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(String(res.status));
    return await res.json();
  } catch (err) {
    if (attempt >= 4) return null;
    await new Promise((r) => setTimeout(r, 400 * (attempt + 1)));
    return get(url, attempt + 1);
  }
}

function zoneFor(area) {
  for (const [pattern, zone] of RULES) {
    if (pattern.test(area)) return zone;
  }
  return null;
}

const dex = JSON.parse(readFileSync(DEX, "utf8")).pokemon;
const byID = new Map(dex.map((p) => [p.id, p]));

const members = new Map(Object.keys(ZONES).map((id) => [id, new Set()]));
const unassigned = [];
const unknownAreas = new Set();

const ids = Array.from({ length: MAX_DEX }, (_, i) => i + 1);
let cursor = 0;
await Promise.all(
  Array.from({ length: 14 }, async () => {
    while (cursor < ids.length) {
      const id = ids[cursor++];
      const data = await get(`${API}/pokemon/${id}/encounters`);
      if (!data) continue;
      const areas = new Set();
      for (const entry of data) {
        if (entry.version_details.some((v) => GEN12.has(v.version.name))) {
          areas.add(entry.location_area.name);
        }
      }
      if (areas.size === 0) {
        // Sin encuentro salvaje: casi todas son formas evolucionadas, que se
        // consiguen evolucionando. Se anotan igual para la red de seguridad.
        unassigned.push(id);
        continue;
      }
      let placed = false;
      for (const area of areas) {
        const zone = zoneFor(area);
        if (zone) {
          members.get(zone).add(id);
          placed = true;
        } else {
          unknownAreas.add(area);
        }
      }
      if (!placed) unassigned.push(id);
    }
  })
);

const zones = Object.entries(ZONES).map(([id, meta]) => ({
  id,
  name: meta.name,
  region: meta.region,
  unlock: meta.unlock,
  species: [...members.get(id)].sort((a, b) => a - b),
}));

const payload = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  source: "PokeAPI /pokemon/{id}/encounters filtrado a rojo, azul, amarillo, oro, plata y cristal",
  note: "El agrupamiento de áreas a zonas es curado; los encuentros son de la API.",
  zones,
  /// Especies sin zona: aparecen en cualquiera con probabilidad de tier raro.
  unassigned: [...new Set(unassigned)].sort((a, b) => a - b),
};

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(payload, null, 1) + "\n");

const err = process.stderr;
err.write(`escrito ${OUT}\n`);
for (const zone of zones) {
  err.write(`  ${zone.id.padEnd(18)} ${String(zone.species.length).padStart(3)} especies · ${JSON.stringify(zone.unlock)}\n`);
}
err.write(`\nsin zona: ${payload.unassigned.length}`);
const bases = payload.unassigned.filter((id) => byID.get(id)?.stage === 0);
err.write(` (formas base, o sea inalcanzables sin la red: ${bases.length} -> ${bases.join(",")})\n`);
if (unknownAreas.size) {
  err.write(`\náreas sin regla (${unknownAreas.size}):\n  ${[...unknownAreas].sort().join("\n  ")}\n`);
}
