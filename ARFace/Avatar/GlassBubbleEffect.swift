import Foundation
import Metal
import QuartzCore
import OSLog
import RealityKit
import simd

nonisolated final class GlassBubbleFrame: @unchecked Sendable {
    // Scene updates and the renderer exchange value snapshots under this lock.
    private let lock = NSLock()
    private var spheres: [SIMD4<Float>] = []

    func update(spheres: [SIMD4<Float>], cameraZ: Float) {
        lock.lock()
        defer { lock.unlock() }
        self.spheres = spheres.map { sphere in
            SIMD4(sphere.x, sphere.y, sphere.z - cameraZ, sphere.w)
        }.sorted { $0.z < $1.z }
    }

    func snapshot() -> [SIMD4<Float>] {
        lock.lock()
        defer { lock.unlock() }
        return spheres
    }

    /// The scene's look for the post-process: white balance gains, and what bubbles reflect below
    /// and above (SceneLook).
    private var look: [SIMD4<Float>] = GlassBubbleFrame.lookData(SceneLook())

    /// `fringe`: the distortion's colour fringe (off while the phone is hot).
    func update(look: SceneLook, fringe: Bool = true) {
        var data = Self.lookData(look)
        data[4].z = fringe ? 1 : 0
        lock.lock()
        defer { lock.unlock() }
        self.look = data
    }

    func lookSnapshot() -> [SIMD4<Float>] {
        lock.lock()
        defer { lock.unlock() }
        return look
    }

    private static func lookData(_ look: SceneLook) -> [SIMD4<Float>] {
        let environment = look.bubbleEnvironment
        let start = look.vignetteSize
        return [
            SIMD4(look.whiteBalanceGains, 1), SIMD4(environment.low, 1), SIMD4(environment.high, 1),
            SIMD4(min(max(look.vignette, 0), 1), start, start + max(look.vignetteSoftness, 0.05), 0),
            SIMD4(min(max(look.distortion, 0), 1), 0, 0, 0),   // .y: the time, set per frame
        ]
    }


}

@available(iOS 26.0, *)
struct GlassBubbleEffect: PostProcessEffect {
    let frame: GlassBubbleFrame
    private let pipeline: any MTLComputePipelineState
    private let logger = Logger(subsystem: "ARFace", category: "GlassBubbles")

    init(frame: GlassBubbleFrame) throws {
        self.frame = frame
        guard let device = MTLCreateSystemDefaultDevice(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "glassBubbles") else {
            throw CocoaError(.featureUnsupported)
        }
        pipeline = try device.makeComputePipelineState(function: function)
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        let spheres = frame.snapshot()
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            logger.error("Could not encode glass bubbles; copying the scene without bubbles.")
            copySource(context: context)
            return
        }
        var projection = context.projection
        var inverseProjection = simd_inverse(projection)
        var count = UInt32(spheres.count)
        let bounds = spheres.map { sphere -> SIMD4<Float> in
            var lower = SIMD2<Float>(repeating: .infinity)
            var upper = SIMD2<Float>(repeating: -.infinity)
            for x in [Float(-1), 1] {
                for y in [Float(-1), 1] {
                    for z in [Float(-1), 1] {
                        let corner = SIMD4(
                            sphere.x + x * sphere.w,
                            sphere.y + y * sphere.w,
                            sphere.z + z * sphere.w,
                            1
                        )
                        let clip = projection * corner
                        let uv = SIMD2(clip.x, -clip.y) / clip.w * 0.5 + 0.5
                        lower = simd_min(lower, uv)
                        upper = simd_max(upper, uv)
                    }
                }
            }
            return SIMD4(lower.x, lower.y, upper.x, upper.y)
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(context.sourceDepthTexture, index: 1)
        encoder.setTexture(context.targetColorTexture, index: 2)
        let sphereData = spheres.isEmpty ? [SIMD4<Float>.zero] : spheres
        sphereData.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)
        encoder.setBytes(&projection, length: MemoryLayout<simd_float4x4>.size, index: 2)
        encoder.setBytes(&inverseProjection, length: MemoryLayout<simd_float4x4>.size, index: 3)
        let boundData = bounds.isEmpty ? [SIMD4<Float>.zero] : bounds
        boundData.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 4)
        }
        // Bubbles per screen tile, so each pixel only tests the few bubbles near it.
        let (offsets, indices, tileInfo) = Self.tiles(
            bounds: bounds,
            width: context.targetColorTexture.width,
            height: context.targetColorTexture.height
        )
        offsets.withUnsafeBytes { bytes in
            setBuffer(encoder, bytes, index: 5, device: context.device)
        }
        indices.withUnsafeBytes { bytes in
            setBuffer(encoder, bytes, index: 6, device: context.device)
        }
        var info = tileInfo
        encoder.setBytes(&info, length: MemoryLayout<SIMD2<UInt32>>.size, index: 7)
        var look = frame.lookSnapshot()
        look[4].y = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 3600))
        look.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 8)
        }
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreads(
            MTLSize(width: context.targetColorTexture.width, height: context.targetColorTexture.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
        encoder.endEncoding()
    }

    private static let tileSize = 64

    /// Sorts the bubbles' screen bounds (uv) into tiles: offsets (one per tile, plus the end) and
    /// the bubble indices, kept in the bubbles' back-to-front order within each tile.
    private static func tiles(bounds: [SIMD4<Float>], width: Int, height: Int) -> ([UInt32], [UInt16], SIMD2<UInt32>) {
        let tilesX = (width + tileSize - 1) / tileSize
        let tilesY = (height + tileSize - 1) / tileSize
        let ranges: [(x: ClosedRange<Int>, y: ClosedRange<Int>)?] = bounds.map { bound in
            guard bound.x.isFinite, bound.y.isFinite, bound.z.isFinite, bound.w.isFinite,
                  bound.z >= 0, bound.w >= 0, bound.x <= 1, bound.y <= 1 else { return nil }
            func tile(_ uv: Float, _ size: Int, _ count: Int) -> Int {
                min(count - 1, Int(min(max(uv, 0), 1) * Float(size)) / tileSize)
            }
            return (tile(bound.x, width, tilesX)...tile(bound.z, width, tilesX),
                    tile(bound.y, height, tilesY)...tile(bound.w, height, tilesY))
        }
        var offsets = [UInt32](repeating: 0, count: tilesX * tilesY + 1)
        for case let range? in ranges {
            for y in range.y { for x in range.x { offsets[y * tilesX + x + 1] += 1 } }
        }
        for index in 1..<offsets.count { offsets[index] += offsets[index - 1] }
        var fill = offsets
        var indices = [UInt16](repeating: 0, count: max(1, Int(offsets[offsets.count - 1])))
        for (sphere, range) in ranges.enumerated() {
            guard let range else { continue }
            for y in range.y {
                for x in range.x {
                    let tile = y * tilesX + x
                    indices[Int(fill[tile])] = UInt16(sphere)
                    fill[tile] += 1
                }
            }
        }
        return (offsets, indices, SIMD2(UInt32(tilesX), UInt32(tileSize)))
    }

    /// Small data goes inline; larger needs its own buffer (setBytes is limited to 4 KB).
    private func setBuffer(_ encoder: any MTLComputeCommandEncoder, _ bytes: UnsafeRawBufferPointer, index: Int, device: any MTLDevice) {
        if bytes.count <= 4096 {
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: index)
        } else if let buffer = device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count) {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }
    }

    private func copySource(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        guard let encoder = context.commandBuffer.makeBlitCommandEncoder() else {
            logger.error("Could not copy the scene to the post-process output.")
            return
        }
        encoder.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        encoder.endEncoding()
    }
}
