import CoreGraphics
import AppKit
// mouse.swift x y [click] — flytter musa (og klikker) med CGEvent. Kun til minnemålingen i CI.
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
if a.count > 3, a[3] == "click" {
    usleep(300_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
if let s = NSScreen.screens.first { print(Int(s.frame.width / 2), "skjerm \(Int(s.frame.width))×\(Int(s.frame.height)) skala \(s.backingScaleFactor)") }
if a.count > 4, let pid = Int(a[4]) {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
        let b = (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
        print("vindu \(Int(b.width))×\(Int(b.height)) på skjermen: \(w[kCGWindowIsOnscreen as String] as? Bool ?? false)")
    }
}
