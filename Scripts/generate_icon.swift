import Cocoa

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let iconsetDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = cardRect.width * 0.22

    // Rounded background with blue-indigo gradient
    let bgPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.46, blue: 0.98, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.34, green: 0.22, blue: 0.88, alpha: 1.0)
    )
    gradient?.draw(in: bgPath, angle: -45)

    // Subtle glass menu card inside
    let menuRect = NSRect(
        x: size * 0.34,
        y: size * 0.22,
        width: size * 0.46,
        height: size * 0.50
    )
    let menuPath = NSBezierPath(roundedRect: menuRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor(calibratedWhite: 1.0, alpha: 0.95).setFill()
    menuPath.fill()

    // Menu rows
    for i in 0..<3 {
        let rowY = menuRect.maxY - size * (0.14 + CGFloat(i) * 0.13)
        let rowRect = NSRect(x: menuRect.minX + size * 0.06, y: rowY, width: menuRect.width - size * 0.12, height: size * 0.055)
        let rowPath = NSBezierPath(roundedRect: rowRect, xRadius: size * 0.025, yRadius: size * 0.025)
        if i == 0 {
            NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.98, alpha: 0.95).setFill()
        } else {
            NSColor(calibratedWhite: 0.72, alpha: 0.85).setFill()
        }
        rowPath.fill()
    }

    // Cursor arrow on top-left
    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: size * 0.22, y: size * 0.78))
    cursor.line(to: NSPoint(x: size * 0.22, y: size * 0.40))
    cursor.line(to: NSPoint(x: size * 0.32, y: size * 0.50))
    cursor.line(to: NSPoint(x: size * 0.44, y: size * 0.48))
    cursor.close()
    NSColor.white.setFill()
    cursor.fill()
    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.55, alpha: 0.85).setStroke()
    cursor.lineWidth = max(1.0, size * 0.02)
    cursor.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (filename, px) in specs {
    if let data = renderIcon(pixelSize: px) {
        try data.write(to: iconsetDir.appendingPathComponent(filename))
    }
}
