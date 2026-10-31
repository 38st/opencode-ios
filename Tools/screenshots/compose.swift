// The README hero: the iPad workspace with an iPhone in front of its lower right corner.
//   xcrun swift Tools/screenshots/compose.swift <ipad.png> <iphone.png> <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 4 else { FileHandle.standardError.write(Data("usage: compose.swift ipad.png iphone.png out.png\n".utf8)); exit(2) }

func image(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read \(path)") }
    return image
}

/// XCUIScreen saves a landscape screen in portrait pixels; turn it back to landscape.
func landscape(_ image: CGImage) -> CGImage {
    guard image.height > image.width,
          let context = CGContext(data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    context.translateBy(x: CGFloat(image.height), y: 0)
    context.rotate(by: .pi / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage() ?? image
}

let ipad = landscape(image(arguments[1])), iphone = image(arguments[2])
let width = 1600.0, height = 1033.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No context") }
context.interpolationQuality = .high
context.setFillColor(CGColor(srgbRed: 0.945, green: 0.945, blue: 0.94, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

/// A screen with rounded corners, a thin bezel and a soft shadow. Core Graphics' origin is the lower left.
func device(_ screen: CGImage, in frame: CGRect, radius: CGFloat, bezel: CGFloat) {
    let body = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: CGColor(gray: 0, alpha: 0.22))
    context.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    context.addPath(body); context.fillPath()
    context.restoreGState()
    let inner = frame.insetBy(dx: bezel, dy: bezel), innerRadius = max(0, radius - bezel)
    context.saveGState()
    context.addPath(CGPath(roundedRect: inner, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil)); context.clip()
    context.draw(screen, in: inner)
    context.restoreGState()
}

// The iPad, landscape, scaled to leave a margin; the iPhone overlaps its lower right corner.
let ipadAspect = Double(ipad.width) / Double(ipad.height)
let ipadWidth = 1300.0, ipadHeight = ipadWidth / ipadAspect
let ipadFrame = CGRect(x: 60, y: height - 50 - ipadHeight, width: ipadWidth, height: ipadHeight)
device(ipad, in: ipadFrame, radius: 34, bezel: 14)
let phoneAspect = Double(iphone.width) / Double(iphone.height)
let phoneHeight = height - 80, phoneWidth = phoneHeight * phoneAspect
device(iphone, in: CGRect(x: width - 60 - phoneWidth, y: 30, width: phoneWidth, height: phoneHeight), radius: 52, bezel: 10)

guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[3]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot write") }
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(arguments[3])") }
