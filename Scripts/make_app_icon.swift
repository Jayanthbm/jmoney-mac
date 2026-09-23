import CoreGraphics
import CoreText
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Renders the Jmoney macOS app icon: the standard Big Sur tile (824/1024 with
/// Apple's 0.225 corner-radius ratio), an indigo→violet gradient, and a white ₹
/// glyph — the app's currency throughout (`AppFormat.currency`, en-IN).
///
/// Writes the classic ten-size macOS appiconset into
/// `Jmoney/Assets.xcassets/AppIcon.appiconset/`, rendering each size directly
/// from vectors (no bitmap downscaling artifacts).
///
/// Run: `swift Scripts/make_app_icon.swift`

let canvas: CGFloat = 1024
let outputDir = "Jmoney/Assets.xcassets/AppIcon.appiconset"

// MARK: - Colors

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let topColor = rgb(79, 70, 229) // indigo 600
let bottomColor = rgb(124, 58, 237) // violet 600
let glyphColor = rgb(255, 255, 255)

// MARK: - Context

func makeContext(size: CGFloat) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.scaleBy(x: size / canvas, y: size / canvas)
    return context
}

// MARK: - Glyph (₹, U+20B9)

let fontSize: CGFloat = 540
var systemFont = CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
if let bold = CTFontCreateCopyWithSymbolicTraits(
    systemFont, fontSize, nil, .boldTrait, .boldTrait
) {
    systemFont = bold
}

var characters = [UniChar(0x20B9)]
var glyph = CGGlyph()
guard CTFontGetGlyphsForCharacters(systemFont, &characters, &glyph, 1) else {
    fatalError("The system font has no glyph for U+20B9 (₹) — cannot render the icon")
}
let bounding = CTFontGetBoundingRectsForGlyphs(
    systemFont, .horizontal, [glyph], nil, 0
)

// Optical centering: dead-center, lifted slightly so the symbol reads balanced.
let glyphX = canvas / 2 - (bounding.origin.x + bounding.width / 2)
let glyphY = canvas / 2 - (bounding.origin.y + bounding.height / 2) - fontSize * 0.02

// MARK: - Render

func render(size: CGFloat) -> CGImage {
    let context = makeContext(size: size)

    // The Big Sur tile: 824/1024, corner radius 0.225 of the tile width.
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius = 824 * 0.225
    let tile = CGPath(roundedRect: tileRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(tile)
    context.clip()

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [topColor, bottomColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvas / 2, y: 924),
        end: CGPoint(x: canvas / 2, y: 100),
        options: []
    )

    // A quiet top highlight so the tile has depth without decoration.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [rgb(255, 255, 255, 0.16), rgb(255, 255, 255, 0.0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: canvas / 2, y: 924),
        end: CGPoint(x: canvas / 2, y: 620),
        options: []
    )

    context.setFillColor(glyphColor)
    CTFontDrawGlyphs(systemFont, [glyph], [CGPoint(x: glyphX, y: glyphY)], 1, context)

    return context.makeImage()!
}

// MARK: - Write PNGs

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to write \(path)")
    }
}

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// The classic ten-entry macOS appiconset.
let sizes: [(file: String, pixels: CGFloat, scale: String, point: String)] = [
    ("icon_16x16.png", 16, "1x", "16x16"),
    ("icon_16x16@2x.png", 32, "2x", "16x16"),
    ("icon_32x32.png", 32, "1x", "32x32"),
    ("icon_32x32@2x.png", 64, "2x", "32x32"),
    ("icon_128x128.png", 128, "1x", "128x128"),
    ("icon_128x128@2x.png", 256, "2x", "128x128"),
    ("icon_256x256.png", 256, "1x", "256x256"),
    ("icon_256x256@2x.png", 512, "2x", "256x256"),
    ("icon_512x512.png", 512, "1x", "512x512"),
    ("icon_512x512@2x.png", 1024, "2x", "512x512"),
]

for entry in sizes {
    let image = render(size: entry.pixels)
    writePNG(image, to: "\(outputDir)/\(entry.file)")
    print("wrote \(entry.file) (\(Int(entry.pixels))px)")
}

// MARK: - Contents.json

var imageEntries = sizes.map { entry in
    """
            {
              "filename" : "\(entry.file)",
              "idiom" : "mac",
              "scale" : "\(entry.scale)",
              "size" : "\(entry.point)"
            }
    """
}
let contentsJSON = """
    {
      "images" : [
    \(imageEntries.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
try contentsJSON.write(
    toFile: "\(outputDir)/Contents.json", atomically: true, encoding: .utf8
)

// The catalog root.
let catalogRoot = "Jmoney/Assets.xcassets"
try? fileManager.createDirectory(atPath: catalogRoot, withIntermediateDirectories: true)
let rootJSON = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
try rootJSON.write(toFile: "\(catalogRoot)/Contents.json", atomically: true, encoding: .utf8)

print("App icon set written to \(outputDir)")
