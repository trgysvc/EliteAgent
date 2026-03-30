import SwiftUI
import MetalKit
import Metal

/// SwiftUI bridge for the Metal-powered Neural Sight engine.
public struct VisualizerView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0) // Transparent for glass effect
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 120
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    public class Coordinator: NSObject, MTKViewDelegate {
        var commandQueue: MTLCommandQueue?
        var computePipelineState: MTLComputePipelineState?
        var renderPipelineState: MTLRenderPipelineState?
        
        var particleBuffer: MTLBuffer?
        private let maxParticles = 1024
        
        override init() {
            super.init()
            setupMetal()
        }
        
        private func setupMetal() {
            let device = MTLCreateSystemDefaultDevice()
            commandQueue = device?.makeCommandQueue()
            
            // Link to the compiled shaders in the main bundle
            guard let library = device?.makeDefaultLibrary() else { return }
            
            let computeFunction = library.makeFunction(name: "neural_compute")
            computePipelineState = try? device?.makeComputePipelineState(function: computeFunction!)
            
            let vertexFunction = library.makeFunction(name: "neural_vertex")
            let fragmentFunction = library.makeFunction(name: "neural_fragment")
            
            let renderDescriptor = MTLRenderPipelineDescriptor()
            renderDescriptor.vertexFunction = vertexFunction
            renderDescriptor.fragmentFunction = fragmentFunction
            renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            renderDescriptor.colorAttachments[0].isBlendingEnabled = true
            
            renderPipelineState = try? device?.makeRenderPipelineState(descriptor: renderDescriptor)
            
            particleBuffer = device?.makeBuffer(length: maxParticles * 32, options: .storageModePrivate)
        }
        
        public func draw(in view: MTKView) {
            // Guard all resources at the the top to ensure safe encoder lifecycle
            guard let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let sharedBuffer = InferenceActor.shared.sharedBuffer.buffer,
                  let particleBuffer = self.particleBuffer,
                  let computePipeline = computePipelineState,
                  let renderPipeline = renderPipelineState,
                  let renderDescriptor = view.currentRenderPassDescriptor else { return }
            
            // 1. Compute Pass: Transform activations to particles
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(computePipeline)
                computeEncoder.setBuffer(sharedBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(particleBuffer, offset: 0, index: 1)
                
                let threadsPerThreadgroup = MTLSize(width: 32, height: 1, depth: 1)
                let threadgroupsPerGrid = MTLSize(width: maxParticles / 32, height: 1, depth: 1)
                computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()
            }
            
            // 2. Render Pass: Draw particles
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) {
                renderEncoder.setRenderPipelineState(renderPipeline)
                renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
                
                // Set MVP matrix (Mock ortho for now)
                var identity = matrix_identity_float4x4
                renderEncoder.setVertexBytes(&identity, length: MemoryLayout<float4x4>.size, index: 1)
                
                renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: maxParticles)
                renderEncoder.endEncoding()
            }
            
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    }
}
