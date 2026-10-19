// Genera el iconset de la app. Uso: swift make-icon.swift <salida.icns> [imagen-fuente]
// Con imagen fuente, la recorta en la forma redondeada de los iconos de macOS;
// sin ella, dibuja el símbolo de la marca: cartas en abanico con una gráfica encima.
import AppKit

let source: NSImage? = CommandLine.arguments.count > 2 ? NSImage(contentsOfFile: CommandLine.arguments[2]) : nil

// Paleta de la marca.
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let ink = rgb(0x1A0B3D)
let tileBorder = rgb(0xE4DCFB)

// El símbolo está diseñado en un lienzo de ~900×960 unidades con el eje y hacia abajo.
// Cada carta: centro, giro en grados (positivo = horario) y color, de la de atrás a la de delante.
let cards: [(center: CGPoint, angle: CGFloat, color: CGColor)] = [
    (CGPoint(x: 307, y: 622), -19, rgb(0xC4B5FD)),
    (CGPoint(x: 362, y: 522), -6, rgb(0xA78BFA)),
    (CGPoint(x: 450, y: 405), 6, rgb(0x8B5CF6)),
    (CGPoint(x: 582, y: 325), 19.5, rgb(0x6D28D9)),
]
let cardSize = CGSize(width: 344, height: 462)
let chart: [(point: CGPoint, radius: CGFloat)] = [
    (CGPoint(x: 225, y: 393), 28), (CGPoint(x: 320, y: 260), 28),
    (CGPoint(x: 482, y: 155), 30), (CGPoint(x: 672, y: 92), 38),
]
let symbolCenter = CGPoint(x: 450, y: 470)
let symbolHeight: CGFloat = 860

/// En tamaños chicos se engrosan los contornos y se omiten los detalles finos.
struct Detail {
    var outline: CGFloat   // contorno blanco de cartas y gráfica
    var line: CGFloat      // grosor de la línea de la gráfica
    var dot: CGFloat       // factor del radio de los puntos
    var inner: Bool        // marco interior y contenido de las cartas
    var scale: CGFloat     // alto del símbolo respecto al azulejo
}

func detail(for pixels: Int) -> Detail {
    switch pixels {
    case ..<24:  Detail(outline: 30, line: 60, dot: 1.8, inner: false, scale: 0.86)
    case ..<48:  Detail(outline: 22, line: 46, dot: 1.5, inner: false, scale: 0.82)
    case ..<100: Detail(outline: 14, line: 36, dot: 1.25, inner: true, scale: 0.78)
    default:     Detail(outline: 11, line: 30, dot: 1.15, inner: true, scale: 0.74)
    }
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawCard(_ ctx: CGContext, center: CGPoint, angle: CGFloat, color: CGColor, front: Bool, detail d: Detail) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let rect = CGRect(x: -cardSize.width / 2, y: -cardSize.height / 2, width: cardSize.width, height: cardSize.height)
    let radius: CGFloat = 26

    ctx.setFillColor(.white)
    ctx.addPath(roundedRect(rect.insetBy(dx: -d.outline, dy: -d.outline), radius + d.outline))
    ctx.fillPath()
    ctx.setFillColor(color)
    ctx.addPath(roundedRect(rect, radius))
    ctx.fillPath()
    guard d.inner else { return }

    ctx.setStrokeColor(rgb(0xFFFFFF, 0.45))
    ctx.setLineWidth(5)
    ctx.addPath(roundedRect(rect.insetBy(dx: 15, dy: 15), 16))
    ctx.strokePath()

    // Ilustración y dos renglones de texto.
    ctx.setFillColor(rgb(0xFFFFFF, front ? 0.28 : 0.22))
    ctx.addPath(roundedRect(CGRect(x: rect.minX + 34, y: rect.minY + 36, width: cardSize.width - 68, height: 190), 16))
    ctx.fillPath()
    ctx.setStrokeColor(rgb(0xFFFFFF, front ? 0.32 : 0.25))
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    for (y, width) in [(rect.minY + 272, cardSize.width - 92), (rect.minY + 318, cardSize.width - 190)] {
        ctx.move(to: CGPoint(x: rect.minX + 42, y: y))
        ctx.addLine(to: CGPoint(x: rect.minX + 42 + width, y: y))
    }
    ctx.strokePath()
}

func drawChart(_ ctx: CGContext, detail d: Detail) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (color, extra) in [(CGColor.white, d.outline), (ink, 0)] {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(d.line + 2 * extra)
        ctx.addLines(between: chart.map(\.point))
        ctx.strokePath()
        ctx.setFillColor(color)
        for dot in chart {
            let r = dot.radius * d.dot + extra
            ctx.fillEllipse(in: CGRect(x: dot.point.x - r, y: dot.point.y - r, width: 2 * r, height: 2 * r))
        }
    }
}

func draw(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let s = CGFloat(size) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    if let source {
        NSGraphicsContext.current?.imageInterpolation = .high
        path.addClip()
        source.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
        return rep
    }
    let ctx = NSGraphicsContext.current!.cgContext

    // Azulejo blanco con un borde lila suave y una sombra ligera.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s, color: rgb(0x1A0B3D, 0.22))
    ctx.setFillColor(.white)
    ctx.addPath(path.cgPath)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path.cgPath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [CGColor.white, rgb(0xF5F3FF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(tileBorder)
    ctx.setLineWidth(max(1, 4 * s))
    ctx.addPath(NSBezierPath(roundedRect: tile.insetBy(dx: 2 * s, dy: 2 * s), xRadius: 183 * s, yRadius: 183 * s).cgPath)
    ctx.strokePath()

    // Símbolo centrado en el azulejo, con el eje y hacia abajo.
    let d = detail(for: size)
    let k = tile.height * d.scale / symbolHeight
    ctx.translateBy(x: tile.midX, y: tile.midY)
    ctx.scaleBy(x: k, y: -k)
    ctx.translateBy(x: -symbolCenter.x, y: -symbolCenter.y)
    for (i, card) in cards.enumerated() {
        drawCard(ctx, center: card.center, angle: card.angle, color: card.color, front: i == cards.count - 1, detail: d)
    }
    drawChart(ctx, detail: d)
    return rep
}

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = draw(size: base * scale).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
