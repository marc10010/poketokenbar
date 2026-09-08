# Spec: gimnasios, medallas y rango de entrenador

Estado: **borrador para decidir**, sin implementar. Nada de esto existe hoy en
el código.

## 1. Por qué

El juego actual no tiene objetivo: capturas indefinidamente y nada culmina. Los
tiers raro y legendario se desbloquean solos con el tiempo (>200k y >2M tokens),
así que la progresión es pura acumulación pasiva.

Los gimnasios meten tres cosas que faltan: un **hito** cada cierto tiempo, una
**recompensa que no es otro Pokémon en la caja** (medalla) y, sobre todo, una
razón para que la efectividad de tipos deje de ser decorativa: contra un líder
sabes su tipo **de antemano** y eliges compañero, mientras que en los salvajes
te toca por sorteo.

## 2. Reglas pedidas

Tal cual, para no perderlas de vista:

1. Cada **300.000 tokens acumulados** o tras vencer **10 Pokémon salvajes**,
   aparece un Líder de Gimnasio (Gen 1 o 2) en lugar del siguiente encuentro
   salvaje. **Decidido**: el gimnasio se abre **al terminar el Pokémon en
   curso**, no interrumpiéndolo (ver §5).
2. Los líderes tienen **500.000 – 1.000.000 HP**.
3. Al derrotarlo **no se captura** a su Pokémon: se otorga una **medalla**.
4. Tener X medallas es **requisito obligatorio** para subir de **Rango de
   Entrenador**, y el rango es lo que desbloquea la aparición de raros y
   legendarios en los encuentros salvajes.

## 3. Cómo encaja con lo que ya hay

| Pieza existente | Qué cambia |
|---|---|
| `SpawnService` gatea tiers por `unlockThreshold` en tokens | El gate pasa a ser el **rango**; los umbrales de tokens desaparecen o se combinan (ver decisión D5) |
| `BattleEngine.apply` reparte daño y captura al llegar a 0 HP | Necesita un modo "sin captura" y un tope de gasto (ver D2) |
| `WildEncounter` es el único tipo de rival | Aparece un segundo tipo de combate, y ocupa el sitio del salvaje **siguiente**: el de en curso se acaba primero |
| Multiplicador de tipos por rival | Es la mecánica central del gimnasio: el tipo del líder se conoce antes de entrar |
| `state.box` guarda capturas | Las medallas van aparte: no son Pokémon |

## 4. Modelo de datos

`schemaVersion: 3`.

```jsonc
{
  "gyms": {
    "defeated": ["kanto-pewter", "kanto-cerulean"],   // ids de gimnasio, en orden
    "tokensSinceLastGym": 128400,
    "capturesSinceLastGym": 4,
    "current": {                                       // null si no hay gimnasio activo
      "gymID": "kanto-vermilion",
      "maxHP": 720000,
      "currentHP": 315000,
      "tokensSpent": 405000,
      "tokenBudget": 1080000,                          // ver D2
      "startedAt": "..."
    }
  }
}
```

Catálogo de gimnasios: `Resources/gyms.json`, **escrito a mano** (PokeAPI no
tiene líderes). Un líder se representa con el **sprite de su Pokémon estrella**,
así que no hace falta ningún recurso gráfico nuevo.

```jsonc
{
  "id": "kanto-pewter",
  "leader": "Brock",
  "city": "Ciudad Plateada",
  "region": "kanto",
  "type": "rock",
  "signatureSpeciesID": 95,        // Onix
  "medal": "Medalla Roca",
  "order": 1,
  "hp": [500000, 620000],          // se sortea dentro del rango
  "absorption": 0.5                // umbral de daño: ver §6
}
```

16 entradas (8 Kanto + 8 Johto). El orden fija en qué gimnasio te toca: el
siguiente sin derrotar.

## 5. El disparador

El gimnasio **no interrumpe**: se comprueba en el momento en que capturas, justo
donde hoy se sortea el rival siguiente.

```
al capturar un salvaje:
  si (tokensSinceLastGym >= 300_000) o (capturesSinceLastGym >= 10)
     y queda algún gimnasio sin derrotar
     y no hay gimnasio activo
  entonces el rival siguiente es el líder, en vez de otro salvaje
```

- **No hay encuentro pausado ni estado que restaurar.** Esto es lo que hace la
  regla simple: el sitio del gimnasio es el hueco que deja el Pokémon que
  acabas de terminar. Se cae `pausedEncounter` del modelo y con él todo el
  riesgo de perder un rival a medio bajar.
- Los dos contadores se ponen a cero **cuando el gimnasio termina**, no cuando
  empieza. Si se reiniciaran al empezar, los 500k–1M tokens del propio combate
  volverían a llenar el contador de 300k y encadenarías gimnasios sin descanso
  (ver D4).
- El daño que sobra del evento que remató al salvaje entra ya al líder, igual
  que el arrastre entre rivales que ya existe.
- Efecto que hay que aceptar: un legendario de 4M HP **retrasa** el gimnasio
  hasta que lo acabes, por mucho que los contadores estén pasados. Es el precio
  de no interrumpir, y a cambio nunca pierdes progreso.

## 6. El combate: no se pierde, se bloquea

Los tokens vienen del trabajo del jugador, no de jugar. Cualquier derrota que
dependa del tiempo (un presupuesto que se agota, un líder que se cura con el
reloj) castiga por trabajar y hace perder progreso mientras duermes. Así que la
condición de fallo no es perder: es **no avanzar**.

**Cada líder absorbe daño.** Solo le hace mella lo que pase de su umbral:

```
daño efectivo por token = max(0, multiplicador de tipos − absorción)
```

| Tu cruce contra Brock (absorción 0,5) | Daño por token |
|---|---|
| ×0,25 (inmune o muy poco eficaz) | **0** — no le haces nada |
| ×0,5 (poco eficaz) | 0 — tampoco |
| ×1 (neutro) | 0,5 |
| ×2 (eficaz) | **1,5** |
| ×4 (doblemente eficaz) | 3,5 |

Consecuencias, que son el punto entero del diseño:

- **La medalla es un logro, no un peaje.** Con el compañero equivocado no
  ganas *nunca*, por muchos tokens que le tires. Con el adecuado, cae. Lo que
  decide es la elección, no el tiempo.
- **No se pierde nada.** El peor caso es una barra que no baja, y se arregla en
  un clic: cambiar de compañero. El HUD dice exactamente eso, con el nombre de
  un tipo que sí sirva.
- **Es independiente del reloj.** Nada se cura por la noche ni caduca; dejar el
  Mac cerrado un fin de semana no cuesta progreso.
- **Se escala subiendo la absorción**, no el HP. Los primeros gimnasios piden
  ×1; los últimos, 0,75 y 1,5 de absorción, que obligan a ×2 y ×4 — es decir, a
  tener **roster**. La dificultad pasa a ser cobertura de tipos, no paciencia.

Reglas que se mantienen del combate normal:

- **Se puede cambiar de compañero durante el combate**, y es la jugada
  principal.
- El compañero equipado gana los tokens del gimnasio, así que también evoluciona.
- Al llegar a 0 HP: medalla, **sin captura**, contadores a cero y el rival
  siguiente vuelve a ser salvaje.

**Sub-decisión D8 — ¿la etapa evolutiva suma?** Hoy evolucionar es solo estética.
Propuesta: en gimnasio, cada etapa suma `+0,25` al multiplicador antes de
restar la absorción, así criar a un Pokémon tiene por fin un efecto mecánico y
un Wartortle sirve donde un Squirtle se queda corto. Aplicarlo también a los
salvajes cambiaría la economía de todo el juego, así que en el MVP sería solo en
gimnasios.

## 7. Medallas y rango

| Rango | Medallas | Desbloquea |
|---|---|---|
| Novato | 0 | común, poco común |
| Entrenador | 2 | **raro** |
| Veterano | 5 | HP de salvajes ×1,25 (opcional, ver D6) |
| As | 8 | **legendario** |
| Campeón | 16 | — (fin del contenido) |

Sustituye a `Rarity.unlockThreshold`, que hoy es puro token. Consecuencia
buscada: acumular tokens ya no basta para ver un Mewtwo; hay que ganar
gimnasios.

## 8. UI

- **Barra de menú**: durante un gimnasio, el título cambia a la medalla en
  juego y el HP del líder. Fuera de combate, un contador de medallas discreto.
- **HUD**: tarjeta de gimnasio con el nombre del líder, su tipo, el
  multiplicador de tu compañero contra él (que es la información que dispara la
  acción) y el presupuesto restante si se adopta D2.
- **Popover**: sección de medallas (16 huecos, las conseguidas en color), rango
  actual y qué desbloquea el siguiente.
- Aviso al abrirse un gimnasio: es el único momento del juego que merece
  interrumpir, y hoy no hay notificaciones (ver D7).

## 9. Migración v2 → v3

Los contadores arrancan a cero y `defeated` vacío. El efecto en una partida en
curso es que **se pierde acceso a raros y legendarios** hasta ganar 2 y 8
medallas.

Con ~485k tokens acumulados, el primer gimnasio se abre en el evento siguiente
al arranque, así que la primera medalla llega en horas, no en días. Ver D3 para
la alternativa de convalidar rango por tokens ya gastados.

## 10. Plan de tests

Lo que hay que fijar con tests antes de dar esto por bueno:

- el disparador salta por tokens **y** por capturas, y solo una vez;
- los contadores se reinician al **terminar**, y un gimnasio de 1M tokens no
  encadena el siguiente;
- el gimnasio se abre **en la captura** y no antes: un evento que deja al
  salvaje a 1 HP no lo abre, aunque los contadores estén pasados;
- derrotar a un líder **no** añade nada a la caja;
- la medalla se otorga **una sola vez** aunque un único evento gigante pase de
  sobra del HP del líder;
- el rango sale de las medallas y el gate de spawn sale del rango: con 0
  medallas y 5M tokens **no** aparecen legendarios;
- con absorción 0,5 y cruce ×0,5, el HP del líder **no baja nada** aunque el
  evento sea de un millón de tokens;
- con cruce ×2 sí baja, y a la tasa exacta `(2 − 0,5)` por token;
- cambiar de compañero a mitad del combate cambia la tasa desde ese momento, sin
  tocar el daño ya hecho;
- los tokens que no hacen daño **sí** cuentan para el ledger y para la
  evolución del compañero: se gastaron de verdad;
- el sobrante de tokens del evento que abre el gimnasio entra al líder.

## 11. Decisiones abiertas

**D1 — ¿Un Pokémon o equipo?** La regla dice "su Pokémon", en singular.
Propuesta: **uno**, con una sola barra de HP; el equipo completo se lista como
adorno. Un equipo de 3 con barras secuenciales es más fiel pero triplica estado
y UI.

**D2 — ¿Se puede perder? RESUELTA: no se pierde, se bloquea.** Ver §6. El líder
absorbe daño y con un cruce de tipos insuficiente el progreso es cero, así que
la medalla se gana eligiendo bien y no esperando. Descartadas y por qué:

- *presupuesto de tokens que se agota*: castiga por trabajar y puede fallar
  mientras el jugador no mira;
- *el líder se cura con el reloj*: hace perder progreso por la noche;
- *KO del compañero con daño entrante*: es la única que da derrota de verdad y
  usa la tabla de tipos en las dos direcciones, pero mete un recurso nuevo (HP
  del compañero, curación) y quita un Pokémon de circulación por una decisión
  que ya está tomada al empezar. Queda anotada como alternativa si el bloqueo
  resulta demasiado blando.

**D3 — ¿Convalidar la partida actual?** Propuesta: **no** convalidar, porque
regalar rango vacía la mecánica el primer día. La rebaja razonable es que el
primer gimnasio se abra de inmediato, que es lo que pasa con 485k tokens.

**D4 — ¿Los tokens del gimnasio cuentan para el siguiente disparador?**
Propuesta: **no**. Cuentan para el ledger y para la evolución del compañero,
pero el contador de 300k se reinicia al cerrar el gimnasio.

**D5 — ¿El gate de tokens desaparece del todo?** Propuesta: **sí**, lo sustituye
el rango. La alternativa (rango **y** tokens) hace el desbloqueo más lento y
difícil de explicar.

**D6 — ¿El rango afecta a algo más que al tier?** Propuesta: no en el MVP. La
palanca de dificultad pasa a ser la absorción de cada líder (§6), no el HP.

**D7 — ¿Notificación al abrirse un gimnasio?** Hoy no hay notificaciones a
propósito, para no pedir permisos. Un gimnasio es el único evento que justifica
pedirlos. Propuesta: en el MVP, el HUD y la barra cambian de aspecto; la
notificación del sistema queda para después.

## 12. Fuera de alcance

Alto Mando y Campeón, revanchas contra líderes ya derrotados, objetos, MT,
niveles individuales, e intercambio.

## 13. Fases

1. **Datos y reglas**: `gyms.json`, `GymCatalog`, rango y gate de spawn por
   rango, y la fórmula de absorción, con tests. Sin UI: se puede verificar
   entero con el arnés.
2. **Combate**: disparador en la captura, daño con absorción, medalla sin
   captura.
3. **UI**: tarjeta en el HUD, medallas y rango en el popover, barra de menú.
4. Opcionales según D2/D6/D7.
