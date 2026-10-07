import Foundation
import Metal
import simd

// Run on a Mac with Metal: xcrun swift Tests/GlassBubbleRenderingChecks.swift
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = try String(contentsOf: repository.appendingPathComponent("ARFace/Avatar/GlassBubbles.metal"), encoding: .utf8)
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fatalError("Glass rendering checks require a Metal-capable Mac.")
}
let library = try device.makeLibrary(source: source, options: nil)
guard let function = library.makeFunction(name: "glassBubbles") else {
    fatalError("Missing glassBubbles kernel.")
}
let pipeline = try device.makeComputePipelineState(function: function)
let width = 256
let scale: Float = 1 / tan(35 * .pi / 360)
let near: Float = 0.01
let far: Float = 10
var projection = simd_float4x4(columns: (
    SIMD4(scale, 0, 0, 0), SIMD4(0, scale, 0, 0),
    SIMD4(0, 0, far / (near - far), -1),
    SIMD4(0, 0, near * far / (near - far), 0)
))
var inverse = simd_inverse(projection)
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba32Float, width: width, height: width, mipmapped: false
)
descriptor.storageMode = .shared
descriptor.usage = [.shaderRead, .shaderWrite]
let input = device.makeTexture(descriptor: descriptor)!
let output = device.makeTexture(descriptor: descriptor)!
let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .r32Float, width: width, height: width, mipmapped: false
)
depthDescriptor.storageMode = .shared
depthDescriptor.usage = [.shaderRead]
let depth = device.makeTexture(descriptor: depthDescriptor)!
let region = MTLRegionMake2D(0, 0, width, width)
let pixels = (0..<(width * width)).map { index -> SIMD4<Float> in
    let x = index % width
    let y = index / width
    return (x / 12 + y / 12) % 2 == 0 ? SIMD4(0.7, 0.85, 0.9, 1) : SIMD4(0.04, 0.22, 0.35, 1)
}
pixels.withUnsafeBytes {
    input.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 16)
}

func render(count: UInt32, backgroundZ: Float) -> [SIMD4<Float>] {
    let clip = projection * SIMD4<Float>(0, 0, backgroundZ, 1)
    let depths = [Float](repeating: clip.z / clip.w, count: width * width)
    depths.withUnsafeBytes {
        depth.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4)
    }
    var sphere = SIMD4<Float>(0, 0, -0.6, 0.1)
    let projectedRadius = scale * sphere.w / (-sphere.z - sphere.w) * 0.5
    var bounds = SIMD4<Float>(0.5 - projectedRadius, 0.5 - projectedRadius,
                              0.5 + projectedRadius, 0.5 + projectedRadius)
    var count = count
    let buffer = queue.makeCommandBuffer()!
    let encoder = buffer.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(depth, index: 1)
    encoder.setTexture(output, index: 2)
    encoder.setBytes(&sphere, length: 16, index: 0)
    encoder.setBytes(&count, length: 4, index: 1)
    encoder.setBytes(&projection, length: 64, index: 2)
    encoder.setBytes(&inverse, length: 64, index: 3)
    encoder.setBytes(&bounds, length: 16, index: 4)
    encoder.dispatchThreads(
        MTLSize(width: width, height: width, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
    )
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    precondition(buffer.status == .completed, "\(String(describing: buffer.error))")
    var result = [SIMD4<Float>](repeating: .zero, count: width * width)
    result.withUnsafeMutableBytes {
        output.getBytes($0.baseAddress!, bytesPerRow: width * 16, from: region, mipmapLevel: 0)
    }
    return result
}

func checkProjection() {
    let empty = render(count: 0, backgroundZ: -1.5)
    precondition(zip(empty, pixels).allSatisfy { simd_distance($0, $1) < 0.0001 })
    let occluded = render(count: 1, backgroundZ: -0.3)
    precondition(zip(occluded, pixels).allSatisfy { simd_distance($0, $1) < 0.0001 })
    let glass = render(count: 1, backgroundZ: -1.5)
    precondition(glass.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w == 1 })
    var changedInterior = 0
    var highlight: Float = 0
    var brightUpperPixels = 0
    for index in glass.indices {
        let x = Float(index % width) - 127.5
        let y = Float(index / width) - 127.5
        let distance = sqrt(x * x + y * y)
        let change = simd_distance(glass[index], pixels[index])
        if distance < 50 && change > 0.1 { changedInterior += 1 }
        if distance > 75 { precondition(change < 0.0001) }
        highlight = max(highlight, glass[index].x)
        if y < 0 && glass[index].z > 1 { brightUpperPixels += 1 }
    }
    precondition(changedInterior > 1000, "The sphere must distort its background, not just draw a rim.")
    precondition(highlight > 1, "Specular highlights must be bright, not dark.")
    precondition(brightUpperPixels > 200, "The bright surface above must create a broad upper highlight.")
}

checkProjection()
// Also cover reversed-Z projections, used by modern renderers.
projection.columns.2.z = near / (far - near)
projection.columns.3.z = near * far / (far - near)
inverse = simd_inverse(projection)
checkProjection()
print("PASS: GPU refraction, bright highlights, foreground occlusion, unchanged exterior/empty pass, finite output, and both depth conventions.")
