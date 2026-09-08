# Spec: Liga Pokémon, zonas de caza e hitos legendarios

Estado: **borrador para decidir**, sin implementar.

## 1. Qué falta hoy

Los gimnasios dieron hitos y un gate real, pero dejaron tres agujeros:

1. **No hay final.** Con 16 medallas eres Campeón y el contenido se acaba: los
   gimnasios dejan de abrirse y solo queda capturar.
2. **Los legendarios son un 2 % invisible.** Mewtwo aparece por sorteo, sin sitio
   ni historia. Lo más raro del juego llega sin épica.
3. **No hay agencia sobre qué cazas.** El sorteo es puro RNG dentro del tier, así
   que si te falta un tipo Lucha para Whitney no puedes hacer nada: solo esperar.
   Y desde que completar la Pokédex es la meta, eso es el hueco más grande.
4. **La dificultad es una pendiente sin escalones.** Los 16 gimnasios suben la
   absorción de 0,25 a 1,5 de forma continua y nada marca que hayas cambiado de
   liga. No hay "he terminado una región".

## 2. La pieza que ya existe

Un gimnasio es, por debajo: **disparador + rival fijo + absorción + recompensa
que no es una captura**. La Liga y los hitos legendarios son la misma forma con
otros parámetros, así que lo primero es extraer eso en vez de escribir tres
sistemas paralelos:

```
ScriptedEncounter
  id, tipo (gimnasio | liga | hito)
  oponente: especie fija
  hp, absorción
  requisito: medallas, rango, hito previo
  recompensa: medalla | título | captura garantizada
  disparador: contadores (gimnasio) | manual (liga, hito)
```

`GymCombat` ya sirve tal cual para los tres. Lo que cambia es el disparador
—los gimnasios se abren solos, la Liga y los hitos se **eligen**— y la
recompensa.

## 3. Estructura por regiones

En vez de una escalera plana de 16 gimnasios y una liga al final, el contenido
se parte en **dos regiones con puerta entre ellas**, al estilo de PokéClicker:
terminas una y la siguiente se abre, más dura.

Los 16 gimnasios que ya existen se dividen solos, porque ya están en ese orden:
los ocho de Johto y luego los de Kanto.

```
Johto: 8 gimnasios ─▶ Alto Mando de Johto ─▶ Campeón Lance
                                                  │
                                        abre la región de Kanto
                                                  ▼
Kanto: 8 gimnasios ─▶ Monte Plateado: Red (el final de verdad)
```

**Esto es lo canónico de Gen 2** y además resuelve dos cosas: le da a la primera
liga una recompensa que significa algo (abrir Kanto) y mete un clímax a mitad,
donde hoy solo hay una pendiente.

### La escalera de desbloqueo

| Medallas | Qué se abre |
|---|---|
| 0 | Ruta 1 (sin sesgo) · gimnasios de Johto |
| 1 | zona Bosque Verde |
| 2 | **tier raro** en el sorteo · zona Monte Moon |
| 4 | zona Ruinas Alfa |
| 6 | zona Zona Safari |
| 8 | **Alto Mando de Johto** · hitos de Johto (perros de la Torre Quemada) |
| Liga de Johto ganada | **región de Kanto**: sus 8 gimnasios y sus zonas |
| 10 | hitos de Johto: Torre Campana (Ho-Oh), Islas Remolino (Lugia) |
| 12 | zona Central Eléctrica · hitos de Kanto (Zapdos, Articuno, Moltres) |
| 16 | **Monte Plateado: Red** |
| Red vencido | Cueva Celeste (Mewtwo) · título de Campeón |

La progresión deja de ser "cuántos tokens llevas" y pasa a ser una lista de
puertas, que es lo que hace que se note avanzar.

### Cómo sube la dificultad entre regiones

Ya sube dentro de la escalera de absorción actual (0,25 → 1,5). Lo que falta es
el **escalón** al cambiar de región: los gimnasios de Kanto arrancan en la
absorción donde terminó Johto, así que el primero de Kanto ya pide cruce eficaz
donde el primero de Johto se ganaba con neutro. Eso ya lo cumple el catálogo
actual; lo que añade esta spec es que **no puedas llegar a ellos** sin pasar por
la liga.

## 4. Las tres mecánicas

### A. Las dos ligas

Canónicamente en Gen 2 hay **un solo Alto Mando** (el Plateau Añil) pero **dos
plantillas**: la de Gen 1 y la de Gen 2. Y tras los gimnasios de Kanto queda
Red en Monte Plateado, que es el reto final de verdad. Así que dos hitos:

**Alto Mando de Johto** (8 medallas): Will, Koga, Bruno, Karen y Campeón Lance,
en cadena y **sin salvajes entre medias** — es un gauntlet, no cinco gimnasios
sueltos. Cada miembro con su Pokémon estrella para el sprite:

| Miembro | Estrella | Tipo |
|---|---|---|
| Will | Xatu (#178) | psíquico/volador |
| Koga | Crobat (#169) | veneno/volador |
| Bruno | Machamp (#68) | lucha |
| Karen | Umbreon (#197) | siniestro |
| Campeón Lance | Dragonite (#149) | dragón/volador |

Detalle bonito y gratis: **Koga es líder de gimnasio en Kanto y Alto Mando en
Johto**, así que aparece dos veces con sprites distintos (Weezing y Crobat).

**Monte Plateado** (16 medallas): Red, con Pikachu (#25) como estrella. Es el
final: absorción por encima de todo lo anterior, así que exige ×4 o etapa 2.

## Recompensas

- Liga de Johto → **abre la región de Kanto**. Esto contesta a D2: la primera
  liga no necesita inventarse un premio, su premio es el contenido siguiente.
- Red → **Cueva Celeste (Mewtwo)** y el título de Campeón.

### B. Zonas de caza (la más valiosa)

No son combates: **cambian la distribución del sorteo**. Eliges dónde cazas y
eso decide qué aparece.

| Región | Zona | Sesga hacia | Se abre con |
|---|---|---|---|
| — | Ruta 1 (por defecto) | sin sesgo, como hoy | siempre |
| Johto | Bosque Verde | bicho, planta | 1 medalla |
| Johto | Monte Moon | roca, tierra, veneno | 2 medallas |
| Johto | Ruinas Alfa | psíquico | 4 medallas |
| Johto | Zona Safari | poco comunes y raros variados | 6 medallas |
| Kanto | Central Eléctrica | eléctrico, acero | Kanto abierta + 12 |
| Kanto | Cueva Celeste | psíquico y raros de Kanto | Red vencido |

Esto es lo que convierte "me falta un Lucha para Whitney" en una decisión en vez
de en esperar. El sesgo se aplica **dentro** del tier que ya sortea
`SpawnService`: la rareza sigue mandando, la zona solo reordena qué especie sale.

Coste de diseño a aceptar: con una zona puesta, la Pokédex se completa más
rápido y más dirigida. Es exactamente el punto.

### C. Hitos legendarios

Los legendarios **salen del sorteo aleatorio** y pasan a ser encuentros con
sitio y requisito:

| Región | Hito | Legendario | Requisito |
|---|---|---|---|
| Johto | Torre Quemada | Raikou, Entei, Suicune | 8 medallas |
| Johto | Torre Campana | Ho-Oh | 10 medallas |
| Johto | Islas Remolino | Lugia | 10 medallas |
| Kanto | Central Eléctrica | Zapdos | Kanto abierta + 12 |
| Kanto | Islas Espuma | Articuno | Kanto abierta + 12 |
| Kanto | Monte Ascuas | Moltres | Kanto abierta + 12 |
| Kanto | Cueva Celeste | Mewtwo | Red vencido |

Se afrontan cuando tú quieras (una vez cumplido el requisito), con HP de
legendario y absorción alta. Al vencerlos **sí se capturan**: son la única
excepción a "un jefe no se queda", porque el objetivo es la Pokédex.

Efecto de fondo: el tier legendario deja de existir como sorteo y `Rarity`
pierde su cuarto nivel en el spawn (D5).

## 4. Cómo encaja con lo que hay

| Pieza | Qué cambia |
|---|---|
| `GymCatalog` | pasa a ser `EncounterCatalog` con los tres tipos, o convive con dos catálogos más (D1) |
| `SpawnService` | acepta la zona activa y sesga la elección de especie dentro del tier |
| `Rarity.requiredRank` | el nivel legendario se queda sin uso si los legendarios pasan a hitos (D5) |
| `GymProgress` | se generaliza a progreso de encuentros: medallas, hitos vencidos, Liga superada |
| `ActiveGymBattle` | vale igual para un jefe de la Liga o un legendario; solo cambia la recompensa |
| UI | selector de zona (nuevo), lista de hitos disponibles (nuevo), pantalla de Liga (nuevo) |

## 5. Decisiones abiertas

**D1 — ¿Un catálogo o tres?** Propuesta: **uno** (`encounters.json`) con un campo
de tipo. Tres ficheros repetirían el 80 % del esquema y la UI tendría que
unirlos igual.

**D2 — ¿Qué da ganar cada liga? RESUELTA por la estructura de regiones.** La de
Johto **abre Kanto**, así que su premio es el contenido siguiente y no hay que
inventar nada. Red da **Mewtwo y el título de Campeón**. Las revanchas de
gimnasio con absorción subida quedan como contenido posterior si hiciera falta
alargar el final.

**D8 — ¿La puerta entre regiones bloquea de verdad?** Es el cambio con más
consecuencias: hoy los 16 gimnasios se abren solos en orden, y con la puerta el
noveno **no aparece** hasta ganar la Liga de Johto. Propuesta: **sí bloquea**,
porque sin puerta la región es solo una etiqueta. Efecto secundario a aceptar: el
gate de aparición de legendarios (8 medallas) se queda corto si los legendarios
pasan a ser hitos, así que los dos sistemas hay que mirarlos juntos (ver D5).

**D3 — ¿La zona se elige a mano o rota?** Propuesta: **a mano**, persistida, con
una zona por defecto sin sesgo. Rotarla sola quitaría justo la agencia que se
busca.

**D4 — ¿Cuánto sesga una zona?** Propuesta: dentro del tier, **70 % de
probabilidad** de que la especie salga del conjunto de la zona y 30 % del pool
completo. Un 100 % convertiría la zona en una lista de la compra y mataría la
sorpresa.

**D5 — ¿El tier legendario desaparece del sorteo?** Propuesta: **sí**. Si los
legendarios son hitos, dejarlos también en el sorteo los abarata. `Rarity`
mantiene el nivel para clasificar, pero `SpawnService` deja de ofrecerlo.

**D6 — ¿La Liga es un gauntlet sin salir?** Propuesta: **sí**, los cinco
seguidos y sin salvajes entre medias. Si te bloqueas por cruce de tipos, se
puede cambiar de compañero igual que en un gimnasio, así que no hay callejón sin
salida.

**D7 — ¿Los hitos caducan?** Propuesta: **no**. Están disponibles desde que se
cumple el requisito y se pueden afrontar cuando quieras. Un legendario que se
pierde para siempre castiga por no mirar la app.

## 6. Fases

1. **Zonas de caza.** Es lo más pequeño y lo que más cambia el día a día: un
   catálogo de zonas, el sesgo en `SpawnService` y un selector. Verificable
   entero con el arnés (distribuciones con RNG sembrado).
2. **Hitos legendarios.** Generalizar el encuentro guionizado y sacar el tier
   legendario del sorteo.
3. **Regiones y ligas.** La puerta entre Johto y Kanto, el gauntlet del Alto
   Mando y Red, encima de la generalización de la fase 2. La escalera de
   desbloqueo pasa a ser una pantalla: sin ella, el jugador no ve la
   progresión que esto añade.
