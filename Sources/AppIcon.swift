// The app icon, drawn in code so the repository needs no binary assets.
// build.sh renders it into an .icns file; the running app also sets it for the Dock.

import AppKit

enum AppIcon {
    static let top = NSColor(srgbRed: 0.42, green: 0.36, blue: 0.96, alpha: 1)
    static let bottom = NSColor(srgbRed: 0.91, green: 0.33, blue: 0.62, alpha: 1)

    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    static func draw(in r: NSRect) {
        let tile = r.insetBy(dx: r.width * 0.1, dy: r.width * 0.1)
        let w = tile.width
        let shape = NSBezierPath(roundedRect: tile, xRadius: w * 0.225, yRadius: w * 0.225)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = r.width * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -r.width * 0.012)
        shadow.set()
        top.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)

        let c = NSPoint(x: tile.midX, y: tile.midY)
        func circle(_ d: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
        }
        let rings: [(CGFloat, CGFloat)] = [(0.74, 0.25), (0.6, 0.45)]
        for (d, alpha) in rings {
            let p = circle(w * d)
            p.lineWidth = w * 0.025
            NSColor.white.withAlphaComponent(alpha).setStroke()
            p.stroke()
        }
        NSColor.white.setFill()
        circle(w * 0.46).fill()
        NSGradient(starting: top, ending: bottom)?.draw(in: circle(w * 0.17), angle: -90)
    }

    static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func writeIconset(to path: String) {
        let dir = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                if let d = png(pixels: base * scale) {
                    try? d.write(to: dir.appendingPathComponent(name))
                }
            }
        }
    }
}
