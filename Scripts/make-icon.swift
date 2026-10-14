// Dibuja el icono de la app y genera Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift
//
// El diseño vive aquí en código para poder ajustarlo sin herramientas de
// diseño ni Xcode. Sigue la retícula de iconos de macOS: lienzo de 1024 px con
// el cuerpo de 824 px centrado.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(in context: CGContext) {
    let canvas: CGFloat = 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Sombra del cuerpo, como en los iconos del sistema.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0x1C1C1E))
    context.fillPath()
    context.restoreGState()

    // Fondo: degradado índigo a azul.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x6E5CF0), color(0x2F7BF6), color(0x18A0F0)] as CFArray,
        locations: [0, 0.6, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Franja superior oscura: la barra de menús de la que cuelga el notch.
    context.setFillColor(color(0x000000, 0.9))
    context.fill(CGRect(x: body.minX, y: body.maxY - 92, width: body.width, height: 92))

    // Panel del notch expandido, con las esquinas inferiores redondeadas.
    let panel = CGRect(x: canvas / 2 - 290, y: body.maxY - 92 - 300, width: 580, height: 300 + 92)
    let radius: CGFloat = 96
    let panelPath = CGMutablePath()
    panelPath.move(to: CGPoint(x: panel.minX, y: panel.maxY))
    panelPath.addLine(to: CGPoint(x: panel.minX, y: panel.minY + radius))
    panelPath.addArc(tangent1End: CGPoint(x: panel.minX, y: panel.minY), tangent2End: CGPoint(x: panel.minX + radius, y: panel.minY), radius: radius)
    panelPath.addLine(to: CGPoint(x: panel.maxX - radius, y: panel.minY))
    panelPath.addArc(tangent1End: CGPoint(x: panel.maxX, y: panel.minY), tangent2End: CGPoint(x: panel.maxX, y: panel.minY + radius), radius: radius)
    panelPath.addLine(to: CGPoint(x: panel.maxX, y: panel.maxY))
    panelPath.closeSubpath()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: color(0x000000, 0.45))
    context.addPath(panelPath)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // Ondas de audio a la izquierda dentro del panel.
    let barWidth: CGFloat = 30
    let heights: [CGFloat] = [70, 130, 95, 160, 80]
    let barsBaseY = panel.minY + 150
    for (index, height) in heights.enumerated() {
        let x = panel.minX + 80 + CGFloat(index) * (barWidth + 18)
        let bar = CGRect(x: x, y: barsBaseY - height / 2, width: barWidth, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    }
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()

    // Indicador de evento a la derecha: un punto y una barra de progreso.
    context.setFillColor(color(0x30D158))
    context.fillEllipse(in: CGRect(x: panel.maxX - 150, y: barsBaseY + 20, width: 56, height: 56))
    let track = CGRect(x: panel.maxX - 210, y: barsBaseY - 60, width: 130, height: 22)
    context.addPath(CGPath(roundedRect: track, cornerWidth: 11, cornerHeight: 11, transform: nil))
    context.setFillColor(color(0xFFFFFF, 0.3))
    context.fillPath()
    let progress = CGRect(x: track.minX, y: track.minY, width: 78, height: track.height)
    context.addPath(CGPath(roundedRect: progress, cornerWidth: 11, cornerHeight: 11, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
}

func renderPNG(size: Int, to url: URL) throws {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try renderPNG(size: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(size: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try renderPNG(size: 1024, to: resources.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil falló") }
print("Creado: \(resources.appendingPathComponent("AppIcon.icns").path)")
