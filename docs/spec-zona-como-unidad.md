# Spec: la zona como unidad de dificultad

Estado: **implementada** en #47 con la curva **B** (HP ×6 de punta a punta y
techo del bonus de colección a +3) y **Z1 ponderado 45/33/22**. Las demás
decisiones quedaron como se proponen aquí salvo **Z5**, que se decidió al
revés: el gate de rango se queda (ver la nota en esa decisión).

Estado original: propuesta. Sustituye la decisión **K4** de
[spec-salto-a-kanto](spec-salto-a-kanto.md) ("no escalamos el HP por región"),
que se tomó con Johto como región 1 y con el supuesto de que la alternativa era
un multiplicador por región. Ninguna de las dos cosas se sostiene ya: el orden
se invirtió a Kanto → Johto, y **PokéClicker no escala por región**.

---

## 1. Cómo está hoy

El HP de un salvaje sale de su **tier** (común 10k–50k, poco común 75k–200k,
raro 250k–600k) y el tier se sortea con pesos fijos (60/28/10, renormalizados
sobre 0,98 porque los legendarios no salen en libertad). Los pesos no cambian
nunca, y los tres tiers están disponibles desde la **segunda medalla**.

Consecuencia medida sobre los datos reales:

| | HP esperado de un salvaje |
|---|---|
| medalla 2 | 101.020 |
| medalla 16 | 101.020 |

Constante. Mientras tanto el bonus de colección sube hasta ×2 y solo cuenta
contra salvajes, así que:

| momento | especies | tokens por captura |
|---|---|---|
| Kanto, 2 medallas | 25 | 91.870 |
| Kanto, 8 medallas | 70 | 78.991 |
| Johto abierto | 80 | 76.605 |
| Johto, 12 medallas | 120 | 68.345 |
| Johto, 16 medallas | 180 | **58.831** |

**El juego se vuelve un 36 % más fácil según avanzas.** Es lo contrario de lo
que se espera de una región nueva.

Y hay un segundo problema, que es el que hace que escalar por especie no
arregle nada: el bombo **mezcla todas las zonas abiertas**. Los Rattata de la
primera ruta siguen saliendo en Johto, así que la media no puede subir por
mucho que se multiplique el HP de lo nuevo. Modelado con el reparto real:

| momento | hoy | ×(1+puerta·0,06) | ×(1+puerta/16)^1,6 |
|---|---|---|---|
| Kanto, 2 medallas | 91.870 | 92.211 | 92.459 |
| Johto abierto | 76.605 | 90.856 | 103.017 |
| Johto, 16 medallas | 58.831 | 73.185 | **86.089** |

Las dos vuelven a bajar al final.

## 2. Qué hace PokéClicker

Del código, no de fuentes secundarias
([PokemonFactory.ts](https://github.com/pokeclicker/pokeclicker/blob/develop/src/scripts/pokemons/PokemonFactory.ts)):

```
max(20, floor( (100 · ruta^2,2 / 12)^1,15 · (1 + región/20) ))
```

`ruta` es el índice **normalizado**: sigue contando al cambiar de región (Kanto
1–25, Johto 26–48…). O sea **una sola curva continua**, HP ∝ ruta^2,53, con un
factor de región de **+5 %**, que es ruido.

| | HP |
|---|---|
| Kanto ruta 1 | 20 |
| Kanto ruta 11 | 4.939 |
| fin de Kanto (25) | 39.421 |
| primera de Johto (26) | 45.710 |
| fin de Johto (48) | 215.611 |

Cruzar a Johto es un escalón del **16 %**. Lo que multiplica por 1.971 es
recorrer Kanto entero. **La unidad de dificultad es la ruta, no la región.**

Tres cosas más que van con ello:

- **Siempre estás en una ruta.** No existe el modo "todo mezclado". Por eso su
  curva funciona: la dificultad es la del sitio donde estás, no la media de
  todo lo abierto.
- **La rareza no es HP.** Todos los Pokémon de una ruta tienen el HP de la
  ruta; lo que distingue a uno raro es la **probabilidad de encuentro**.
- **Su ataque crece igual de bruto** que el HP (cada Pokémon capturado suma
  ataque, más niveles, más crianza). Por eso pueden permitirse ×2.000.

Aquí el daño crece ×2 por colección y hasta ×4 por tipos. **Copiar la pendiente
sería injugable; lo que se copia es la forma.**

## 3. La propuesta

### A. Siempre estás en una zona

`focusedZoneID` deja de ser opcional y pasa a ser `currentZoneID`: el sorteo
sale **siempre** del bombo de esa zona, con las mismas reglas que hoy tiene el
enfoque (formas base, sin legendarios). Se elige zona en la pestaña de Progreso,
que ya tiene la lista con "faltan N de M".

Esto arregla de paso una confusión real: hoy la app puede decir "Cueva Diglett"
mientras enfrente hay un Mankey, porque sin enfoque la zona es solo una
etiqueta.

### B. El HP sale de la zona

Cada zona tiene una **profundidad** `d`: su posición al ordenarlas por región y
por medallas, que es nuestro equivalente al índice normalizado de ruta. El HP
del salvaje es el de la zona:

```
HP(d) = base · r^(d−1)
```

La rareza deja de tocar el HP. `Rarity.hpRange` se queda solo para los jefes y
para la ficha.

### C. La rareza pasa a ser probabilidad

Dentro de la zona, el sorteo se pondera con los pesos de siempre (60 / 28 / 10)
repartidos entre las especies de cada tier de esa zona. Un raro de la zona sale
poco, pero cuando sale cuesta lo mismo que un común de esa zona.

Esto **cambia el enfoque tal y como está hoy**, que reparte a partes iguales.
Con la zona como único modo, el reparto uniforme dejaría la rareza sin
significado: un Dratini saldría tanto como un Magikarp. Ver Z1.

### D. La tabla, con la curva conservadora (base 60.000, r = 1,036)

| # | zona | puerta | especies | HP |
|---|---|---|---|---|
| 1 | Rutas del sur de Kanto | 0 | 50 | 60.000 |
| 2 | Bosque Verde | 1 | 3 | 62.160 |
| 3 | Cueva Diglett | 2 | 1 | 64.398 |
| 4 | Monte Moon | 2 | 4 | 66.716 |
| 5 | Túnel Roca | 3 | 6 | 69.118 |
| 6 | Edificios y guaridas | 4 | 25 | 71.606 |
| 7 | Central Eléctrica | 5 | 3 | 74.184 |
| 8 | Rutas del norte de Kanto | 6 | 45 | 76.855 |
| 9 | Zona Safari | 6 | 21 | 79.621 |
| 10 | Islas Espuma | 7 | 12 | 82.488 |
| 11 | Calle Victoria | 8 | 5 | 85.457 |
| 12 | Bosque Encinar | Johto | 13 | 88.534 |
| 13 | Cueva Unión | Johto | 13 | 91.721 |
| 14 | Rutas del sur de Johto | Johto | 46 | 95.023 |
| 15 | Torre Hojalata | Johto | 2 | 98.444 |
| 16 | Parque Nacional | 10 | 11 | 101.988 |
| 17 | Pozo Slowpoke | 10 | 4 | 105.659 |
| 18 | Rutas centrales de Johto | 10 | 48 | 109.463 |
| 19 | Ruinas Alfa | 11 | 6 | 113.404 |
| 20 | Cueva Oscura | 12 | 9 | 117.486 |
| 21 | Rutas de la costa | 12 | 35 | 121.716 |
| 22 | Monte Mortar | 13 | 8 | 126.097 |
| 23 | Lago de la Furia | 14 | 7 | 130.637 |
| 24 | Rutas del norte de Johto | 14 | 6 | 135.340 |
| 25 | Senda Helada | 15 | 4 | 140.212 |
| 26 | Catarata Tohjo | 16 | 5 | 145.260 |
| 27 | Guarida Dragón | 16 | 2 | 150.489 |
| 28 | Islas Remolino | 16 | 6 | 155.907 |
| 29 | Torre Campana | 16 | 2 | 161.519 |
| 30 | Torre Quemada | 16 | 3 | 167.334 |
| 31 | Cueva Celeste | campeón | 7 | 173.358 |
| 32 | Monte Plateado | campeón | 10 | 179.599 |

Ninguna zona se queda vacía: la más pequeña es Cueva Diglett con una forma base.
La curva sale de los datos, así que añadir Hoenn la continúa sola.

### E. El ritmo

A tu ritmo real medido (~41.700 tokens/hora de los que cuenta la app):

**A · conservadora** — HP ×3 de punta a punta, bonus de colección como hoy (techo +1):

| zona | HP | daño | tokens | tiempo |
|---|---|---|---|---|
| 1 · Rutas del sur de Kanto | 60.000 | 1,05 | 57.143 | 1,4 h |
| 11 · Calle Victoria | 85.457 | 1,30 | 65.736 | 1,6 h |
| 14 · Rutas del sur de Johto | 95.023 | 1,35 | 70.387 | 1,7 h |
| 24 · Rutas del norte de Johto | 135.340 | 1,60 | 84.587 | 2,0 h |
| 32 · Monte Plateado | 179.599 | 1,85 | 97.080 | 2,3 h |

Volver a la zona 1 al final: 32.432 tokens, **1,8× más barato** que al empezar.

**B · carrera armamentística** — HP ×6 (r = 1,0595) y techo del bonus de
colección a **+3**:

| zona | HP | daño | tokens | tiempo |
|---|---|---|---|---|
| 1 · Rutas del sur de Kanto | 60.000 | 1,15 | 52.174 | 1,3 h |
| 11 · Calle Victoria | 106.945 | 1,90 | 56.287 | 1,3 h |
| 14 · Rutas del sur de Johto | 127.193 | 2,05 | 62.045 | 1,5 h |
| 24 · Rutas del norte de Johto | 226.711 | 2,80 | 80.968 | 1,9 h |
| 32 · Monte Plateado | 359.982 | 3,55 | 101.403 | 2,4 h |

Volver a la zona 1 al final: 16.901 tokens, **3,4× más barato**.

Las dos dejan la frontera en un ritmo casi constante que sube al final, que es
lo que se buscaba. La diferencia está en **volver atrás**: en A sigue costando
casi lo mismo y en B se nota que ya has crecido, que es la sensación de
PokéClicker. B sube el techo del bonus de colección, y como ese bonus **solo
cuenta contra salvajes**, no toca el equilibrio de los jefes.

## 4. Qué hay que tocar

| Pieza | Cambio |
|---|---|
| `SpawnService.spawn` | desaparece el sorteo de tier para salvajes; siempre sale del bombo de la zona |
| `SpawnService.candidates` / `rollTier` / `availableTiers` | dejan de usarse para salvajes (hoy son el camino principal) |
| `Rarity.hpRange` | deja de dar el HP de los salvajes; se queda para jefes y ficha |
| `Rarity.requiredRank` | el gate de rango lo sustituye la puerta de la zona (ver Z5) |
| `Zone` | gana `depth` y `hp`, derivados en el generador, no a mano |
| `settings.focusedZoneID` | pasa a `currentZoneID`, no opcional; migración en `StateFileStore` |
| `GameStore.focus(zoneID:)` | pasa a ser "cambiar de zona", y no admite `nil` |
| UI | el selector de zona pasa a primer plano; el HUD dice dónde estás |
| Tests | `SpawnServiceTests` (ratios sobre 200k muestras) y `ZoneTests` cambian de forma |

Lo que **no** cambia: jefes (gimnasio, hito y liga tienen su HP en sus JSON y su
rampa por `order`), el disparador de gimnasio, la probabilidad de shiny, la
cadena de daño sobrante, el barco entre regiones y su requisito de 70 especies.

## 5. Decisiones abiertas

**Z1 — ¿Rareza uniforme o ponderada dentro de la zona?** Propuesta:
**ponderada** (60/28/10). Contra: es justo lo contrario de lo que se decidió
para el enfoque ("todo lo de la zona a partes iguales"), y volverá a hacer
lentas las cacerías concretas. A favor: con la zona como único modo, uniforme
deja la rareza sin significado. Punto medio posible: ponderar, pero mucho más
plano que hoy (por ejemplo 45/33/22).

**Z2 — ¿Curva A o B?** Propuesta: **B**, porque es la única que hace que volver
atrás se sienta distinto, que es la mitad de la gracia. Coste: tocar el techo
del bonus de colección, que es un número que ya estaba calibrado.

**Z3 — Al abrir una zona nueva, ¿te mueve sola?** Propuesta: **no**, pero
anunciarlo con el mismo marco que la medalla. En PokéClicker ir es cosa tuya.

**Z4 — ¿Se queda un modo "todas las zonas abiertas"?** Propuesta: **no**. Es
exactamente lo que rompe la curva; dejarlo como ajuste sería dejar dos juegos.

**Z5 — ¿Se caen los gates de rango de los tiers?** Propuesta: **sí**, la puerta
de la zona ya es el gate. Efecto: un raro de la primera ruta pasa a poder salir
con 0 medallas, cuando hoy pide 2. Es coherente —está en la ruta 1, tan
alcanzable como el resto— pero es un cambio de sensación en la primera hora.

**Decidido al implementar: se quedan.** Quitarlos se llevaba por delante lo que
anuncia la celebración de medalla ("ahora salen raros"), que es contenido real
de una pantalla, y hacía que las tres raras de la primera ruta —los iniciales—
salieran desde el primer minuto. La puerta de la zona dice **dónde** puedes ir;
el rango, **qué** se te pone delante al llegar.

**Z6 — ¿Qué HP tienen las zonas de campeón?** Propuesta: las últimas de la
curva (31 y 32), sin trato especial. Cueva Celeste ya es donde vive Mewtwo.

**Z7 — ¿Y Hoenn?** La curva es una función de la profundidad, así que Hoenn se
añade detrás y sigue subiendo sola. No hace falta decidir nada ahora.

**Z8 — Migración de la partida en curso.** `focusedZoneID` = `rutas-kanto-sur`
ya está puesto, así que la migración es directa. Para quien lo tuviera a `nil`:
la zona abierta más profunda.

## 6. Fuera de alcance

- Absorción en salvajes (que resistan como los líderes). Metería el bloqueo en
  el juego normal, y un salvaje que no puedes matar no es un reto, es un muro.
- Contadores por zona tipo "vence N aquí para abrir la siguiente". Nuestras
  puertas son medallas y funcionan.
- Tocar el HP o la absorción de los jefes: su rampa por `order` ya está bien.
