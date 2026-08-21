import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillRounded(_ rect: CGRect, radius: CGFloat, fill: CGColor) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setFillColor(fill)
    context.fillPath()
}

func strokeRounded(_ rect: CGRect, radius: CGFloat, stroke: CGColor, width: CGFloat) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.strokePath()
}

context.saveGState()
let background = CGGradient(colorsSpace: colorSpace,
    colors: [color(0.08, 0.11, 0.24), color(0.12, 0.28, 0.55), color(0.10, 0.55, 0.58)] as CFArray,
    locations: [0, 0.55, 1])!
// Let macOS apply the app-icon mask. Keeping the artwork edge-to-edge avoids
// transparent wedges when the same mark is shown in the menu bar or sidebar.
context.addRect(CGRect(x: 0, y: 0, width: size, height: size))
context.clip()
context.drawLinearGradient(background, start: CGPoint(x: 120, y: 120), end: CGPoint(x: 900, y: 930),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.restoreGState()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: color(0.01, 0.03, 0.10, 0.45))
fillRounded(CGRect(x: 220, y: 145, width: 584, height: 700), radius: 86, fill: color(0.96, 0.98, 1.0))
context.restoreGState()
strokeRounded(CGRect(x: 220, y: 145, width: 584, height: 700), radius: 86, stroke: color(1, 1, 1, 0.6), width: 4)

// The colored tab is the "clip" in ClipMemo.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 12, color: color(0.02, 0.06, 0.14, 0.2))
fillRounded(CGRect(x: 374, y: 738, width: 276, height: 132), radius: 52, fill: color(1.0, 0.74, 0.25))
context.restoreGState()
fillRounded(CGRect(x: 436, y: 766, width: 152, height: 58), radius: 28, fill: color(0.14, 0.20, 0.36))

let rowColors: [CGColor] = [color(0.16, 0.76, 0.71), color(0.98, 0.38, 0.35), color(0.98, 0.74, 0.22)]
for (index, rowColor) in rowColors.enumerated() {
    let y = CGFloat(620 - index * 122)
    fillRounded(CGRect(x: 310, y: y, width: 42, height: 42), radius: 14, fill: rowColor)
    fillRounded(CGRect(x: 390, y: y + 8, width: 280, height: 26), radius: 13, fill: color(0.56, 0.63, 0.76, 0.55))
}

// A small spark turns the generic clipboard into a memory cue.
let spark = CGMutablePath()
spark.move(to: CGPoint(x: 786, y: 720))
spark.addLine(to: CGPoint(x: 812, y: 780))
spark.addLine(to: CGPoint(x: 872, y: 806))
spark.addLine(to: CGPoint(x: 812, y: 832))
spark.addLine(to: CGPoint(x: 786, y: 892))
spark.addLine(to: CGPoint(x: 760, y: 832))
spark.addLine(to: CGPoint(x: 700, y: 806))
spark.addLine(to: CGPoint(x: 760, y: 780))
spark.closeSubpath()
context.addPath(spark)
context.setFillColor(color(1.0, 0.78, 0.28))
context.fillPath()

let image = context.makeImage()!
let output = CommandLine.arguments.dropFirst().first ?? "ClipMemoLogo.png"
let destination = URL(fileURLWithPath: output)
let imageDestination = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(imageDestination, image, nil)
CGImageDestinationFinalize(imageDestination)
