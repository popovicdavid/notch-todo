import CoreGraphics
import AppKit
// mouse.swift x y [click] — flytter musa (og klikker) med CGEvent. Kun til minnemålingen i CI.
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
if a.count > 3 {
    usleep(300_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
for s in NSScreen.screens { print("skjerm", s.frame, "skala", s.backingScaleFactor) }
