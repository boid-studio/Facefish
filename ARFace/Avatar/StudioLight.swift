import CoreGraphics
import Foundation
import RealityKit

/// A studio beauty-light environment for the fish (in place of RealityKit's generic default): what
/// she reflects and is lit by besides the scene's lights. Made here as an HDR panorama, so its
/// lights read as clear shapes in her glossy eyes and the gold mask:
///
/// - key: a softbox above and in front, bright and white (the clear, rectangular catchlight high
///   in the eyes)
/// - rims: two tall strip lights behind her, either side (bright edges on her and her fins)
/// - fill: a soft bounce from below (under the chin and lips)
/// - a dark studio around them, so the reflections stay clean.
///
/// Directions: +Z toward the camera, +Y up; the lights are placed by azimuth from +Z (the
/// panorama's middle faces -Z, as RealityKit reads it).
enum StudioLight {
    /// How bright the studio is overall (RealityKit's exponent: +1 doubles it).
    static let intensityExponent: Float = 0

    @MainActor
    static func environment() -> EnvironmentResource? {
        let width = 1024, height = 512
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let degrees = Float.pi / 180

        /// A soft-edged rectangle of light, `size` degrees across, centred at azimuth/elevation.
        func box(_ azimuth: Float, _ elevation: Float, center: (Float, Float), size: (Float, Float), soft: Float) -> Float {
            var da = azimuth - center.0 * degrees
            if da > .pi { da -= 2 * .pi }
            if da < -.pi { da += 2 * .pi }
            let de = elevation - center.1 * degrees
            let ex = (abs(da) - size.0 * degrees / 2) / (soft * degrees)
            let ey = (abs(de) - size.1 * degrees / 2) / (soft * degrees)
            return (1 - smooth(ex)) * (1 - smooth(ey))
        }
        func smooth(_ x: Float) -> Float {
            let t = min(max(x * 0.5 + 0.5, 0), 1)
            return t * t * (3 - 2 * t)
        }

        for y in 0..<height {
            let elevation = (0.5 - (Float(y) + 0.5) / Float(height)) * .pi       // +90° at the top
            for x in 0..<width {
                // RealityKit centres the panorama behind (-Z): azimuth 0 (+Z, toward the camera) is at
                // its edges.
                let azimuth = ((Float(x) + 0.5) / Float(width) - 0.5) * 2 * .pi + .pi
                let direction = SIMD3<Float>(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))

                // The dark studio: a little lighter above than below.
                var light = SIMD3<Float>(repeating: 0.012 + 0.012 * max(direction.y, 0))
                // Key: a softbox above the camera, pure white; small and bright, so its catchlight reads
                // white without lighting her more.
                light += SIMD3(repeating: 25) * box(azimuth, elevation, center: (0, 28), size: (40, 22), soft: 2.5)
                // Rims: tall strips behind, left and right, a touch cool.
                for side: Float in [-1, 1] {
                    light += SIMD3(0.93, 0.97, 1.0) * 4.5 * box(azimuth, elevation, center: (side * 125, 5), size: (12, 75), soft: 2)
                }
                // Fill: a soft bounce from below, in front.
                light += SIMD3(repeating: 0.9) * box(azimuth, elevation, center: (0, -35), size: (90, 30), soft: 12)

                let index = (y * width + x) * 4
                pixels[index] = light.x
                pixels[index + 1] = light.y
                pixels[index + 2] = light.z
                pixels[index + 3] = 1
            }
        }

        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
                  bytesPerRow: width * 16, space: space,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return try? EnvironmentResource(equirectangular: image, withName: "studio")
    }
}
