import CoreGraphics
import Foundation
// Kun til målingen i CI. mouse.swift x y [click]  |  mouse.swift sweep sekunder
let a = CommandLine.arguments
func move(_ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
if a[1] == "sweep" {
    // Musa går opp og ned over oppgavene i tre kolonner, som når man leter i lista.
    let end = Date().addingTimeInterval(Double(a[2])!)
    var down = true
    while Date() < end {
        for x in [200.0, 450.0, 700.0] {
            for i in 0...110 {
                let y = down ? 75.0 + Double(i) * 2 : 295.0 - Double(i) * 2
                move(CGPoint(x: x, y: y))
                usleep(8000)
            }
            down.toggle()
        }
    }
} else {
    let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
    move(p)
    if a.count > 3 {
        usleep(300_000)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
