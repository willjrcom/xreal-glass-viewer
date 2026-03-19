import Foundation
import Metal
import MetalKit
import OSLog
import AVFoundation
import simd

@available(macOS 11.0, *)
public final class Renderer: NSObject, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD3<Float>
        var texCoord: SIMD2<Float>
    }

    private struct PlaneUniform {
        var modelMatrix: matrix_float4x4
        var aspectRatio: Float
        var cornerRadius: Float
    }

    private struct Uniforms {
        var viewProjection: matrix_float4x4
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let logger = Logger(subsystem: "com.prismaxr.renderer", category: "metal")
    private var textureCache: CVMetalTextureCache?
    private var latestTextures: [MTLTexture?] = [nil, nil, nil]
    private let textureLock = DispatchSemaphore(value: 1)
    private var pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let planeBuffer: MTLBuffer
    private var planeUniforms: [PlaneUniform]
    private let uniformBuffer: MTLBuffer
    private var cameraOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(x: 0, y: 1, z: 0))
    private var aspectRatio: Float
    private var deskLayouts: [DeskLayoutConfiguration]

    public init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        let library: MTLLibrary
#if SWIFT_PACKAGE
        guard let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL),
              let compiledLibrary = try? device.makeLibrary(source: shaderSource, options: nil) else {
            return nil
        }
        library = compiledLibrary
#else
        guard let defaultLibrary = device.makeDefaultLibrary() else { return nil }
        library = defaultLibrary
#endif
        self.device = device
        self.commandQueue = commandQueue
        self.aspectRatio = Float(mtkView.drawableSize.width / max(mtkView.drawableSize.height, 1))

        // Pipeline
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "sceneVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "sceneFragment")
        descriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        descriptor.label = "ScenePipeline"
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        // Geometry buffers
        deskLayouts = .defaultDeskLayouts()

        let vertices = Renderer.makeQuadVertices(width: 1.0, height: 1.0)
        guard let vBuffer = device.makeBuffer(bytes: vertices,
                                              length: MemoryLayout<Vertex>.stride * vertices.count,
                                              options: .storageModeShared) else {
            return nil
        }
        vertexBuffer = vBuffer

        planeUniforms = Renderer.makePlaneUniforms(from: deskLayouts)
        guard let pBuffer = device.makeBuffer(length: MemoryLayout<PlaneUniform>.stride * planeUniforms.count,
                                              options: .storageModeShared) else {
            return nil
        }
        planeBuffer = pBuffer

        guard let uBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared) else {
            return nil
        }
        uniformBuffer = uBuffer

        super.init()
        applyPlaneUniforms()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        mtkView.device = device
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
    }

    public func updateFrame(sampleBuffer: CMSampleBuffer, index: Int = 0) {
        guard index >= 0 && index < 3 else { return }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        guard let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        if result != kCVReturnSuccess {
            logger.error("Failed to create Metal texture from pixel buffer: \(result)")
            return
        }
        guard let cvTexture, let metalTexture = CVMetalTextureGetTexture(cvTexture) else { return }
        if textureLock.wait(timeout: .now() + 0.1) == .success {
            latestTextures[index] = metalTexture
            textureLock.signal()
        }
    }

    public func updateCameraOrientation(_ orientation: simd_quatf) {
        cameraOrientation = orientation
    }

    public func updateLayout(_ configurations: [DeskLayoutConfiguration]) {
        guard !configurations.isEmpty else { return }
        deskLayouts = configurations
        planeUniforms = Renderer.makePlaneUniforms(from: deskLayouts)
        applyPlaneUniforms()
    }

    deinit {
        textureLock.signal() // Libera qualquer thread esperando
        textureCache = nil
        latestTextures = [nil, nil, nil]
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        aspectRatio = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        updateUniforms()

        if textureLock.wait(timeout: .now() + 0.1) == .timedOut {
            return // Skip frame if lock is held too long (prevents hangs)
        }
        let textures = latestTextures
        textureLock.signal()

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(planeBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 2)

        let activeCount = deskLayouts.count
        for i in 0..<min(activeCount, textures.count) {
            if let tex = textures[i] {
                encoder.setFragmentTexture(tex, index: i)
            }
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: activeCount)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspectRatio = Float(size.width / max(size.height, 1))
    }

    private func updateUniforms() {
        let cameraTranslation = matrix_float4x4(translationX: 0, y: 0, z: 0.1)
        let rotation = matrix_float4x4(quaternion: cameraOrientation.inverse)
        let viewMatrix = rotation * cameraTranslation
        let projection = matrix_float4x4(perspectiveFovY: Float.pi / 1.8,
                                         aspectRatio: aspectRatio,
                                         nearZ: 0.01,
                                         farZ: 100)
        var uniforms = Uniforms(viewProjection: projection * viewMatrix)
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
    }

    private static func makeQuadVertices(width: Float, height: Float) -> [Vertex] {
        let w = width / 2
        let h = height / 2
        return [
            Vertex(position: SIMD3(-w, -h, 0), texCoord: SIMD2(0, 1)),
            Vertex(position: SIMD3( w, -h, 0), texCoord: SIMD2(1, 1)),
            Vertex(position: SIMD3(-w,  h, 0), texCoord: SIMD2(0, 0)),
            Vertex(position: SIMD3(-w,  h, 0), texCoord: SIMD2(0, 0)),
            Vertex(position: SIMD3( w, -h, 0), texCoord: SIMD2(1, 1)),
            Vertex(position: SIMD3( w,  h, 0), texCoord: SIMD2(1, 0))
        ]
    }

    private func applyPlaneUniforms() {
        planeUniforms.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            memcpy(planeBuffer.contents(), base, bytes.count)
        }
    }

    private static func makePlaneUniforms(from configs: [DeskLayoutConfiguration]) -> [PlaneUniform] {
        configs.map { config in
            let radius = max(config.radius, 0.5)
            let theta = config.horizontalOffset / radius
            
            let x = sin(theta) * radius
            let z = -cos(theta) * radius
            
            let scale = matrix_float4x4(scaleX: 1.8, y: 1.0, z: 1.0)
            let translation = matrix_float4x4(translationX: x, y: config.height, z: z)
            let rotationY = matrix_float4x4(rotationY: -theta)
            let rotationX = matrix_float4x4(rotationX: config.tilt)
            
            return PlaneUniform(modelMatrix: translation * rotationY * rotationX * scale, 
                               aspectRatio: 16.0 / 9.0, 
                               cornerRadius: 0.08) // Aumentado para um visual mais moderno
        }
    }

    public static func defaultLayouts() -> [DeskLayoutConfiguration] {
        .defaultDeskLayouts()
    }
}

private extension matrix_float4x4 {
    init(translationX x: Float, y: Float, z: Float) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(x, y, z, 1)
    }

    init(scaleX x: Float, y: Float, z: Float) {
        self = matrix_identity_float4x4
        columns.0.x = x
        columns.1.y = y
        columns.2.z = z
    }

    init(quaternion: simd_quatf) {
        self = simd_float4x4(quaternion)
    }

    init(rotationY radians: Float) {
        self = matrix_float4x4(columns: (
            SIMD4<Float>(cos(radians), 0, -sin(radians), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sin(radians), 0, cos(radians), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    init(rotationX radians: Float) {
        let c = cos(radians)
        let s = sin(radians)
        self = matrix_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    init(perspectiveFovY fovyRadians: Float, aspectRatio: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovyRadians * 0.5)
        let xScale = yScale / aspectRatio
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -(2 * farZ * nearZ) / zRange

        self = matrix_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }
}
