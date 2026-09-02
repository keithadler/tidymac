import AppKit

// Tidy for Mac icon: soft green tile with a big white sparkle and two small companions.
func sparkle(center c: CGPoint, radius r: CGFloat, pinch: CGFloat = 0.28) -> NSBezierPath {
    let p = NSBezierPath()
    let pts: [CGPoint] = (0..<8).map { i in
        let a = CGFloat(i) * .pi / 4 - .pi / 2
        let rr = i % 2 == 0 ? r : r * pinch
        return CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
    }
    p.move(to: pts[0])
    for i in 1...8 {
        let prev = pts[i - 1], cur = pts[i % 8]
        p.curve(to: cur,
                controlPoint1: CGPoint(x: prev.x + (c.x - prev.x) * 0.45, y: prev.y + (c.y - prev.y) * 0.45),
                controlPoint2: CGPoint(x: cur.x + (c.x - cur.x) * 0.45, y: cur.y + (c.y - cur.y) * 0.45))
    }
    p.close()
    return p
}

func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.55, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.58, blue: 0.40, alpha: 1)])!.draw(in: tile, angle: -70)
    NSColor.white.withAlphaComponent(0.95).setFill()
    sparkle(center: CGPoint(x: s * 0.46, y: s * 0.50), radius: s * 0.32).fill()
    NSColor.white.withAlphaComponent(0.85).setFill()
    sparkle(center: CGPoint(x: s * 0.76, y: s * 0.75), radius: s * 0.12).fill()
    sparkle(center: CGPoint(x: s * 0.24, y: s * 0.23), radius: s * 0.08).fill()
    img.unlockFocus()
    return img
}

let out = "icon/TidyMac.iconset"
try? FileManager.default.removeItem(atPath: out)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                   ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
