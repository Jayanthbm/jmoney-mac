import CoreGraphics
import CoreText
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Renders the Jmoney macOS app icon set from a single square source image.
///
/// The source is the brand icon of the Jmoney app (the React Native project's
/// `assets/icon.png`); pass its path as the first argument (defaults to
/// `../jayledger/assets/icon.png` relative to the repo root).
///
/// macOS icons carry their own mask in the artwork: the source is drawn into a
/// 1024×1024 canvas as the standard Big Sur tile — 824×824 centered, with
/// Apple's 0.225 corner-radius ratio — so the rounded corners are baked in.
/// All ten classic macOS sizes are written for the AppIcon.appiconset.
///
/// Run: `swift Scripts/make_app_icon.swift [path/to/source.png]`

let canvas: CGFloat = 1024
let tileSize: CGFloat = 824
let tileRadius: CGFloat = tileSize * 0.225
let outputDir = "Jmoney/Assets.xcassets/AppIcon.appiconset"

let arguments = CommandLine.arguments
let sourcePath = arguments.count > 1
    ? arguments[1]
    : "../jayledger/assets/icon.png"

// MARK: - Load the source

guard let sourceProvider = CGImageSourceCreateWithURL(
    URL(fileURLWithPath: sourcePath) as CFURL, nil
) else {
    fatalError("Cannot read source icon at \(sourcePath)")
}
let sourceImage = CGImageSourceCreateImageAtIndex(sourceProvider, 0, nil)!
let sourceSize = CGFloat(sourceImage.width)

// MARK: - Render

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

func render(size: CGFloat) -> CGImage {
    let context = makeContext(size: size)

    // The Big Sur tile: centered 824×824, corner radius 824 × 0.225.
    let margin = (canvas - tileSize) / 2
    let tileRect = CGRect(x: margin, y: margin, width: tileSize, height: tileSize)
    let tile = CGPath(
        roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil
    )
    context.addPath(tile)
    context.clip()

    // Draw the square source scaled to fill the tile exactly (aspect fill;
    // a square source needs no cropping).
    let scale = tileSize / sourceSize
    let drawRect = CGRect(
        x: margin - (sourceSize * scale - tileSize) / 2,
        y: margin - (sourceSize * scale - tileSize) / 2,
        width: sourceSize * scale,
        height: sourceSize * scale
    )
    context.draw(sourceImage, in: drawRect)

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

let imageEntries = sizes.map { entry in
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

print("App icon set written to \(outputDir) from \(sourcePath)")
