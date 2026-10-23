import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.25, green: 0.26, blue: 0.58, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
for (x, y, r, g, b) in [(230.0, 380.0, 0.74, 0.86, 0.68), (490.0, 240.0, 0.94, 0.85, 0.65)] {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: 1).setFill()
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: x, y: y))
    leaf.curve(to: NSPoint(x: x + 305, y: y + 360), controlPoint1: NSPoint(x: x - 80, y: y + 300), controlPoint2: NSPoint(x: x + 170, y: y + 410))
    leaf.curve(to: NSPoint(x: x, y: y), controlPoint1: NSPoint(x: x + 370, y: y + 40), controlPoint2: NSPoint(x: x + 120, y: y - 40))
    leaf.fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
