import AppKit
import Foundation

let fill = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
let barGrey = NSColor(srgbRed: 174 / 255, green: 174 / 255, blue: 178 / 255, alpha: 1)
let barDark = NSColor(srgbRed: 88 / 255, green: 88 / 255, blue: 92 / 255, alpha: 1)

func drawGate(size: CGFloat, accent: NSColor) {
    fill.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let notchWidth = size * 0.76
    let notchHeight = size * 0.32
    let notch = NSRect(
        x: (size - notchWidth) / 2,
        y: (size - notchHeight) / 2,
        width: notchWidth,
        height: notchHeight
    )
    let notchPath = NSBezierPath(roundedRect: notch, xRadius: notchHeight / 2, yRadius: notchHeight / 2)
    NSColor(srgbRed: 36 / 255, green: 36 / 255, blue: 40 / 255, alpha: 1).setFill()
    notchPath.fill()

    let tabW = size * 0.045
    let tabH = size * 0.07
    NSColor(srgbRed: 36 / 255, green: 36 / 255, blue: 40 / 255, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: notch.minX - tabW * 0.35, y: size / 2 - tabH / 2, width: tabW, height: tabH)).fill()
    NSBezierPath(rect: NSRect(x: notch.maxX - tabW * 0.65, y: size / 2 - tabH / 2, width: tabW, height: tabH)).fill()

    let lens = size * 0.16
    let lensRect = NSRect(x: size / 2 - lens / 2, y: size / 2 - lens / 2, width: lens, height: lens)
    NSColor(srgbRed: 10 / 255, green: 12 / 255, blue: 16 / 255, alpha: 1).setFill()
    NSBezierPath(ovalIn: lensRect).fill()
    for (inset, alpha) in [(0.12, 0.35), (0.28, 0.22), (0.44, 0.18)] {
        let ring = NSBezierPath(ovalIn: lensRect.insetBy(dx: lens * inset, dy: lens * inset))
        NSColor.white.withAlphaComponent(alpha).setStroke()
        ring.lineWidth = max(size * 0.007, 0.6)
        ring.stroke()
    }
    let glint = NSRect(x: size / 2 + lens * 0.08, y: size / 2 - lens * 0.22, width: lens * 0.12, height: lens * 0.12)
    NSColor.white.withAlphaComponent(0.55).setFill()
    NSBezierPath(ovalIn: glint).fill()

    let inset = size * 0.10
    let gate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let barCount = 6
    let barWidth = max(size * 0.038, 1.0)
    let inner = gate.insetBy(dx: barWidth * 0.85, dy: barWidth * 1.1)
    let gap = (inner.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)

    barGrey.setFill()
    barDark.setStroke()

    let frame = NSBezierPath(roundedRect: gate, xRadius: barWidth, yRadius: barWidth)
    frame.lineWidth = barWidth
    frame.stroke()

    let topRail = NSRect(x: gate.minX, y: gate.maxY - barWidth * 1.35, width: gate.width, height: barWidth * 1.15)
    let bottomRail = NSRect(x: gate.minX, y: gate.minY + barWidth * 0.2, width: gate.width, height: barWidth * 1.15)
    NSBezierPath(roundedRect: topRail, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    NSBezierPath(roundedRect: bottomRail, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()

    for i in 0..<barCount {
        let x = inner.minX + CGFloat(i) * (barWidth + gap)
        let bar = NSRect(
            x: x,
            y: inner.minY,
            width: barWidth,
            height: inner.height
        )
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
}

func png(size: Int, accent: NSColor) -> Data {
    let width = size
    let height = size
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("context")
    }
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    drawGate(size: CGFloat(size), accent: accent)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage() else {
        fatalError("image")
    }
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
        fatalError("dest")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return output as Data
}

func write(_ data: Data, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
let extras = URL(fileURLWithPath: CommandLine.arguments[2])
let accents = [
    NSColor(srgbRed: 0, green: 128 / 255, blue: 128 / 255, alpha: 1),
    NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 1),
    NSColor(srgbRed: 1, green: 149 / 255, blue: 0, alpha: 1)
]
let teal = accents[0]

let catalogSizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, name) in catalogSizes {
    write(png(size: size, accent: teal), catalog.appendingPathComponent(name))
}

let exports: [(Int, String)] = [
    (16, "icon_16.png"),
    (32, "icon_32.png"),
    (128, "icon_128.png"),
    (256, "icon_256.png"),
    (512, "icon_512.png"),
    (1024, "icon_1024.png")
]
for (size, name) in exports {
    write(png(size: size, accent: teal), extras.appendingPathComponent(name))
}

write(png(size: 1024, accent: accents[1]), extras.appendingPathComponent("NotchGateIcon-blue-1024.png"))
write(png(size: 1024, accent: accents[2]), extras.appendingPathComponent("NotchGateIcon-orange-1024.png"))
print("wrote gate icons")
