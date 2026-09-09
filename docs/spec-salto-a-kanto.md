# Spec: el salto a Kanto

Estado: **implementada**, con una vuelta de tuerca posterior: al ver que la
regla de "una evolución que cruza de región espera a esa región" no tocaba nada
interesante con Johto primero, **se invirtió el orden de juego a Kanto → Johto**
(el de las generaciones). El mecanismo del barco es el mismo; lo que cambia son
los números:

| | En esta spec | Implementado |
|---|---|---|
| Región 1 | Johto | **Kanto** |
| Liga que abre la 2 | Alto Mando de Johto | **Alto Mando de Kanto** (Lorelei…Blue) |
| Requisito del barco | 50 de las 100 de Johto | **70 de las 151 de Kanto** |
| Coste del requisito | 47 encontrables + criar 3 (~0,6M) | 66 encontrables + criar 4 (~0,8M) |

El resto —las decisiones K1 a K6— se mantiene tal cual: el requisito de Pokédex,
que la liga se pueda ganar sin él, que no se escale el HP por región, que el
patrón valga para Hoenn y que a quien ya tuviera la región abierta no se le
cierre.

Definir bien este salto es lo que hace que las regiones siguientes salgan
solas: si Johto→Kanto queda bien resuelto, Kanto→Hoenn es el mismo patrón con
otros datos.

---

## 1. Cómo está hoy

Ganas el Alto Mando de Johto → `LeagueProgress.kantoOpen` → aparece el noveno
gimnasio y las zonas de Kanto entran a 10, 12, 14 y 16 medallas.

Funciona, y la puerta bloquea de verdad (`nextGym` devuelve `nil` para Kanto y
`gymGate` dice qué falta). Pero el salto tiene cuatro agujeros:

1. **No hay momento.** Ganas la liga y el gimnasio siguiente aparece en
   silencio. Hay celebración de medalla y de liga, pero no de región.
2. **El requisito es solo de medallas.** Se puede ganar el Alto Mando con **18
   de las 100 especies de Johto sin registrar** —de 82 alcanzables— porque la
   Pokédex no gatea nada. La región 1 se puede saltar casi sin jugarla.
3. **Kanto no pesa más.** Un salvaje de Kanto tiene el mismo HP que uno de
   Johto: los tiers son globales. Solo rampan los jefes.
4. **No hay identidad de región** en ninguna pantalla. De ahí la confusión de
   ver un Snubbull (#209, Johto) en la región 1 y pensar que es un bug: las
   etiquetas decían "Gen 2" y "Gen 2" se lee como "región 2".

El punto 4 ya se arregló (PR #30: se etiqueta por región). Esta spec es de los
otros tres.

## 2. Qué hace PokéClicker

Con la salvedad de que son fuentes secundarias y no el código:

| Pieza | Cómo funciona allí |
|---|---|
| Puerta de región | vencer al Alto Mando **y al Campeón**, y luego **comprar el Dock Pass** (50.000 puntos de misión). Dos pasos: contenido superado y un paso deliberado |
| Pokédex | **no** hace falta completar la regional |
| Rutas | se abren por "vence N Pokémon en la ruta anterior" y por medallas |
| Poder | el daño es la suma del ataque de **todo** lo capturado, y **un Pokémon en una región que no es la suya conserva solo una parte de su ataque** |
| Volver atrás | permitido, con selector de región |

Lo que merece robarse: **el segundo paso deliberado** y **que la región nueva
exija construir allí**. Lo que no: el selector de viaje (nuestro bombo es
acumulativo y la zona enfocada ya te lleva donde quieras, que es mejor) y el
debuff al ataque (aquí llevas **un** Pokémon, no un equipo: restarle un 25 %
es castigar la colección que acabas de construir).

## 3. La propuesta

### A. El S.S. Aqua: un segundo paso, con requisito de Pokédex

En Oro y Plata a Kanto se va **en barco desde Ciudad Olivo**, después del Alto
Mando. Ese es nuestro Dock Pass, y sin moneda que comprar el peaje natural es
la Pokédex:

> **Kanto se abre cuando has ganado el Alto Mando de Johto y tienes N de las 100
> especies de Johto registradas.**

Con los datos de hoy —47 especies de Johto se capturan directamente antes de
Kanto, y otras 35 salen de evolucionarlas— el umbral cuesta esto:

| Umbral | Qué exige | Crianza |
|---|---|---|
| 40/100 | capturar 40 de las 47 que hay | ninguna |
| **50/100** | **las 47 y evolucionar 3** | **0,6M tokens** |
| 60/100 | las 47 y evolucionar 13 | 2,6M tokens |
| 70/100 | las 47 y evolucionar 23 | 4,6M tokens |

Propuesta: **50**. Obliga a recorrer Johto entero y a criar un poco, sin
convertirse en un muro de millones de tokens. Y como la Pokédex ya es un
registro acumulativo, nada de lo conseguido se pierde por el camino.

La pantalla de Ligas diría: *"Alto Mando ganado · el barco a Kanto sale con 50
especies de Johto registradas (tienes 43)"*.

### B. Kanto pesa más, pero sin cinta de correr

Los salvajes son iguales en las dos regiones, y multiplicar el HP por región
tiene un problema: **el bonus de colección que ganas en Johto se lo comería el
multiplicador de Kanto**, y volver a Johto a por lo que falta pasaría a costar
un 50 % más. Es la cinta de correr clásica.

Los datos dicen que casi no hace falta: los pools ya son distintos.

| Región | Especies base | Comunes | Poco comunes | Raras | HP medio |
|---|---|---|---|---|---|
| Johto | 95 | 33 | 56 | 6 | 118k |
| Kanto | 83 | 28 | 46 | **9** | **132k** |

Kanto ya trae un 12 % más de HP medio y **50 % más de especies raras**, sin
tocar una línea de código. Propuesta: **no escalar el HP**, y que la rampa la
sigan poniendo los jefes, que es donde ya está bien puesta (absorción 0,75 →
1,5, que exige ventaja de tipo **y** etapa evolutiva).

Alternativa si Kanto se siente flojo después de jugarlo: subir la absorción de
los gimnasios de Kanto antes que el HP de sus salvajes. Un jefe duro es una
decisión; un salvaje con más HP es solo esperar más.

### C. El momento

El salto es el hito más grande del juego y hoy no se ve. Con las piezas que ya
existen:

- **Celebración de región** al abrirse Kanto, con el mismo marco que la de
  medalla y la de liga: sprite, titular ("¡Kanto abierta!") y qué desbloquea
  (8 gimnasios, 13 zonas, 83 especies base nuevas).
- **La región en el HUD y en la barra**, cuando la zona enfocada sea de Kanto:
  saber dónde estás cazando sin abrir el popover.
- **La escalera de desbloqueo** ya tiene el escalón; solo le falta decir el
  requisito nuevo de Pokédex.

## 4. Decisiones abiertas

**K1 — ¿El umbral es 50?** Propuesta: sí. Alternativa: 40, que no pide crianza
y solo pide recorrer; o 60, que pide 2,6M de tokens y probablemente sea muro.

**K2 — ¿El requisito cuenta especies de Johto o especies cualesquiera?**
Propuesta: **de Johto** (Gen 2). Contar cualquiera lo haría trivial, porque
antes de Kanto ya se ven 48 especies de Kanto en las rutas de Johto.

**K3 — ¿El Alto Mando se puede intentar sin el requisito de Pokédex?**
Propuesta: **sí**, se gana igual; lo que espera es el barco. Así el requisito no
bloquea contenido, solo el paso de región — que es la forma del Dock Pass.

**K4 — ¿Escalamos el HP de los salvajes por región?** Propuesta: **no** (ver B).

**K5 — ¿Y las regiones siguientes?** Propuesta: el mismo patrón, con el umbral
en proporción a lo alcanzable de cada región. Así Hoenn no necesita inventar
nada: liga + registro de la región anterior.

## 5. Fuera de alcance

Debuff regional al ataque, selector de viaje, monedas y objetos, y
notificaciones del sistema (descartadas ya en el spec de gimnasios).
