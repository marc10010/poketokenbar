#!/usr/bin/env node
// Genera Sources/PokeTokenBarCore/Resources/typechart.json desde PokeAPI.
// Solo se guardan las relaciones distintas de 1x: el resto se asume neutro.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

const API = "https://pokeapi.co/api/v2";
const OUT = resolve(import.meta.dirname, "../Sources/PokeTokenBarCore/Resources/typechart.json");

// Los 18 tipos. Hada llegó en Gen 6, pero PokeAPI devuelve los tipos ACTUALES
// y por eso el dex generado ya trae Hada en Clefairy, Jigglypuff, Togepi,
// Mr. Mime, Marill y compañía: dejarla fuera dejaría a esos sin tabla.
const TYPES = [
  "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison",
  "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark",
  "steel", "fairy",
];

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

const effectiveness = {};
for (const type of TYPES) {
  const data = await getJSON(`${API}/type/${type}/`);
  const relations = data.damage_relations;
  const row = {};
  const put = (list, value) => {
    for (const entry of list) {
      if (TYPES.includes(entry.name)) row[entry.name] = value;
    }
  };
  put(relations.double_damage_to, 2);
  put(relations.half_damage_to, 0.5);
  put(relations.no_damage_to, 0);
  effectiveness[type] = row;
  process.stderr.write(`${type}: ${Object.keys(row).length} relaciones\n`);
}

const payload = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  source: "https://pokeapi.co/api/v2/type (relaciones de la generación actual)",
  types: TYPES,
  effectiveness,
};

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(payload, null, 1) + "\n");
process.stderr.write(`escrito ${OUT}\n`);
