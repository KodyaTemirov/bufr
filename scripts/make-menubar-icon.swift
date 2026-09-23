// Builds the menu bar template icon from the app logo: the rounded square with the letter cut
// out, black on transparent (macOS tints template images for light and dark menu bars).
//
// Usage: swift scripts/make-menubar-icon.swift <logo.png> <output directory>
// Writes MenuBarIcon.png (16 px) and MenuBarIcon@2x.png (32 px).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    print("usage: make-menubar-icon <logo.png> <output directory>")
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[2])

let width = logo.width, height = logo.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
pixels.withUnsafeMutableBytes { raw in
    let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(logo, in: CGRect(x: 0, y: 0, width: width, height: height))
}

// Mask = the square's coverage minus the letter (bright pixels; the square itself is blue)
var mask = [UInt8](repeating: 0, count: width * height * 4)
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let p = (y * width + x) * 4
        let alpha = Double(pixels[p + 3]) / 255
        guard alpha > 0.02 else { continue }
        let red = Double(pixels[p]) / 255 / alpha // un-premultiplied
        let letter = min(1, max(0, (red - 0.5) / 0.2))
        let coverage = alpha * (1 - letter)
        mask[p + 3] = UInt8((coverage * 255).rounded())
        if alpha > 0.5 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
let side = max(maxX - minX, maxY - minY) + 1
let crop = CGRect(x: minX, y: minY, width: side, height: side)

let maskImage: CGImage = mask.withUnsafeMutableBytes { raw in
    let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!.cropping(to: crop)!
}

for (name, size) in [("MenuBarIcon.png", 16), ("MenuBarIcon@2x.png", 32)] {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(maskImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    let destination = CGImageDestinationCreateWithURL(outputDirectory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(name) (\(size)×\(size))")
}
