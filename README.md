# NotchTodo

A small macOS app that shows your todo list in the notch. Hover over the notch for task counters, click it to open the list.

## What it does

- Reads tasks from a plain markdown file and reloads automatically when the file changes.
- Four sections: `## Viktig` (important), `## Frister` (deadlines), `## Generelle` (general) and `## Senere` (far ahead, kept out of the notch counters).
- Deadlines and later tasks are sorted by date: the one after `frist`/`innen`, otherwise the first in the task. Dates can be `2026-11-01` or short Norwegian `1. nov` (this year, or next year if more than 30 days ago; `1. nov 2027` sets the year).
- Checked tasks move to the bottom. Double-click a task to edit it. A button moves a task to the next section.
- Shows the clock in Norwegian time when you hover over the notch.

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

## Setup

Write the path to your todo file in `~/.config/notch-todo/path` (one line). Without it, `~/todo.md` is used.

```sh
./build.sh
```

The script compiles `main.swift`, signs the app ad hoc, copies it to `~/Applications` and starts it.

Requires macOS 14 or newer, Apple Silicon and the Swift toolchain. Written in Swift with SwiftUI and AppKit.
