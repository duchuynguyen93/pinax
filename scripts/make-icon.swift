// Vẽ icon Pinax (tablet đất sét trên nền indigo) thẳng từ vector cho từng cỡ iconset.
// Dùng: swift scripts/make-icon.swift <outdir>
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Squircle (superellipse) – xấp xỉ continuous corner của macOS.
func squircle(_ r: CGRect, n: CGFloat = 4.4) -> CGPath {
    let p = CGMutablePath()
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

func sparkle(center c: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 2
        let r = i % 2 == 0 ? outer : inner
        let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func render(size px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    let small = px <= 32

    // Nền
    let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bg = squircle(bgRect)
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let grad = CGGradient(colorsSpace: space, colors: [rgb(0x3B3F9E), rgb(0x0F1A4A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // highlight đỉnh
    let hl = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    ctx.restoreGState()

    // Tablet (xoay quanh tâm, nghiêng ~-8°)
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 500)
    ctx.rotate(by: -8 * .pi / 180)
    let tw: CGFloat = 500, th: CGFloat = 580
    let outer = CGRect(x: -tw / 2, y: -th / 2, width: tw, height: th)
    // bóng đổ
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 40, color: rgb(0x000020, 0.55))
    ctx.setFillColor(rgb(0xB5573A))
    ctx.addPath(roundRect(outer, 56)); ctx.fillPath()
    ctx.restoreGState()
    // khung
    ctx.setFillColor(rgb(0xA64B30))
    ctx.addPath(roundRect(outer, 56)); ctx.fillPath()
    // mặt
    let b: CGFloat = small ? 34 : 38
    let face = outer.insetBy(dx: b, dy: b)
    ctx.saveGState()
    ctx.addPath(roundRect(face, 30)); ctx.clip()
    let fg = CGGradient(colorsSpace: space, colors: [rgb(0xE79A70), rgb(0xD57F57)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fg, start: CGPoint(x: 0, y: face.maxY), end: CGPoint(x: 0, y: face.minY), options: [])
    ctx.restoreGState()
    // viền sáng mép trên khung
    if !small {
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.22)); ctx.setLineWidth(5)
        ctx.addPath(roundRect(outer.insetBy(dx: 3, dy: 3), 53)); ctx.strokePath()
    }
    // dòng khắc
    let lineH: CGFloat = small ? 44 : 32
    let widths: [CGFloat] = small ? [1, 1, 0.55] : [1, 1, 1, 0.5]
    let left = face.minX + 52, full = face.width - 104
    let gap: CGFloat = small ? 84 : 86
    let startY = face.maxY - 82 - lineH / 2
    for (i, w) in widths.enumerated() {
        let y = startY - CGFloat(i) * gap
        let r = CGRect(x: left, y: y - lineH / 2, width: full * w, height: lineH)
        if !small {
            ctx.setFillColor(rgb(0xFFD2B0, 0.55))
            ctx.addPath(roundRect(r.offsetBy(dx: 0, dy: -4), lineH / 2)); ctx.fillPath()
        }
        ctx.setFillColor(rgb(0x7A3321))
        ctx.addPath(roundRect(r, lineH / 2)); ctx.fillPath()
    }
    ctx.restoreGState()

    // Sparkle ở góc trên phải tablet (toạ độ canvas, đã tính theo phép xoay)
    if !small {
        let a = -8 * CGFloat.pi / 180
        let cx = 250 * cos(a) - 290 * sin(a) + 512
        let cy = 250 * sin(a) + 290 * cos(a) + 500
        let sp = sparkle(center: CGPoint(x: cx - 6, y: cy - 4), outer: 100, inner: 26)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 28, color: rgb(0xFFF1B8, 0.8))
        ctx.setFillColor(rgb(0xFFF6D6))
        ctx.addPath(sp); ctx.fillPath()
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, to url: URL) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    precondition(CGImageDestinationFinalize(d), "ghi PNG lỗi: \(url.path)")
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Dùng: swift make-icon.swift <outdir>\n".utf8)); exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(render(size: 64), to: out.appendingPathComponent("icon_64x64.png"))
writePNG(render(size: 1024), to: out.appendingPathComponent("icon_1024.png"))
