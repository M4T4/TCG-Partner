# TCG - Partner

App nativa de macOS (SwiftUI) para acompañar el juego de Pokémon TCG. Tiene un **dashboard** con tus estadísticas (win rate, arquetipo más usado, gráficas de pastel), **arquetipos** que agrupan carpetas de mazos, registro de **partidas** y **eventos**. Y, para empezar: **guardar decklists**. Copias una lista en [Limitless](https://limitlesstcg.com), la pegas con ⇧⌘V y la ves como una cuadrícula con las imágenes de las cartas.

## Compilar y ejecutar

Requiere macOS 14+ y Swift 5.10+ (bastan las Command Line Tools, no hace falta Xcode).

```sh
./scripts/build-app.sh      # genera build/TCGPartner.app
open build/TCGPartner.app

swift run                   # ejecución rápida en desarrollo
./scripts/test.sh           # tests del parser de listas
```

## Atajos

| Atajo | Acción |
|:--|:--|
| ⇧⌘V | Nuevo mazo con la lista del portapapeles |
| ⌘N | Nuevo mazo vacío |
| ⇧⌘N | Nueva carpeta de mazos |
| ⇧⌘C | Copiar la lista del mazo (formato Limitless / PTCG Live) |
| ⌘P | Imprimir la lista o exportarla como PDF, en español o inglés, eligiendo un jugador guardado |
| ⌘R | Registrar una partida |
| ⇧⌘E | Nuevo evento |
| ⌘, | Configuración: jugador actual, mis datos y tema |
| ⌫ | Mover el mazo seleccionado a la papelera |

Para saber cómo está construido el proyecto (parser, imágenes, caché y dónde se guardan los datos), lee **[COMO-FUNCIONA.md](COMO-FUNCIONA.md)**.
