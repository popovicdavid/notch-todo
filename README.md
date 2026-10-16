# NotchTodo

Liten macOS-app som viser en todo-liste i notchen. Hold musa over notchen for tellere, trykk for å åpne lista.

Listen leses fra en markdown-fil med `## Viktig`, `## Frister` (sortert etter tidligste dato i teksten) og `## Generelle` og linjer som `- [ ] oppgave`.

## Oppsett

Skriv stien til todo-filen i `~/.config/notch-todo/path`. Uten den brukes `~/todo.md`.

```sh
./build.sh
```

Krever macOS 14 og Swift.
