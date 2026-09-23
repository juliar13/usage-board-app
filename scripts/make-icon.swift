import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        NSColor(red: 0.065, green: 0.08, blue: 0.09, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202).fill()
        let track = NSBezierPath()
        track.appendArc(withCenter: NSPoint(x: 512, y: 520), radius: 296, startAngle: 0, endAngle: 360)
        track.lineWidth = 52
        NSColor(white: 1, alpha: 0.1).setStroke()
        track.stroke()
        let progress = NSBezierPath()
        progress.appendArc(withCenter: NSPoint(x: 512, y: 520), radius: 296, startAngle: 90, endAngle: -170, clockwise: true)
        progress.lineWidth = 52
        progress.lineCapStyle = .round
        NSColor(red: 0.65, green: 0.88, blue: 0.54, alpha: 1).setStroke()
        progress.stroke()
        for (index, height) in [110, 190, 280].enumerated() {
            NSColor(red: 0.65, green: 0.88, blue: 0.54, alpha: 1 - Double(index) * 0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: 365 + index * 110, y: 365, width: 72, height: height), xRadius: 24, yRadius: 24).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
