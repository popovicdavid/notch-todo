import CoreGraphics
import Foundation
// Kun til målingen i CI.  mouse x y [click]  |  mouse glide x y0 y1 ms
let a = CommandLine.arguments
func move(_ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
if a[1] == "glide" {
    let x = Double(a[2])!, y0 = Double(a[3])!, y1 = Double(a[4])!, ms = Double(a[5])!
    let steps = max(1, Int(ms / 8))
    for i in 0...steps { move(CGPoint(x: x, y: y0 + (y1 - y0) * Double(i) / Double(steps))); usleep(8000) }
} else {
    let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
    move(p)
    if a.count > 3 {
        usleep(300_000)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
