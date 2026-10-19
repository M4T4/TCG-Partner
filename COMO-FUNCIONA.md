# Cómo funciona TCG - Partner

## Visión general

TCG - Partner es una app nativa de macOS pensada como "compañera" del Pokémon TCG. La primera función son las **decklists**:

1. Copias una lista en Limitless (o desde PTCG Live).
2. La pegas en la app.
3. La app la lee, la guarda y la muestra como una cuadrícula de cartas con sus imágenes, separada en Pokémon, Entrenador y Energía.

Además de los mazos, la app lleva un **dashboard** con tus estadísticas, **arquetipos** que agrupan carpetas de mazos, un registro de **partidas** y tus **eventos**.

La idea es que crezca con más herramientas (por ejemplo probabilidades de robo, registro de partidas o comparar versiones de un mazo) sin rehacer lo que ya existe. Cada función nueva sigue el mismo patrón: la lógica pura va en un "Kit" con tests y la interfaz va en la app.

## Estructura de carpetas

```
TCG-Partner/
├── Package.swift              Paquete SwiftPM: un target de lógica, la app y los tests
├── Sources/
│   ├── DeckKit/               Lógica pura, sin interfaz (se puede testear)
│   │   ├── DeckList.swift     Modelos (CardEntry, ParsedDeck, DeckSection) + DeckParser + export()
│   │   ├── Tournament.swift   GameFormat (Estándar/Expandido) y AgeDivision (división según el nacimiento)
│   │   ├── Matches.swift      MatchRecord (PTCG Live o presencial), MatchStats, filtro por temporada y Ranking.best
│   │   ├── BattleLog.swift    Lee el battle log de PTCG Live: jugadores, ganador, turnos, premios, Pokémon
│   │   └── PokemonIcon.swift  Nombre de carta → icono de Limitless («Alolan Ninetales» → ninetales-alola)
│   └── TCGPartner/            La app (SwiftUI + AppKit)
│       ├── TCGPartnerApp.swift   @main, ventana y menús (Archivo › Nuevo mazo…)
│       ├── Models.swift          Archetype, TournamentEvent, DeckStatus + CollectionStore (JSON genérico)
│       ├── Analytics.swift       Cruza mazos, arquetipos y partidas: récord por mazo y por arquetipo
│       ├── Components.swift      Piezas visuales: Panel, StatCard, WinRateBar, badges, PieChart (Swift Charts)
│       ├── DashboardView.swift   El dashboard
│       ├── ArchetypeViews.swift  Detalle y formulario de un arquetipo
│       ├── MatchesView.swift     Historial de partidas (tabla) y formulario para registrar una
│       ├── EventsView.swift      Lista de eventos y su formulario
│       ├── DeckStore.swift       Modelo Deck + guardar y cargar los mazos en JSON
│       ├── CardImages.swift      CardImageService (descarga y caché) + vistas CardImage y CardPlaceholder
│       ├── ContentView.swift     Barra lateral (Dashboard, Partidas, Eventos, Arquetipos, Mazos) + detalle
│       ├── DeckView.swift        Cabecera, contadores y la cuadrícula de cartas (CardTile)
│       ├── PasteDeckSheet.swift  Hoja para pegar o editar una lista con resumen en vivo
│       ├── DecklistPage.swift    La hoja imprimible (vista SwiftUI del tamaño de una página) + opciones
│       ├── PrintDeckSheet.swift  Jugador, idioma, tipografía y vista previa; genera el PDF e imprime
│       ├── PlayerStore.swift     Jugadores guardados (players.json) para elegirlos de un menú
│       ├── PlayerFields.swift    Elegir jugador y editar sus datos (Configuración e impresión)
│       ├── SettingsView.swift    Configuración + pie de la barra lateral con el jugador actual
│       ├── Theme.swift           Temas de color (AppTheme), apariencia y fondo con degradado
│       ├── MatchDetail.swift     Lista de partidas con columnas y ficha completa de una partida
│       └── PokemonIcons.swift    Descarga y caché de iconos de Pokémon, vistas y selector de iconos
├── Tests/DeckKitTests/        Tests (Swift Testing) con listas y battle logs reales (Fixtures/)
├── docs/ejemplos/             Hojas de ejemplo con cada tipografía (PNG) y un PDF
├── scripts/
│   ├── build-app.sh           Compila en release y empaqueta build/TCGPartner.app
│   ├── make-icon.swift        Dibuja el icono (o usa Resources/AppIconSource.png si existe)
│   └── test.sh                swift test, funciona también con solo las Command Line Tools
└── Resources/AppIcon.icns     Se genera solo la primera vez que se ejecuta build-app.sh
```

## Recorrido de una lista pegada

```
 Portapapeles (lista de Limitless)
        │  ⇧⌘V
        ▼
 PasteDeckSheet ──── DeckParser.parse(texto) ──► ParsedDeck   (resumen en vivo: "60 cartas · 17 Pokémon…")
        │  "Crear mazo"
        ▼
 DeckStore.create ──► Decks/<uuid>.json      (se guarda el TEXTO original)
        │
        ▼
 DeckView ── deck.parsed ──► una sección por tipo ──► CardTile × N
                                                         │
                                                         ▼
                                       CardImage ── CardImageService.localFile(carta, tamaño)
                                                         │
                     ┌───────────────────────────────────┴────────────────────────────┐
                     │ 1. ¿Ya está en ~/Library/Caches/TCGPartner/cards? → se usa       │
                     │ 2. CDN de Limitless (URL directa por set y número)              │
                     │ 3. pokemontcg.io por set y número                               │
                     │ 4. pokemontcg.io por nombre                                     │
                     │ 5. Nada → carta de relleno con nombre, set y número             │
                     └──────────────────────────────────────────────────────────────────┘
```

La fuente de verdad de cada mazo es **el texto de la lista**, no las cartas ya interpretadas. Se vuelve a parsear cada vez que se muestra. Así, si el parser mejora, los mazos viejos también se benefician, y "Editar lista" es simplemente editar ese texto.

## Formato de lista aceptado (`DeckParser`)

El formato de Limitless y PTCG Live:

```
Pokémon: 17
4 Dreepy TWM 128
2 Dragapult ex TWM 130

Trainer: 35
4 Arven SVI 166
1 Technical Machine: Evolution PAR 178

Energy: 8
3 Basic {P} Energy SVE 5

Total Cards: 60
```

- **Cabeceras de sección**: `Pokémon`/`Pokemon`, `Trainer`/`Trainer Cards`, `Energy` (también en español: `Entrenador(es)`, `Energía`). Pueden llevar `: 17` o `- 17`, y también se acepta el formato antiguo con `##`.
- **Cartas**: `cantidad nombre SET número`. Se acepta el `*` inicial del formato antiguo de PTCG Live, los promos (`SVP 85`) y los números con letras (`TG03`).
- **Solo nombre**: una línea como `4 Arven` también se acepta; esa carta se busca por nombre.
- **Se ignoran**: líneas vacías, `Total Cards…` y la línea de asteriscos del formato antiguo.
- **Líneas no reconocidas**: no se pierden. Se guardan en `unparsedLines` y la app avisa de ellas, tanto en la hoja de pegar como en la cabecera del mazo.
- **Sin cabecera**: si una carta aparece antes de cualquier cabecera, se considera Energía si su nombre termina en "Energy" y Pokémon en otro caso.
- **60 cartas**: si el total no es 60 se muestra un aviso, pero el mazo se guarda igual.
- **Exportar**: `ParsedDeck.export()` hace lo contrario y genera el texto en formato Limitless. Es lo que copia "Copiar lista" (⇧⌘C), listo para importarlo en PTCG Live.

## Imágenes de las cartas (`CardImageService`)

Es un `actor`, así que las descargas no bloquean la interfaz y no se pisan entre sí:

1. **Caché en disco**: `~/Library/Caches/TCGPartner/cards/<SET>-<NUM>_small.png` y `…_large.png`. Si el archivo existe, se usa sin tocar la red.
2. **CDN de Limitless**: `https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/<SET>/<SET>_<NNN>_R_EN_<SM|LG>.png`, con el número rellenado a 3 dígitos (`5` → `005`). Es la fuente principal porque es una URL directa (no necesita API), es rápida y tiene los sets nuevos el mismo día que Limitless. Cubre también las energías básicas (`SVE`) y los promos (`SVP`).
3. **pokemontcg.io**, primero por set y número (`set.ptcgoCode:TWM number:128`) y, si no aparece, por nombre (la impresión más reciente). Se usa como respaldo, sobre todo para cartas pegadas sin set ni número. Las URLs que encuentra se guardan en `lookups.json` para no repetir la consulta.
4. **Si nada funciona**, se dibuja una carta de relleno (`CardPlaceholder`) del color de su sección, con el nombre, el set y el número, para que el mazo siempre se vea completo. El fallo se recuerda **7 días** antes de volver a intentarlo.

Otros detalles:
- **Descargas a la vez**: como mucho 4, para no saturar los servidores.
- **Tamaños**: la cuadrícula usa la imagen pequeña (`SM` / `small`, ~250 px) y el zoom (clic en una carta) usa la grande (`LG` / `large`).
- **Memoria**: `CardImageMemory` guarda en RAM las imágenes ya leídas de disco, para que el scroll sea fluido.
- **Vaciar la caché**: **Archivo › Vaciar caché de imágenes** borra la carpeta de imágenes y `lookups.json`. También puedes borrar la carpeta a mano; se vuelve a llenar sola.
- **Sin conexión**: después de ver un mazo una vez con internet, sus imágenes cargan sin conexión.

## Barra lateral

```
Dashboard
Partidas            89
Eventos              3
ARQUETIPOS  +
 ▾ Alakazam
    ▾ 📁 Alakazam Jellycent
         Alakazam Control
    ▸ 📁 Alakazam Ghost
 ▸ Charizard ex
MAZOS  📁+
 ▸ 📁 Ligas            (carpetas sin arquetipo)
   Lista de prueba     (mazos sueltos)
───────────────────────
(MR) Matías Rodríguez ⚙    ← fijo abajo: jugador actual → Configuración
     ID 4821937
```

## Configuración

Se abre desde el pie de la barra lateral (jugador actual y engrane) o con **⌘,**.
- **Jugador actual y mis datos**: eliges quién eres de entre los jugadores guardados y editas tu nombre, Player ID y fecha de nacimiento (la división se calcula sola). También puedes crear o eliminar jugadores. Es el mismo jugador que se propone al imprimir una lista (`currentPlayerKey` en las preferencias), así que si cambias de jugador aquí, cambia también en la hoja de impresión.
- **Mis usuarios de PTCG Live**: los nombres con los que la app te reconoce en los battle logs. Se agregan solos al registrar partidas y aquí puedes agregarlos o quitarlos a mano.
- **Tema**: Sistema (el color de acento de macOS) o uno inspirado en los tipos de Pokémon: Psíquico, Fuego, Agua, Planta, Eléctrico, Siniestro, Dragón o Hada. El tema cambia el color de botones, enlaces y selección (`.tint`), el avatar del pie y un degradado suave arriba de cada vista (`AppBackground`). Los colores de los resultados (verde/rojo) y de los arquetipos no cambian, para que las gráficas se lean igual con cualquier tema.
- **Apariencia**: Automático, Claro u Oscuro (`NSApp.appearance`).
- **Datos**: cuántos mazos y jugadores hay, un botón para abrir la carpeta de datos en Finder y otro para vaciar la caché de imágenes.

## Arquetipos

Un arquetipo ("Alakazam", "Charizard ex") agrupa **carpetas** y, si hace falta, **mazos directamente**, sin carpeta. El arquetipo de un mazo es el de su carpeta; si el mazo no está en ninguna carpeta, es el que tenga asignado directamente.
- **Crear**: con el **+** de la sección Arquetipos, **Archivo › Nuevo arquetipo…** o desde el dashboard. Tiene nombre, color (para las gráficas), **carta de portada** (set y número, o se elige entre los Pokémon de sus mazos) y notas.
- **Relacionar carpetas**: arrastra una carpeta sobre un arquetipo, o usa **Arquetipo ›** en el menú de la carpeta. "Nueva carpeta…" en el menú de un arquetipo la crea ya relacionada.
- **Mazos**: arrástralos sobre el arquetipo, o usa **Mover a › Alakazam › …**.
- **Eliminar**: desde su formulario. Las carpetas y los mazos **no se borran**, solo se quedan sin arquetipo.
- **Vista de detalle**: al seleccionar un arquetipo ves su récord (pastel), sus mazos con win rate y sus partidas recientes.
- **Win rate por matchup**: en la vista del arquetipo, una tabla con tu récord (V-D-E) y porcentaje de victoria contra cada mazo rival, según el campo «Mazo del rival» de cada partida. Agrupa sin importar mayúsculas ni espacios, ordena por partidas jugadas y deja al final las partidas sin rival anotado (`Matchup.table` en DeckKit, con tests). La barra muestra victorias (verde), empates (gris) y derrotas (rojo).

## Iconos de Pokémon

Igual que Limitless, los arquetipos, carpetas y mazos se muestran con **1 o 2 iconos de Pokémon** (sprites de `https://r2.limitlesstcg.net/pokemon/gen9/<nombre>.png`). Aparecen en la barra lateral, el dashboard, la página del arquetipo, las listas de partidas, el historial, la ficha de partida y el detalle del mazo.

**De dónde salen los iconos de cada cosa** (el primero que exista):

| Mazo | Carpeta | Arquetipo |
|:--|:--|:--|
| 1. Sus iconos propios | 1. Sus iconos propios | 1. Sus iconos elegidos |
| 2. Los de su carpeta | 2. Icono de carpeta 📁 | 2. Su nombre («Alakazam» → Alakazam; «Alakazam / Dusknoir» → los dos) |
| 3. Los de su arquetipo | | |
| 4. El Pokémon principal de su lista | | |

Ejemplo: el arquetipo «Alakazam» muestra a Alakazam. Si su carpeta «Alakazam Ghost» tiene como iconos Alakazam + Dusknoir, todos los mazos de esa carpeta se ven con los dos.

**Cambiarlos**:
- Arquetipo: en su formulario, sección **Iconos**.
- Carpeta o mazo: **Iconos…** en su menú contextual, o haciendo clic en los iconos del encabezado del mazo.

Se escriben los nombres de los Pokémon, o se eligen de los que hay en sus mazos. Si se dejan vacíos, se heredan. Si una carpeta o un mazo todavía usa los iconos heredados y escribes solo el **segundo** Pokémon (o eliges una sugerencia), el primero se rellena con el heredado. Así, en «Alakazam Ghost» basta con escribir «Dusknoir» para quedar con Alakazam + Dusknoir (`PokemonIcon.combine`, con tests). Si ya tenía iconos propios y borras el primero a propósito, se queda solo el segundo.

**Nombre del icono** (`PokemonIcon.slug`, con tests): se quitan los sufijos de carta (`ex`, `V`, `VSTAR`, `VMAX`, `GX`…) y los dueños («Ethan's», «Team Rocket's», «Radiant»). Las formas van al final: Alolan/Galarian/Hisuian/Paldean → `-alola`/`-galar`/`-hisui`/`-paldea`, Mega → `-mega` (`charizard-mega-x`), máscaras de Ogerpon → `ogerpon-wellspring`, Bloodmoon → `ursaluna-bloodmoon`, Origin Forme → `palkia-origin`, Rapid Strike, Shadow Rider, Black/White Kyurem. Se quitan puntos, apóstrofos y acentos (`mr-mime`, `farfetchd`, `flabebe`). Si el nombre completo no existe, se prueba la primera palabra («Alakazam Fantasma» → `alakazam`). Si nada existe, se muestra un círculo con la inicial.

Los mazos de los rivales también llevan iconos, a partir de lo que escribiste en «Mazo del rival» (separando con `/` o `+`: «Gardevoir ex / Jellicent»).

Los iconos se guardan en `~/Library/Caches/TCGPartner/icons/` y se dibujan sin suavizar (son pixel art). **Vaciar caché de imágenes** también los borra.

## Partidas

Hay dos tipos de partida. Se elige arriba del formulario, y la app recuerda el último tipo que usaste. En la página de un arquetipo, **Registrar partida ▾** ofrece las dos opciones y propone el mazo del arquetipo que más juegas; en el selector de mazo, los de ese arquetipo salen primero.

### Partida en PTCG Live

Pega el **battle log** (en PTCG Live: resumen de la partida › pestaña *Battle Log* › copiar). Si lo acabas de copiar, ya aparece pegado al abrir el formulario. `BattleLogParser` (en `DeckKit/BattleLog.swift`) obtiene:

| Dato | De qué líneas del log |
|:--|:--|
| Los dos jugadores | `X drew 7 cards for the opening hand.`, la moneda y los encabezados `X's Turn` (también `Turn # 3 - X's Turn`) |
| Quién eres tú | Tus nombres de usuario guardados o, si no hay, el jugador cuyas cartas ocultas aparecen en el log: tu mano inicial sale con viñetas (`• Buddy-Buddy Poffin, …`) y tus robos dicen el nombre de la carta (`Matt_277 drew Dusclops.`), mientras que los del rival no (`drew a card`) |
| Resultado | La última línea `… X wins.` (victoria si X eres tú, derrota si no). También reconoce empates |
| Cómo terminó | `took all of their Prize cards` → premios, `conceded` → rendición, sin Pokémon, sin cartas en el mazo |
| Quién empezó | `X decided to go first/second.` o el primer encabezado de turno |
| Turnos y premios | Encabezados de turno y `X took a Prize card.` / `X took 2 Prize cards.` |
| Pokémon del rival | `played … to the Active Spot/Bench`, `X's … used …`, `evolved … to …`, Pokémon sacados a la banca con Poffin. Los descartes no cuentan |

Con eso se llenan solos el resultado, el rival, "¿Empezaste tú?", los turnos y los premios. Los Pokémon del rival aparecen como botones para elegir su mazo con un clic. Si el log no permite saber cuál de los dos eres, eliges tu nombre una vez y la app lo guarda (`ptcgl.usernames` en las preferencias) para detectarlo sola la próxima vez. Puedes tener varias cuentas. El log completo se guarda en la partida (`battleLog`).

PTCG Live mezcla el apóstrofo recto y el curvo (`Matt_277’s Duskull`); el parser los trata igual. Los tests usan un log real (`Tests/DeckKitTests/Fixtures/battlelog-derrota.txt`). Si PTCG Live cambia sus frases, conviene agregar el log nuevo ahí.

### Partida presencial

Nombre del rival, su mazo, evento, **ronda o mesa**, quién empezó y notas.

### Ficha de una partida

Las listas de **Partidas recientes** (página del arquetipo) y **Actividad reciente** (dashboard) tienen columnas: resultado, fecha, tipo, mi mazo, rival (con su mazo) y evento. Al hacer **clic** en una fila (o doble clic en el historial) se abre la ficha de la partida (`MatchDetail.swift`) con todo lo relacionado:
- **Resultado** y cómo terminó (según el battle log).
- **Datos de la partida**: fecha, tipo, quién empezó, turnos, premios de cada uno y ronda o mesa.
- **Mi mazo**, con su arquetipo, el nombre con el que jugaste y un enlace para abrirlo.
- **Rival**: su mazo y los Pokémon que jugó según el log.
- **Evento**: lugar, costo y tu récord en él.
- **Historial relacionado**: tu récord contra ese mismo mazo rival y contra ese jugador.
- **Notas** y el **battle log** completo, con su texto seleccionable y un botón para copiarlo.
- Botones **Editar…** y **Eliminar**.

### Historial

La sección **Partidas** muestra el historial en una tabla que se puede ordenar (con columna **Tipo**), con filtros por mazo, tipo y resultado. Doble clic para editar una partida y ⌫ para borrarla.

**Win rate** = victorias ÷ partidas jugadas (los empates cuentan como no ganadas). El cálculo está en `DeckKit/Matches.swift` y tiene tests. Las partidas registradas antes de que existieran los tipos cuentan como presenciales.

## Eventos

Cada evento guarda: nombre, tipo (Liga, League Challenge, League Cup, Regional, Special Event, Internacional, Mundial, en línea), formato, **enlace**, **fecha de inicio y de fin**, **lugar**, **costo** (con moneda), si ya estás **inscrito**, el **mazo que planeas jugar** y notas.
- La sección **Eventos** separa los **próximos** de los **pasados**. En los pasados aparece tu récord si registraste partidas en ese evento.
- El menú contextual de un evento permite abrir su página, editarlo, abrir el enlace, duplicarlo o eliminarlo.

### Página del evento

Al hacer clic en un evento (en Eventos o en el dashboard) se abre su página (`EventPage.swift`):
- **Cabecera**: tipo, formato, si estás inscrito o si ya terminó, fecha, lugar, costo, **Abrir enlace**, **Editar…** y **Registrar partida ▾** (presencial o PTCG Live). La partida queda ligada al evento, con el mazo que usaste en él (o el planeado) y la **siguiente ronda** ya escrita («Ronda 4»). Si el evento ya pasó, se fecha el día del evento.
- **Tarjetas**: posición final (cuando ya la anotaste o el evento terminó; clic para editarla), récord, win rate, rondas jugadas y mazo jugado.
- **Posición final**: se anota en **Editar… → Resultado** con dos campos numéricos con flechas (`NumberField`): posición final y jugadores en el evento (opcional). La posición no puede pasar del número de jugadores. Se guarda en `placement` y `players` del evento y se muestra como insignia («🥉 3.º de 64 · Top 4») en la cabecera y en la tarjeta del evento en **Eventos**. `Placement` (DeckKit, con tests) arma el texto: 1.º = Campeón, 2.º = Finalista, y si no, el corte más chico que alcanzaste (Top 4, Top 8…), sin mostrar un corte que abarque todo el torneo. Colores: oro, plata y bronce para 1.º, 2.º y 3.º–4.º.
- **Partidas por ronda**: una lista con columnas (ronda, resultado, fecha, tipo, mi mazo y rival), ordenada por número de ronda. Cada fila va en **verde si ganaste** y en **rojo si perdiste**; los empates quedan sin color. Al hacer clic en una fila se abre la ficha de la partida.
- **Notas** del evento.

La ronda es texto libre («Ronda 3», «R10», «Mesa 4 · Ronda 2», «Top 8»). Para ordenar, `MatchRecord.roundNumber` toma el número que sigue a «ronda», «round» o «r», o si no el primer número del texto. Tiene tests. El campo de ronda aparece en las partidas presenciales y en cualquier partida ligada a un evento (también en las de PTCG Live, para torneos en línea).

## Journal de cada arquetipo

En la cabecera de un arquetipo, el botón **Journal** (con el número de anotaciones) abre su journal (`JournalView.swift`). Sirve para escribir tus anotaciones, tus guías y lo que aprendes en cada partida, para recordar qué hacer la próxima vez.
- **Tipos**: **Aprendizaje** (lo que aprendiste en una partida), **Guía** (plan de juego, mulligan, matchups) y **Nota** libre.
- **Lista** a la izquierda con búsqueda (título, texto y mazo rival, sin importar mayúsculas ni acentos) filtros por tipo. Las fijadas van arriba y luego la última editada.
- **Editor** a la derecha: título, tipo y el texto, sin textos de ejemplo. Si la anotación salió de una partida, aparece el enlace **Ver partida**. Se guarda solo mientras escribes (medio segundo después de la última tecla, y al salir). Una anotación nueva que dejas vacía no se guarda.
- **Fijar** una anotación la muestra en el panel **Para recordar**, arriba en la página del arquetipo. Clic en una tarjeta la abre en el journal.
- Desde la **ficha de una partida**, **Anotar aprendizaje** crea un aprendizaje ya ligado a la partida (con el mazo rival y un título como «Derrota contra Gardevoir ex») y lo abre en el journal. Si ya existe, el botón dice **Ver en el journal**.
- Modelo y lógica en DeckKit (`Journal.swift`: `JournalEntry`, `JournalKind`, `JournalEntry.filter`), con tests. Navegación: `SidebarItem.journal(arquetipo, entry:)`.

## Dashboard

Se puede ver la **temporada actual** de Play! Pokémon (de julio a junio) o **todo** el historial.
- **Tarjetas**:
  - **Win rate**, comparado con la temporada anterior.
  - **Arquetipo más usado**.
  - **Mazos activos**: los que no están retirados; también indica cuántos están listos para torneo.
  - **Próximo evento**.
- **Arquetipos**: carpetas, mazos, partidas y win rate de cada uno. Clic para abrirlo.
- **Mazos que más juego**: partidas, récord, win rate y **estado** (Listo para torneo, En pruebas, Idea, Retirado; se cambia desde el mazo o su menú contextual).
- **Resultados en eventos** (columna principal, entre "Mazos que más juego" y "Actividad reciente"): tabla con los 6 eventos terminados más recientes del periodo elegido (temporada o todo), o con posición ya anotada. Columnas: posición (medalla, «3.º / 64» y el corte: Campeón, Top 4…; «Sin anotar» si falta), evento y tipo, fecha, mazo (el que más usaste en sus partidas o, si no hay, el planeado: `TournamentEvent.playedDeckID`), récord V-D-E y win rate. Clic en una fila abre la página del evento (`EventResultsTable`).
- **Uso por arquetipo** (pastel): qué porcentaje de tus partidas juegas con cada arquetipo. Muestra los 4 principales y agrupa el resto en "Otros". Lleva el sprite pixel de cada arquetipo dentro de su rebanada, solo si cabe (`PieChart`).
- **El mazo que mejor me va** (pastel, con el win rate y el récord arriba): victorias, derrotas y empates del mazo con mejor win rate. Para que un 1-0 no gane, solo cuentan los mazos con **al menos 3 partidas** (`Ranking.best`), salvo que ninguno llegue a 3.
- **Mejores resultados en Cups** y **Mejores resultados en Challenges** (columna lateral, arriba de Próximos eventos): tus 5 mejores posiciones en League Cups y en League Challenges del periodo elegido, solo de eventos con posición anotada. Orden: mejor posición primero; a igual posición, el torneo más grande y luego el más reciente (`Placement.isBetter`, con tests). Cada fila muestra medalla y lugar, el corte (Campeón, Top 4…), nombre, fecha, jugadores y el icono del mazo. Clic abre la página del evento.
- **Actividad reciente** y **Próximos eventos**.

Las fechas se muestran siempre en español de México («hace 2 horas», «dom 11»), aunque el sistema esté en otro idioma (`AppleLocale` solo para esta app).

## Carpetas de mazos

En la barra lateral, dentro de **Mazos**, las carpetas aparecen primero (se pueden plegar) y debajo los mazos sueltos.
- **Crear**: con **Archivo › Nueva carpeta…** (⇧⌘N), con el botón de carpeta de la barra lateral, o desde **Mover a › Carpeta nueva…** en el menú de un mazo (crea la carpeta y mete el mazo).
- **Mover**: arrastra un mazo sobre una carpeta, o sobre otro mazo para llevarlo a la carpeta de ese mazo. También con **Mover a** en el menú contextual. Mover no cambia la fecha de modificación del mazo.
- **Mazos nuevos**: se crean en la carpeta del mazo seleccionado. Desde el menú de una carpeta, **Nuevo mazo aquí (pegar lista)…** lo crea directamente en ella.
- **Eliminar una carpeta**: se puede elegir entre dejar sus mazos sueltos o mandarlos a la Papelera.

Cómo se guarda: cada mazo lleva en su JSON el campo opcional `folder` con el nombre de su carpeta. Los mazos antiguos no lo tienen y quedan sueltos. La lista de carpetas está en `folders.json`, para que las carpetas vacías no se pierdan. Los archivos de los mazos siguen todos juntos en `Decks/`: las carpetas son solo una forma de organizarlos en la app, no carpetas reales en el disco. La app recuerda qué carpetas tienes plegadas.

## Imprimir la lista y exportarla como PDF

**⌘P**, el botón de impresora de la barra de herramientas o **Imprimir o exportar PDF…** en el menú contextual de un mazo abren `PrintDeckSheet`: a la izquierda el formulario y a la derecha la vista previa de la página, que se actualiza en vivo.

La hoja se basa en la de [my.limitlesstcg.com/print](https://my.limitlesstcg.com/print) y en la hoja oficial de Play! Pokémon, con un diseño más moderno:
- **Esquina superior izquierda**: "TCG - Partner" en grande, con el degradado del icono. A la derecha, el nombre del mazo, el formato y el total de cartas.
- **Recuadros del jugador**: nombre, Player ID, fecha de nacimiento, división y formato. Si un dato está vacío, el recuadro queda en blanco para rellenarlo a mano.
- **Tablas**: Pokémon y Energía a la izquierda, Entrenador a la derecha, con las columnas cantidad, nombre, set y número. Las energías se imprimen con su nombre completo ("Basic Fire Energy" en lugar de "Basic {R} Energy"). Si el mazo tiene muchas líneas, el alto de fila se reduce para que todo quepa en **una sola página**.
- **Notas**: las notas del mazo ocupan el espacio que queda al final. Si están vacías, ese espacio queda libre para escribir a mano. Se pueden quitar con "Incluir notas en la hoja".
- **Pie de página**: el total por sección y la fecha de impresión.

Opciones (se recuerdan entre usos):

| Opción | Valores |
|:--|:--|
| Idioma de la hoja | **Español** o **English**: traduce etiquetas, secciones (Entrenador/Trainer), columnas, formato, pie de página y el formato de las fechas («14 mar 1995» / «Mar 14, 1995»). Los nombres de las cartas y las notas se imprimen tal cual. |
| Tipografía | **Moderna** (SF Pro), **Redondeada** (SF Rounded), **Técnica** (SF Mono, columnas alineadas), **Editorial** (New York, serif) |
| Papel | Carta o A4 |
| Tinta | Color, o Blanco y negro para ahorrar tinta |
| Formato | Estándar o Expandido |

Las cuatro tipografías vienen con macOS, así que el PDF se ve igual en cualquier Mac. Hay ejemplos de cada una en `docs/ejemplos/`.

**Jugadores guardados**: los datos de cada jugador (nombre, Player ID y fecha de nacimiento) se guardan en `players.json` (`PlayerStore`), no en cada mazo. En la hoja de impresión, el menú **Jugador** lista a todos los guardados. Al elegir uno (por ejemplo "Brandon") sus datos aparecen en la hoja, y si se corrige algo se guarda al momento en su ficha. **Nuevo jugador** crea una ficha vacía y la selecciona, y **Eliminar** la borra (pide confirmación). La opción **En blanco** imprime los recuadros vacíos para rellenarlos a mano. La app recuerda el último jugador elegido. Si venías de la versión anterior, que guardaba un único jugador en las preferencias, ese jugador se pasa a la lista automáticamente la primera vez.

La **división** se calcula sola a partir del año de nacimiento (`AgeDivision.forBirthDate`). Cada temporada de Play! Pokémon empieza en julio y lleva el nombre del año en que termina. En la temporada T: Junior nació en T-12 o después, Senior entre T-16 y T-13, y Masters en T-17 o antes.

**Cómo se genera el PDF**: `DecklistPDF.render` dibuja la misma vista `DecklistPage` de la vista previa en un `CGContext` de PDF con `ImageRenderer`. El resultado es **vectorial**: el texto se puede seleccionar y se imprime nítido a cualquier tamaño. "Imprimir…" pasa ese mismo PDF a `PDFDocument.printOperation`, así que lo impreso coincide exactamente con el PDF exportado.

## Dónde se guardan los datos

| Qué | Dónde |
|:--|:--|
| Mazos | `~/Library/Application Support/TCGPartner/Decks/<uuid>.json` |
| Búsquedas de la API (URLs y fallos) | `~/Library/Application Support/TCGPartner/lookups.json` |
| Imágenes descargadas | `~/Library/Caches/TCGPartner/cards/` |
| Carpetas de mazos y su arquetipo | `~/Library/Application Support/TCGPartner/folders.json` |
| Arquetipos | `~/Library/Application Support/TCGPartner/archetypes.json` |
| Partidas | `~/Library/Application Support/TCGPartner/matches.json` |
| Eventos | `~/Library/Application Support/TCGPartner/events.json` |
| Journal | `~/Library/Application Support/TCGPartner/journal.json` |
| Jugadores guardados | `~/Library/Application Support/TCGPartner/players.json` |
| Opciones de impresión y último jugador elegido | Preferencias de la app (`defaults read dev.matt.TCGPartner`) |

`players.json` es una lista:

```json
[
  { "birthDate" : "2001-09-09T00:00:00Z", "id" : "59D9…", "name" : "Brandon", "playerID" : "998877" }
]
```

Cada mazo es un JSON legible:

```json
{
  "created" : "2026-10-08T16:20:00Z",
  "id" : "5F1C…",
  "list" : "Pokémon: 17\n4 Dreepy TWM 128\n…",
  "modified" : "2026-10-08T16:25:00Z",
  "folder" : "Regionales",
  "name" : "Dragapult ex",
  "notes" : "Contra Gardevoir: …"
}
```

`DeckStore` guarda los cambios 0,5 s después de la última edición, y también al salir de la app o al cambiar a otra app (`flush()`), igual que el `NoteStore` de NoteTaker. Eliminar un mazo lo manda a la Papelera, así que se puede recuperar.

## Compilar, probar y empaquetar

```sh
swift run                 # abre la app en modo desarrollo
./scripts/test.sh         # tests de DeckKit
./scripts/build-app.sh    # build/TCGPartner.app (release, icono, Info.plist, firma ad-hoc)
```

Para cambiar el icono, pon una imagen cuadrada en `Resources/AppIconSource.png` y vuelve a ejecutar `build-app.sh`.

## Cómo añadir una función nueva

1. **Lógica pura** (cálculos, parsers, reglas): en un target "Kit" sin SwiftUI (`DeckKit` o uno nuevo declarado en `Package.swift`), con sus tests en `Tests/`. Así se prueba con `./scripts/test.sh` sin abrir la app.
2. **Datos que se guardan**: en un `Store` `@MainActor` y `ObservableObject` como `DeckStore`, que se inyecta con `.environmentObject`.
3. **Interfaz**: vistas en `Sources/TCGPartner/`. Los comandos de menú se definen en `TCGPartnerApp.swift`. Si tienen que abrir una hoja de `ContentView`, se usa una `Notification.Name`, como hace `pasteDeckRequested`.
4. **Recursos de red**: reutiliza `CardImageService` para cualquier imagen de carta; `CardImage(entry:size:)` ya se encarga de la carga y la carta de relleno.

Ejemplo: para una calculadora de probabilidades de robo, `DeckKit` recibiría una función `probability(of:in:draws:)` con tests, y `DeckView` un botón que la muestre.
