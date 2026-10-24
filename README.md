# NotchTodo

A small macOS app that shows your todo list in the notch. Hover over the notch for task counters, click it to open the list.

## What it does

- Reads tasks from a plain markdown file and reloads when the file changes (file system events, no polling).
- Four sections: `## Viktig` (important), `## Frister` (deadlines), `## Generelle` (general) and `## Senere` (far ahead, kept out of the notch counters).
- Deadlines and later tasks are sorted by date: the one after `frist`/`innen`, otherwise the first in the task. Dates can be `2026-11-01` or short Norwegian `1. nov` (this year, or next year if more than 30 days ago; `1. nov 2027` sets the year). The date is shown as a chip (`i dag`, `i morgen`, `om 3 d`, `12. apr.`). The chip turns red when three days or less are left.
- Never overwrites changes made elsewhere: before every save the file is read again and the change (check, add, edit, delete, move) is applied on top of what is there now. The Mac app, the iPhone widget and anything else that edits the file can be used side by side.
- Checked tasks move to the bottom. Click a task to select it (move and delete buttons appear), double-click to edit it, drag a task to move it within or between sections.
- `Senere` can be collapsed to a narrow strip (collapsed by default, remembered between launches).
- The list size follows the screen it is on, and it is recalculated when displays are connected or disconnected.
- Shows the clock in Norwegian time when you hover over the notch.

### Keyboard and mouse

| | |
| --- | --- |
| ↑ / ↓ | Move between tasks (↑ from "Ny oppgave" goes into the list) |
| Tab / Shift+Tab | Move between columns |
| Space / Enter | Check or uncheck the selected task |
| ⌘Z / ⇧⌘Z | Undo / redo (check, delete, edit, move, add) |
| ⌘C | Copy the selected task (or the selected text) |
| Esc | Close |

Click a task once, then drag over its text to select and copy part of it. Right-click a task for "Kopier", "Flytt til …", "Slett" and "Kopier hele seksjonen". The copy button next to each section title copies the section as a markdown list.

## Task file

```markdown
# Todo

## Viktig
- [ ] Reply to the email

## Frister
- [ ] Hand in the report (1. nov)

## Generelle
- [ ] Go through the weekly notes

## Senere
- [ ] Apply for next summer (1. apr)
```

The order of the sections, the title and any other lines in the file are kept when the app saves.

## Setup

Write the path to your todo file in `~/.config/notch-todo/path` (one line). Without it, `~/todo.md` is used. The path can be a symlink, for example to a file in iCloud Drive.

```sh
./build.sh
```

The script compiles everything in `Sources/`, signs the app ad hoc, copies it to `~/Applications` and starts it.

Requires macOS 14 or newer, Apple Silicon and the Swift toolchain. Written in Swift with SwiftUI and AppKit, no dependencies.

## Code

- `Sources/Model/TodoFile.swift` – reading and writing the file, dates, and merging changes. Foundation only.
- `Sources/Model/TodoStore.swift` – the list in memory, saving, undo and watching the file.
- `Sources/Views/` – the SwiftUI views.
- `Sources/App/` – the panel at the notch, mouse and keyboard.
- `Tests/main.swift` – tests for the file handling. Run them with `./test.sh`.

## iPhone

`scriptable/NotchTodo.js` is a [Scriptable](https://scriptable.app) script with a widget and a full-screen list for the same file. It follows the same rules as the Mac app (sections, dates and merging on save). It reads the file from Scriptable's iCloud folder (`Scriptable/NotchTodo/todo.md`), so point the Mac app at the same file.
