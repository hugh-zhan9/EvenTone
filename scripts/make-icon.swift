import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)
        let rect = NSRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84)
        let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.19, yRadius: s * 0.19)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.28, blue: 0.23, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.08, alpha: 1))!
        gradient.draw(in: shape, angle: -60)
        NSColor(calibratedRed: 0.59, green: 0.94, blue: 0.78, alpha: 1).setStroke()
        let wave = NSBezierPath()
        wave.lineWidth = s * 0.055
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        wave.move(to: NSPoint(x: s * 0.24, y: s * 0.50))
        wave.line(to: NSPoint(x: s * 0.34, y: s * 0.50))
        wave.line(to: NSPoint(x: s * 0.41, y: s * 0.68))
        wave.line(to: NSPoint(x: s * 0.50, y: s * 0.32))
        wave.line(to: NSPoint(x: s * 0.59, y: s * 0.68))
        wave.line(to: NSPoint(x: s * 0.66, y: s * 0.50))
        wave.line(to: NSPoint(x: s * 0.76, y: s * 0.50))
        wave.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
