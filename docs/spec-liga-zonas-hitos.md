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

## 3. Las tres mecánicas

### A. Liga Pokémon (el final)

Alto Mando (4) + Campeón, en cadena y **sin salvajes entre medias**: es un
gauntlet, no cinco gimnasios sueltos. Requisito: 16 medallas. Absorción por
encima de la del último gimnasio (1,5), así que exige ×4 o etapa 2.

Lo que hay que resolver es la recompensa (D2): al llegar ahí ya no queda tier
por desbloquear, así que "subir de rango" no significa nada.

### B. Zonas de caza (la más valiosa)

No son combates: **cambian la distribución del sorteo**. Eliges dónde cazas y
eso decide qué aparece.

| Zona | Sesga hacia | Se abre con |
|---|---|---|
| Ruta 1 (por defecto) | sin sesgo, como hoy | siempre |
| Bosque Verde | bicho, planta | 1 medalla |
| Central Eléctrica | eléctrico, acero | 4 medallas |
| Zona Safari | poco comunes y raros de varias líneas | 6 medallas |
| Monte Moon | roca, tierra, veneno | 2 medallas |
| Ruinas Alfa | psíquico | 8 medallas |

Esto es lo que convierte "me falta un Lucha para Whitney" en una decisión en vez
de en esperar. El sesgo se aplica **dentro** del tier que ya sortea
`SpawnService`: la rareza sigue mandando, la zona solo reordena qué especie sale.

Coste de diseño a aceptar: con una zona puesta, la Pokédex se completa más
rápido y más dirigida. Es exactamente el punto.

### C. Hitos legendarios

Los legendarios **salen del sorteo aleatorio** y pasan a ser encuentros con
sitio y requisito:

| Hito | Legendario | Requisito |
|---|---|---|
| Central Eléctrica | Zapdos | 4 medallas |
| Islas Espuma | Articuno | 6 medallas |
| Monte Ascuas | Moltres | 6 medallas |
| Torre Quemada | Raikou, Entei, Suicune | 8 medallas |
| Torre Campana | Ho-Oh | 12 medallas |
| Islas Remolino | Lugia | 12 medallas |
| Cueva Celeste | Mewtwo | Liga superada |

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

**D2 — ¿Qué da ganar la Liga?** No queda tier por desbloquear. Opciones: título
de Campeón (solo cosmético), **doblar la probabilidad de shiny** (1 % → 2 %),
desbloquear Cueva Celeste (Mewtwo) —que es lo canónico—, o abrir revanchas de
gimnasio con absorción subida. Propuesta: **Mewtwo + título**, y las revanchas
como contenido posterior.

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
3. **Liga Pokémon.** El gauntlet y la recompensa, encima de la generalización de
   la fase 2.
