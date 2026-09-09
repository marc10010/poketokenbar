# Spec: ramas por condición, y qué viene después

Estado: **borrador para decidir**. Nada de esto está implementado.

Cubre cuatro cosas en un solo documento porque comparten el mismo objetivo —que
la Pokédex se pueda terminar y que el medio juego tenga qué hacer— y porque las
decisiones de una afectan a las otras.

Fuera de alcance, dicho ya: **notificaciones del sistema** (la D7 del spec de
gimnasios). Sigue descartado.

---

## 1. Ramas por condición

### El problema

Cinco líneas bifurcan, y con un ejemplar por línea solo se puede tener una rama.
Son **9 huecos** que la Pokédex de hoy declara inalcanzables:

| Línea | Ramas | Huecos perdidos |
|---|---|---|
| Eevee #133 | Vaporeon, Jolteon, Flareon, Espeon, Umbreon | 4 |
| Tyrogue #236 | Hitmonlee, Hitmonchan, Hitmontop | 2 |
| Gloom #44 | Vileplume, Bellossom | 1 |
| Poliwhirl #61 | Poliwrath, Politoed | 1 |
| Slowpoke #79 | Slowbro, Slowking | 1 |

Y hoy la rama **no se elige**: la fija `evolutionSeed`, que no cambia nunca. Te
toca la que te toca.

### La pieza que ya existe

El registro acumulativo (PR #26): una forma que ha sido tuya **se queda en la
Pokédex** aunque el ejemplar evolucione. Eso convierte "poder cambiar de rama"
en "poder completar las cinco líneas con un solo ejemplar de cada una".

### La regla

**La rama la decide la condición que se cumple en el momento de evolucionar**, no
la semilla. Y se puede **volver a ramificar**: un ejemplar ya evolucionado puede
volver a su forma base y tomar otra rama, pagando otra vez los tokens de esa
etapa.

Condiciones, tomadas del canon y traducidas a lo que este juego tiene (el reloj
y el rival):

| Línea | Rama | Condición | Canon del que sale |
|---|---|---|---|
| Eevee | Vaporeon | vencer un rival de tipo **agua** | Piedra Agua |
| | Jolteon | rival **eléctrico** | Piedra Trueno |
| | Flareon | rival **fuego** | Piedra Fuego |
| | Espeon | **de día** (6:00–19:59) | amistad + día |
| | Umbreon | **de noche** (20:00–5:59) | amistad + noche |
| Gloom | Bellossom | de día | Piedra Solar |
| | Vileplume | de noche | Piedra Hoja |
| Poliwhirl | Poliwrath | rival de tipo **agua** | Piedra Agua |
| | Politoed | cualquier otro | Roca del Rey + intercambio (no hay) |
| Slowpoke | Slowbro | de día | nivel |
| | Slowking | de noche | Roca del Rey (no hay) |
| Tyrogue | Hitmonlee | **mañana** (6:00–13:59) | Ataque > Defensa |
| | Hitmonchan | **tarde** (14:00–19:59) | Ataque < Defensa |
| | Hitmontop | **noche** (20:00–5:59) | Ataque = Defensa |

Prioridad cuando hay dos tipos de condición (solo pasa en Eevee y Poliwhirl): el
**tipo del rival manda** sobre el reloj. Así el reloj es el camino por defecto y
el tipo es el que se busca a propósito — que con la zona enfocada ya es una
decisión con herramientas: enfocar una zona de agua para sacar a Vaporeon.

### Cómo se vuelve a ramificar

Al llegar a la última etapa, la ficha ofrece **volver a la forma base**. El
ejemplar pierde los tokens de esa etapa (`tokensEarned` baja al umbral de la
anterior) y vuelve a subir con la condición que se cumpla esta vez. Completar
Eevee entero son **4 vueltas × 200.000 tokens = 800.000**, más acertar las
condiciones.

Lo que **no** cambia: sigue habiendo un ejemplar por línea, la caja no se llena
de Eevees, y las victorias siguen contando para el gimnasio.

### Decisiones abiertas

**R1 — ¿La rama de los ejemplares que ya existen se reasigna?** Hoy la fija la
semilla. Propuesta: **no** tocar nada retroactivamente; el que ya evolucionó se
queda como está y usa la ramificación nueva para cambiar. Reasignar cambiaría
Pokémon que ya están en la caja del jugador.

**R2 — ¿Cuánto cuesta volver a ramificar?** Propuesta: los tokens de la etapa
(200.000 la primera bifurcación, que es donde bifurcan las cinco líneas). La
alternativa —gratis— convierte la Pokédex en un trámite de reloj; una tasa
distinta pide una moneda nueva que no existe.

**R3 — ¿Se avisa de la condición que se va a cumplir?** Propuesta: **sí**, la
ficha dice a qué evolucionará si evoluciona ahora mismo y qué falta para cada
rama. Sin eso el mecanismo es adivinar.

**R4 — ¿Qué pasa si la condición cambia a mitad del evento?** Un evento gigante
puede cruzar el umbral mientras el rival cambia varias veces. Propuesta: manda
la condición **en el instante del cruce**, con el rival que estuviera delante,
que es lo que ya hace `creditActiveCompanion` para la tasa.

**R5 — ¿El día/noche sale del reloj del sistema?** Propuesta: sí, hora local, sin
zona horaria configurable. Y que la barra de menú lo enseñe (☀/☾) para que no
haya que adivinar en qué banda estás.

---

## 2. Otras regiones

### Alcance

Hoy: 251 especies, 2 regiones, 16 gimnasios, 2 ligas, 33 zonas, 11 hitos.
Hoenn añadiría #252–#386 (**135 especies**), 8 gimnasios, su Alto Mando y sus
zonas; Sinnoh, #387–#493 (**107**).

### Qué sale gratis y qué no

| Pieza | Coste |
|---|---|
| Pokédex, tipos, cadenas evolutivas, zonas | **generado**: los tres generadores están parametrizados por rango de dex |
| Sprites | gratis: PokeAPI los sirve igual |
| Gimnasios, ligas, hitos | **a mano**: PokeAPI no tiene líderes ni Alto Mando (16 entradas nuevas por región) |
| Rangos de entrenador | a mano: hoy son 5 sobre 16 medallas |
| Tabla de tipos | ojo: Gen 6 cambia efectividades y añade **Hada**. Habría que decidir si el juego sigue en Gen 2 o adopta la moderna |

### Decisiones abiertas

**H1 — ¿Hasta dónde?** Propuesta: **solo Hoenn**, y solo cuando Johto y Kanto
estén terminadas de verdad. Cada región añade 8 gimnasios y ~135 especies: dos
de golpe es contenido que nadie va a ver.

**H2 — ¿La meta sigue siendo un número global?** Con Hoenn son 386, y "X/386"
mezcla regiones que no has empezado. Propuesta: **la Pokédex pasa a contar por
región** (Johto 251, Hoenn 135) y el bonus de colección usa el total registrado
sobre el total **desbloqueado**, no sobre el total del juego. Si no, abrir Hoenn
**baja** el bonus de golpe, que es el mismo error que ya arreglamos en la
Pokédex.

**H3 — ¿Hada y la tabla moderna?** Propuesta: quedarse en la tabla de Gen 2 y
que los Pokémon de Gen 3 usen sus tipos de Gen 3. Adoptar Gen 6 cambiaría los
cruces de todo el juego, incluidos los gimnasios ya jugados.

**H4 — ¿Los umbrales de evolución escalan?** 200k y 1M por Pokémon es el ritmo
de hoy. Con tres regiones, completar la Pokédex son cientos de millones de
tokens. Propuesta: dejarlos y aceptar que la Pokédex es una meta larga.

---

## 3. Misiones, logros y revanchas (fases 5 y 6 del spec de ligas)

### A. Misiones cortas

Objetivos de una sesión, no de una semana: "vence 5 de tipo planta", "gana un
gimnasio sin cambiar de compañero", "captura 3 en la zona enfocada".

**M1 — ¿Qué recompensan?** Los tokens reales están descartados (no se pueden
inventar). Propuesta: **tokens de crianza** para el compañero equipado, es decir
adelantar su evolución, que es la única moneda que ya existe. La alternativa —un
empujón temporal a la tasa de shiny— pide estado con caducidad.

**M2 — ¿Cuántas a la vez y cómo rotan?** Propuesta: **tres**, y al completar una
entra otra. Sin caducidad por reloj: caducar castiga por no mirar la app, que es
justo lo que este juego no quiere.

### B. Logros con bonus

Hitos permanentes con un premio pequeño: "las 8 medallas de una región", "50
especies", "un shiny", "un legendario". Propuesta: cada uno suma un **+0,05 al
daño**, con techo, para que la colección siga siendo la palanca principal.

### C. Revanchas de gimnasio

Un líder ya vencido se puede volver a retar con **absorción subida** y sin dar
medalla. Es el contenido de después del Campeón, cuando ya no queda nada que
abrir. Propuesta: dejarla para cuando el final se note vacío de verdad, no
antes.

---

## 4. Menores

- **Liberar y renombrar en la caja.** `nickname` está en el modelo y no se usa.
  Liberar necesita pensarse: con la regla de no repetir líneas, liberar un
  Wartortle te deja poder capturar otro Squirtle, así que es una salida al
  "quiero cambiar de rama" que se solapa con la sección 1. Propuesta: renombrar
  sí; liberar, **solo si** la ramificación de la sección 1 no entra.
- **Notificaciones del sistema: descartadas** (D7). Sin cambios.

---

## Fases propuestas

1. **Ramas por condición** (sección 1). Es lo que desbloquea el 100 % de la
   Pokédex actual, y lo único de aquí que arregla algo roto.
2. **Misiones** (3.A), que es lo que sostiene el medio juego.
3. **Logros** (3.B), encima de las misiones.
4. **Hoenn** (sección 2), cuando lo anterior esté jugado.
5. **Revanchas** (3.C), solo si el final se queda vacío.
