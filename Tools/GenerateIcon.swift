import AppKit
import Foundation

// An original vector-drawn icon. Run with an output .iconset directory.
let outputPath = CommandLine.arguments.dropFirst().first ?? "Fore2Break.iconset"
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawIcon(size: Int) throws -> Data {
    let side = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Fore2Break.Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setAllowsAntialiasing(true)
    context.scaleBy(x: side / 1024, y: side / 1024)
    let rect = NSRect(x: 52, y: 52, width: 920, height: 920)
    let background = NSBezierPath(roundedRect: rect, xRadius: 206, yRadius: 206)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.12, 0.20, 0.17, 0.15)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.96, 0.95, 0.90).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()
    let gradient = NSGradient(starting: color(0.98, 0.97, 0.93), ending: color(0.92, 0.93, 0.86))!
    gradient.draw(in: background, angle: -55)
    color(1, 1, 1, 0.65).setStroke()
    background.lineWidth = 3
    background.stroke()

    let center = NSPoint(x: 512, y: 512)
    let ring = NSBezierPath()
    ring.appendArc(withCenter: center, radius: 246, startAngle: 56, endAngle: 396, clockwise: false)
    ring.lineWidth = 64
    ring.lineCapStyle = .round
    color(0.16, 0.29, 0.24).setStroke()
    ring.stroke()

    let diagonalOffset: CGFloat = 246 / sqrt(2)
    let dotCenter = NSPoint(x: 512 + diagonalOffset, y: 512 + diagonalOffset)
    let accent = NSBezierPath(ovalIn: NSRect(x: dotCenter.x - 39, y: dotCenter.y - 39, width: 78, height: 78))
    color(0.90, 0.49, 0.29).setFill()
    accent.fill()

    let stem = NSBezierPath(roundedRect: NSRect(x: 479, y: 446, width: 66, height: 188), xRadius: 33, yRadius: 33)
    color(0.16, 0.29, 0.24).setFill()
    stem.fill()
    let hand = NSBezierPath()
    hand.move(to: NSPoint(x: 512, y: 472))
    hand.line(to: NSPoint(x: 611, y: 418))
    hand.lineWidth = 66
    hand.lineCapStyle = .round
    color(0.16, 0.29, 0.24).setStroke()
    hand.stroke()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Fore2Break.Icon", code: 2)
    }
    return png
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (filename, size) in entries {
    try drawIcon(size: size).write(to: outputURL.appendingPathComponent(filename), options: .atomic)
}

// ICNS accepts PNG payloads for these modern icon representation types. Writing
// the container directly keeps the build usable when iconutil's service fails.
if CommandLine.arguments.count > 2 {
    func bigEndian(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    let representations: [(String, String)] = [
        ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
        ("ic14", "icon_256x256@2x.png")
    ]
    var payload = Data()
    for (type, filename) in representations {
        let png = try Data(contentsOf: outputURL.appendingPathComponent(filename))
        payload.append(Data(type.utf8))
        payload.append(bigEndian(UInt32(png.count + 8)))
        payload.append(png)
    }
    var container = Data("icns".utf8)
    container.append(bigEndian(UInt32(payload.count + 8)))
    container.append(payload)
    try container.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
}
