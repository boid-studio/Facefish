import CoreGraphics
import SwiftUI

// swiftc ARFace/Views/PhoneOrientationEffect.swift Tests/PhoneCanvasRenderingChecks.swift -o /tmp/PhoneCanvasRenderingChecks
// /tmp/PhoneCanvasRenderingChecks
@main
@MainActor
struct PhoneCanvasRenderingChecks {
    static func render(
        width: Int, height: Int, scale: Int, isUpsideDown: Bool, showsControls: Bool = false
    ) -> [UInt8] {
        let canvas = ZStack {
            VStack(spacing: 0) {
                Color.blue
                Color.green
            }
            Rectangle()
                .fill(.white)
                .frame(width: 16, height: 24)
                .offset(y: -20)
        }
        .overlay(alignment: .topLeading) {
            Color.red.frame(width: 20, height: 20)
        }
        .overlay(alignment: .bottomTrailing) {
            Color.yellow.frame(width: 20, height: 20)
        }
        .frame(width: CGFloat(width), height: CGFloat(height))
        .modifier(PhoneOrientationEffect(isUpsideDown: isUpsideDown))
        .overlay(alignment: .bottomTrailing) {
            if showsControls {
                Color.black.frame(width: 12, height: 12)
            }
        }

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = CGFloat(scale)
        guard let image = renderer.cgImage else {
            fatalError("Could not render the phone canvas.")
        }
        let pixelWidth = width * scale
        let pixelHeight = height * scale
        precondition(image.width == pixelWidth && image.height == pixelHeight,
                     "Rotating a non-square phone canvas must preserve its dimensions.")
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        precondition(rendered, "Could not read the rendered phone canvas.")
        return pixels
    }

    static func check(width: Int, height: Int, scale: Int) {
        let upright = render(width: width, height: height, scale: scale, isUpsideDown: false)
        let upsideDown = render(width: width, height: height, scale: scale, isUpsideDown: true)
        let pixelWidth = width * scale
        let pixelHeight = height * scale
        var changedPixels = 0
        var mismatchedPixels = 0
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let index = (y * pixelWidth + x) * 4
                let opposite = ((pixelHeight - 1 - y) * pixelWidth + pixelWidth - 1 - x) * 4
                if (0..<4).contains(where: {
                    abs(Int(upright[index + $0]) - Int(upsideDown[opposite + $0])) > 1
                }) {
                    mismatchedPixels += 1
                }
                if upright[index..<index + 4] != upsideDown[index..<index + 4] {
                    changedPixels += 1
                }
            }
        }
        // Allow 0.1% for corner antialiasing differences introduced by the half-turn.
        precondition(mismatchedPixels <= pixelWidth * pixelHeight / 1_000,
                     "The background, avatar and overlays must all rotate together by 180 degrees (\(width)x\(height) @\(scale)x, \(mismatchedPixels) mismatches).")
        precondition(changedPixels > pixelWidth * pixelHeight * 9 / 10,
                     "Rotation must change the background, not only the small avatar.")
        precondition(render(width: width, height: height, scale: scale, isUpsideDown: false) == upright,
                     "Returning to upright must restore the original canvas.")
        let uprightControls = render(width: width, height: height, scale: scale, isUpsideDown: false, showsControls: true)
        let invertedControls = render(width: width, height: height, scale: scale, isUpsideDown: true, showsControls: true)
        var controlPixels = 0
        for index in stride(from: 0, to: uprightControls.count, by: 4) {
            if uprightControls[index..<index + 3].allSatisfy({ $0 == 0 }) {
                precondition(invertedControls[index..<index + 3].allSatisfy({ $0 == 0 }),
                             "Bottom controls must stay in the same position when the canvas rotates.")
                controlPixels += 1
            }
        }
        precondition(controlPixels >= 100 * scale * scale, "The fixed controls must be visible.")
        print("Phone canvas rendering checks passed: \(width)x\(height) @\(scale)x (\(changedPixels) rotated pixels).")
    }

    static func main() {
        for (width, height) in [(120, 200), (200, 260)] {
            for scale in 1...3 {
                check(width: width, height: height, scale: scale)
            }
        }
    }
}
