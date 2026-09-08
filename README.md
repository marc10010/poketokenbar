# PokeTokenBar

App de barra de menú para macOS que convierte el consumo de tokens de la API de
Anthropic en combates Pokémon estilo retro. **1 token = 1 punto de daño.**
Cuando el rival llega a 0 HP se captura, entra en tu caja PC y aparece otro.

```
 [ Typhlosion vs Diglett ]  37.3k/42.8k
```

---

## 1. Arquitectura

Tres capas, con el juego aislado de AppKit para que sea comprobable sin UI:

```
┌──────────────────────── PokeTokenBar (app target) ─────────────────────────┐
│  Entry ─▶ AppDelegate ─▶ StatusItemController ─▶ NSPopover(SwiftUI)        │
│                │                    ▲                                     │
│                │  TokenSourceCoordinator      SpriteStore (caché en disco) │
└────────────────┼───────────────┬───────────────────────────────────────────┘
                 │               │ UsageEvent
┌────────────────▼───────────────▼──── PokeTokenBarCore (librería) ──────────┐
│  Ingest      ClaudeCodeTranscriptSource   IngestServer (127.0.0.1:8317)    │
│  Store       GameStore  ──────────────▶  StateFileStore (JSON atómico)     │
│  Engine      BattleEngine · SpawnService · EvolutionService · RandomProvider│
│  Data        Pokedex  ◀── Resources/pokedex.json (#1-#251, generado)       │
└────────────────────────────────────────────────────────────────────────────┘
```

Flujo de un evento:

```
usage de la API ─▶ TokenSource ─▶ GameStore.ingest(UsageEvent)
                                    │  ¿id ya visto? ─▶ descartar
                                    ├─ ledger.record(tokens)
                                    ├─ BattleEngine.apply(damage:)
                                    │     └─ HP 0 ─▶ captura ─▶ SpawnService.spawn()
                                    └─ persist() (debounce 700 ms)
```

Decisiones que importan:

- **El motor no sabe nada de AppKit.** `PokeTokenBarCore` es Foundation puro,
  así que el juego entero se prueba sin abrir una ventana.
- **El RNG es una dependencia** (`RandomProvider`). En producción es
  `SystemRandomProvider`; en tests, `SeededRandomProvider` (SplitMix64), lo que
  permite verificar los ratios de aparición con 200.000 muestras deterministas.
- **La idempotencia vive en el store, no en las fuentes.** Cada `UsageEvent`
  trae un id estable (`requestId` del transcript, `id` del proxy). Las fuentes
  pueden solaparse, reintentar o releer un fichero sin duplicar daño.
- **La app nunca ve tu API key.** No intercepta el proceso ni proxea tráfico:
  o lee los transcripts que Claude Code ya escribe, o recibe un `usage` ya
  contabilizado en un endpoint de loopback.
- **Escritura atómica y estado en cuarentena.** `state.json` se escribe con
  `replaceItemAt`; si aparece corrupto se aparta con sufijo `.corrupt-<epoch>`
  en vez de perderse en silencio.

## 2. Modelo de datos

`Sources/PokeTokenBarCore/Resources/pokedex.json` (generado, 251 entradas):

```jsonc
{
  "id": 147, "name": "Dratini", "localizedName": "Dratini", "slug": "dratini",
  "generation": 1, "types": ["dragon"],
  "baseStatTotal": 300, "captureRate": 45,
  "rarity": "rare",            // tier de aparición
  "stage": 0,                  // distancia a la forma base (0-2)
  "baseFormID": 147,
  "evolvesInto": [148],        // varias si la cadena bifurca (Eevee: 5)
  "isLegendary": false, "isStarter": false
}
```

Estado persistido en `~/Library/Application Support/PokeTokenBar/state.json`
(`schemaVersion: 2`; la migración desde 1 acredita al compañero equipado los
tokens acumulados desde su captura, que es quien los había estado ganando):

```jsonc
{
  "schemaVersion": 1,
  "ledger": { "total": 5500, "monthly": { "2026-09": 5500 }, "eventCount": 2 },
  "box": [{ "id": "<uuid>", "speciesID": 4, "isShiny": false,
            "capturedAt": "...", "capturedAtTotalTokens": 0,
            "evolutionSeed": 12345, "tokensEarned": 289253 }],
  "activeCompanionID": "<uuid>",
  "encounter": { "speciesID": 50, "rarity": "common", "isShiny": false,
                 "maxHP": 42814, "currentHP": 37314, "spawnedAt": "..." },
  "settings": { "countCacheTokens": false, "watchClaudeCodeTranscripts": true,
                "ingestServerEnabled": true, "ingestPort": 8317 },
  "processedEventIDs": ["ingest:req_1"]
}
```

`evolutionSeed` fija la rama evolutiva de por vida: tu Eevee siempre evoluciona
al mismo sitio, aunque la cadena tenga cinco salidas.

## 3. Reglas

| Tier | Prob. | HP | Requiere | Ejemplos |
|---|---|---|---|---|
| Común | 60 % | 10.000 – 50.000 | — | Rattata, Sentret |
| Poco común | 28 % | 75.000 – 200.000 | — | Gastly, Scyther |
| Raro | 10 % | 250.000 – 600.000 | > 200.000 tokens | Dratini, Larvitar, iniciales |
| Legendario | 2 % | 1.500.000 – 4.000.000 | > 2.000.000 tokens | Mewtwo, Lugia |

- Variocolor (shiny): 1 % en cualquier aparición, y se conserva al capturar.
- Un tier bloqueado no "reintenta": su peso se reparte entre los disponibles.
### Efectividad por tipos

El daño se multiplica por el cruce de tipos entre tu compañero y el rival:
agua contra fuego ×2, fuego contra agua ×0,5, roca contra fuego/volador ×4.

- El compañero **ataca con su mejor tipo**: Bulbasaur (planta/veneno) contra
  agua usa planta (×2), no veneno (×1).
- Los tipos del defensor **multiplican** entre sí, así que el rango real va de
  ×0,25 a ×4.
- Una **inmunidad** (Normal contra Fantasma) no atasca el combate: cae al suelo
  de ×0,25 en vez de a 0, para que ningún token quede sin efecto.
- El **ledger sigue contando tokens reales**; lo que escala es el HP que
  quitas. Son dos magnitudes distintas: 1.000 tokens con ×2 son 1.000 tokens
  gastados y 2.000 HP de daño.
- Al capturar en cadena, los tokens que sobran se re-escalan con el
  multiplicador del **rival nuevo**, que puede ser otro tipo.
- Se puede apagar desde el popover (vuelve a 1 token = 1 HP).

La tabla se genera de PokeAPI (`tools/generate_typechart.mjs`) e incluye Hada:
la Pokédex embebida trae los tipos actuales, así que Clefairy, Togepi o Marill
son Hada aunque en Gen 1 y 2 no existiera ese tipo.

- Los tiers salen de los datos de PokeAPI (legendario/mítico, `capture_rate` y
  mejor BST de la familia), no de una lista a mano. La regla está en
  `tools/generate_pokedex.mjs`.
- **La evolución es de cada Pokémon, no del jugador.** Cada capturado acumula
  `tokensEarned`: los tokens gastados **mientras lo llevabas equipado**. Los
  umbrales son los del spec (base ≤ 200.000 · etapa 1 200.001–1.000.000 ·
  etapa 2 > 1.000.000) pero aplicados a ese contador propio.
  - Un Pineco capturado hoy sigue siendo Pineco aunque lleves 300.000 tokens:
    esos los ganó otro.
  - El progreso **solo crece**, así que una evolución conseguida no se pierde
    al cambiar de compañero: puedes tener Wartortle y Marowak evolucionados a
    la vez en la caja.
  - Las líneas de dos formas se quedan en su última forma.
- El daño sobrante de una captura se arrastra al rival siguiente: ningún token
  se pierde, y un evento grande puede encadenar varias capturas.

## 4. HUD flotante

Además del ítem de la barra de menú, la app puede mostrar un HUD anclado a una
esquina: fondo transparente, sin bordes, sin sombra y **click-through**
(`ignoresMouseEvents`), así que nunca roba foco ni tapa nada con lo que quieras
interactuar. Vive en todos los escritorios y sobre apps a pantalla completa.

Colocación:
- **Anclado a una esquina** (por defecto): se dibuja una ventana *por pantalla*,
  porque con varios monitores anclarlo solo a la principal lo deja donde no
  estás mirando.
- **Arrastrado a mano**: al moverlo se guarda la posición y pasa a haber una
  sola ventana. Si desconectas ese monitor, vuelve al anclaje por esquina en
  vez de quedarse en el limbo.

Tamaño:
- compacto (208×76): solo el combate;
- arrastrando cualquier borde crece y va revelando contenido por altura:
  a partir de 118 px las **métricas de consumo** (tokens totales, este mes,
  especies, capturas y lo que falta para la siguiente evolución) y a partir de
  200 px la **caja PC** (rejilla adaptativa: más ancho = más columnas). El botón
  de la esquina despliega/pliega a 320×380 sin buscar el borde, que en una
  ventana sin marco no se ve. Acotado a 520×620 y persistido.

Estados de ratón:
- desbloqueado (por defecto): se arrastra y su **menú contextual** (clic
  derecho) permite cambiar de compañero, recolocarlo, bloquearlo, ocultarlo o
  salir — sin depender del ítem de la barra de menú;
- bloqueado: click-through, se ve pero no recibe clics.

Mientras no haya compañero elegido el HUD muestra el selector de inicial y
siempre acepta clics: es la entrada al juego cuando la barra de menú está tan
llena que macOS oculta el ítem (frecuente en pantallas con notch).

## 5. Puesta en marcha

```bash
git clone <este repo> && cd poketokenbar
./scripts/bundle.sh              # compila en release y arma dist/PokeTokenBar.app
open dist/PokeTokenBar.app       # o: cp -R dist/PokeTokenBar.app /Applications/
```

Requisitos: macOS 13+ y Swift 6.x (las Command Line Tools bastan; no hace falta
Xcode). Al primer arranque eliges inicial entre los seis de Gen 1 y Gen 2.

Para desarrollar: `swift run PokeTokenBar` (el status item funciona igual sin
empaquetar, pero sin `LSUIElement` aparece en el Dock).

### Abrir junto a Claude Code

Un hook `SessionStart` en `~/.claude/settings.json` la levanta si no está ya
corriendo (el `pgrep` la hace idempotente, y el `|| true` evita que un fallo
bloquee la sesión):

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "pgrep -f 'PokeTokenBar.app/Contents/MacOS/PokeTokenBar' >/dev/null || open -ga /Applications/PokeTokenBar.app 2>/dev/null || true",
        "timeout": 10
      }]
    }]
  }
}
```

Autoarranque al iniciar sesión (alternativa, independiente de Claude):

```bash
cat > ~/Library/LaunchAgents/dev.poketokenbar.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.poketokenbar</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/PokeTokenBar.app/Contents/MacOS/PokeTokenBar</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl load ~/Library/LaunchAgents/dev.poketokenbar.plist
```

## 6. De dónde salen los tokens

### a) Transcripts de Claude Code (activo por defecto, cero configuración)

Sigue `~/.claude/projects/**/*.jsonl` y lee `message.usage` de cada línea. En el
primer arranque se coloca al final de cada fichero, así que no te vuelca meses
de historial sobre el primer Rattata.

### b) Proxy de la API (para tu propio código)

```bash
node tools/anthropic-proxy.mjs
export ANTHROPIC_BASE_URL=http://127.0.0.1:8318
```

Reenvía a `api.anthropic.com` tal cual —streaming SSE incluido— y reporta el
`usage` a la app. Las cabeceras de autenticación se reenvían sin leerse ni
registrarse.

### c) Reportar a mano desde cualquier sitio

```bash
curl -X POST http://127.0.0.1:8317/usage \
  -H 'content-type: application/json' \
  -d '{"id":"req_123","model":"claude-opus-5",
       "usage":{"input_tokens":4000,"output_tokens":1000}}'
```

`id` es la clave de idempotencia: repetir la misma petición no hace más daño.
El servidor escucha solo en `127.0.0.1` y expone tres rutas: `GET /` (una
página que explica qué es esto, por si abres el puerto en el navegador),
`GET /health` y `POST /usage`.

Los tokens de caché (`cache_creation_input_tokens`, `cache_read_input_tokens`)
**no** cuentan por defecto: en sesiones largas dominan el total y desequilibran
el combate. Hay un check en el popover para incluirlos.

## 7. Overrides por entorno

Útiles para probar contra una partida desechable sin tocar la real:

| Variable | Efecto |
|---|---|
| `POKETOKENBAR_STATE_DIR` | dónde vive `state.json` y los offsets |
| `POKETOKENBAR_CLAUDE_PROJECTS` | raíz de transcripts a vigilar |
| `POKETOKENBAR_INGEST_PORT` | puerto del servidor de ingest |

## 8. Diagnóstico

Una app de barra de menú no tiene ventana donde mostrar un error y su stderr se
pierde al lanzarla con `open`, así que registra su geometría en
`~/Library/Application Support/PokeTokenBar/diagnostics.log`: si "no se ve
nada", ahí aparece si el ítem existe, en qué pantalla cayó y cuánto mide.

```bash
tail -5 ~/Library/Application\ Support/PokeTokenBar/diagnostics.log
```

## 9. Tests

```bash
swift run PokeTokenBarSelfTest     # 60 tests, ~19k comprobaciones
swift run PokeTokenBar --ui-smoke-test
```

El arnés de `Sources/PokeTokenBarSelfTest` es propio y sin dependencias porque
XCTest y swift-testing necesitan Xcode completo; así la suite corre con solo las
Command Line Tools. Cubre gates de tier, ratios de aparición (200k muestras),
rangos de HP, tasa de shiny, arrastre de daño, capturas en cadena, umbrales y
ramas de evolución, idempotencia del ingest, persistencia entre reinicios,
cuarentena de estado corrupto, la tabla de tipos (incluido que ningún tipo del
dex se quede sin fila y que el multiplicador esté acotado en los 18×18×18
cruces), el apilado de la caja PC (que es lo que impide
que la lista crezca sin límite) y el parseo de transcripts y del payload HTTP.

`--ui-smoke-test` monta el árbol de SwiftUI en las tres pantallas (selector de
inicial, combate, tras captura) más el HUD, y comprueba que el panel flotante
cae dentro del área visible de la pantalla y es click-through y no opaco.

## 10. Regenerar el icono

`assets/AppIcon.icns` está commiteado, pero se genera:

```bash
./tools/make_icon.sh
```

Dibuja una barra de HP pixelada con AppKit y la empaqueta con `iconutil`. No
usa ningún recurso con dueño: es geometría, así que el repo puede llevarlo.

## 11. Regenerar la Pokédex

```bash
node tools/generate_pokedex.mjs   # ~580 peticiones a PokeAPI, ~30 s
```

## 12. Límites conocidos del MVP

- Los sprites se bajan de `raw.githubusercontent.com/PokeAPI/sprites` la primera
  vez y quedan en `~/Library/Caches/PokeTokenBar/sprites`. Sin red, la app
  funciona y muestra el número de Pokédex como placeholder.
- No hay notificaciones del sistema en las capturas (evita pedir permisos): la
  barra muestra "¡X capturado!" durante 6 segundos.
- La caja PC apila por especie + variante + etapa alcanzada, con contador `×N`,
  así que la rejilla tiene techo (251 × 2 × 3) por muchas capturas que acumules; el menú
  del HUD lista solo los 8 grupos más recientes y enlaza a la caja completa.
  Los registros individuales sí se guardan todos (~178 bytes cada uno), pero no
  se muestran de uno en uno.
- La caja PC no permite liberar ni renombrar todavía (`nickname` ya está en el
  modelo).
- Los sprites son propiedad de Nintendo/Game Freak: **no van en el repo**, se
  bajan de PokeAPI en tiempo de ejecución. El código es MIT (ver `LICENSE`),
  los sprites no.
