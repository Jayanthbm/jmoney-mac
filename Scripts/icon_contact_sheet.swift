import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Composites the ten appiconset PNGs onto one canvas (largest → smallest) so
/// the artwork can be eyeballed at every size at a glance — small sizes are
/// where icon detail dies.
///
/// Run from the repo root: `swift Scripts/icon_contact_sheet.swift [out.png]`
/// Output defaults to `/tmp/jmoney_icon_sheet.png`.

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/jmoney_icon_sheet.png"

let setDir = "Jmoney/Assets.xcassets/AppIcon.appiconset"
let files = [
    "icon_512x512@2x.png", "icon_512x512.png", "icon_256x256@2x.png",
    "icon_256x256.png", "icon_128x128@2x.png", "icon_128x128.png",
    "icon_32x32@2x.png", "icon_32x32.png", "icon_16x16@2x.png", "icon_16x16.png",
]

func load(_ name: String) -> CGImage? {
    guard let provider = CGImageSourceCreateWithURL(
        URL(fileURLWithPath: "\(setDir)/\(name)") as CFURL, nil
    ) else { return nil }
    return CGImageSourceCreateImageAtIndex(provider, 0, nil)
}

let images = files.compactMap { load($0) }
guard images.count == files.count else {
    fatalError("Expected \(files.count) icons in \(setDir); found \(images.count). Run make_app_icon.swift first.")
}

// Layout: a row per size group, tallest first, on a light canvas.
let tile = 560 // px per slot (largest icon), smaller icons centered in their slot
let columns = 5
let rows = 2
let padding = 40
let canvasW = columns * tile + (columns + 1) * padding
let canvasH = rows * tile + (rows + 1) * padding

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: canvasW, height: canvasH,
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.setFillColor(CGColor(srgbRed: 0.94, green: 0.94, blue: 0.95, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

for (index, image) in images.enumerated() {
    let row = index / columns
    let column = index % columns
    let slotX = padding + column * tile
    let slotY = canvasH - padding - (row + 1) * tile

    // Center the image in its slot at native pixel size (no scaling), so each
    // renders exactly as the system would.
    let x = CGFloat(slotX) + (CGFloat(tile) - CGFloat(image.width)) / 2
    let y = CGFloat(slotY) + (CGFloat(tile) - CGFloat(image.height)) / 2
    context.draw(image, in: CGRect(x: x, y: y, width: CGFloat(image.width), height: CGFloat(image.height)))
}

let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Failed to write \(output)")
}
print("Contact sheet written to \(output)")
