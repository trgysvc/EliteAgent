import SwiftUI
import MetalKit
import Metal

public struct VisualizerView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        
        // Dynamic Framerate: Cap at 30 FPS while loading to free up PCI bandwidth for mmap
        mtkView.preferredFramesPerSecond = ModelSetupManager.shared.isModelReady ? 120 : 30
        
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.preferredFramesPerSecond = ModelSetupManager.shared.isModelReady ? 120 : 30
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    public class Coordinator: NSObject, MTKViewDelegate {
        var commandQueue: MTLCommandQueue?
        var computePipelineState: MTLComputePipelineState?
        var renderPipelineState: MTLRenderPipelineState?
        
        // Triple Buffering for Thread-Safe Uniform Sync
        private let inFlightSemaphore = DispatchSemaphore(value: 3)
        private var uniformBuffers: [MTLBuffer] = []
        private var uniformBufferIndex = 0
        
        var particleBuffer: MTLBuffer?
        private let maxParticles = 1024
        private let startTime = Date()
        
        struct KernelUniforms {
            var state: Int32
            var progress: Float
            var time: Float
        }
        
        override init() {
            super.init()
            setupMetal()
        }
        
        private func setupMetal() {
            let device = MTLCreateSystemDefaultDevice()!
            commandQueue = device.makeCommandQueue()
            
            guard let library = device.makeDefaultLibrary() else { return }
            
            let computeFunction = library.makeFunction(name: "neural_compute")
            computePipelineState = try? device.makeComputePipelineState(function: computeFunction!)
            
            let vertexFunction = library.makeFunction(name: "neural_vertex")
            let fragmentFunction = library.makeFunction(name: "neural_fragment")
            
            let renderDescriptor = MTLRenderPipelineDescriptor()
            renderDescriptor.vertexFunction = vertexFunction
            renderDescriptor.fragmentFunction = fragmentFunction
            renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            renderDescriptor.colorAttachments[0].isBlendingEnabled = true
            
            renderPipelineState = try? device.makeRenderPipelineState(descriptor: renderDescriptor)
            
            particleBuffer = device.makeBuffer(length: maxParticles * 32, options: .storageModePrivate)
            
            // Initialize Triple Uniform Buffers
            for _ in 0..<3 {
                let buffer = device.makeBuffer(length: MemoryLayout<KernelUniforms>.stride, options: .storageModeShared)!
                uniformBuffers.append(buffer)
            }
        }
        
        public func draw(in view: MTKView) {
            // Wait for GPU to finish with the buffer we are about to write to
            _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
            
            guard let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let sharedBuffer = InferenceActor.shared.sharedBuffer.buffer,
                  let particleBuffer = self.particleBuffer,
                  let computePipeline = computePipelineState,
                  let renderPipeline = renderPipelineState,
                  let renderDescriptor = view.currentRenderPassDescriptor else {
                inFlightSemaphore.signal()
                return
            }
            
            // Update Uniform Buffer for current frame
            let uniforms = KernelUniforms(
                state: Int32(ModelSetupManager.shared.loadState.rawValue),
                progress: Float(ModelSetupManager.shared.downloadProgress),
                time: Float(Date().timeIntervalSince(startTime))
            )
            
            let currentUniformBuffer = uniformBuffers[uniformBufferIndex]
            currentUniformBuffer.contents().copyMemory(from: [uniforms], byteCount: MemoryLayout<KernelUniforms>.stride)
            
            // Completion handler to signal semaphore when GPU is done
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.inFlightSemaphore.signal()
            }
            
            // 1. Compute Pass
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(computePipeline)
                computeEncoder.setBuffer(sharedBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(particleBuffer, offset: 0, index: 1)
                computeEncoder.setBuffer(currentUniformBuffer, offset: 0, index: 2)
                
                let threadsPerThreadgroup = MTLSize(width: 32, height: 1, depth: 1)
                let threadgroupsPerGrid = MTLSize(width: maxParticles / 32, height: 1, depth: 1)
                computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()
            }
            
            // 2. Render Pass
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) {
                renderEncoder.setRenderPipelineState(renderPipeline)
                renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
                
                var identity = matrix_identity_float4x4
                renderEncoder.setVertexBytes(&identity, length: MemoryLayout<float4x4>.size, index: 1)
                renderEncoder.setVertexBuffer(currentUniformBuffer, offset: 0, index: 2)
                
                renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: maxParticles)
                renderEncoder.endEncoding()
            }
            
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
            
            // Rotate buffer index
            uniformBufferIndex = (uniformBufferIndex + 1) % 3
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    }
}
