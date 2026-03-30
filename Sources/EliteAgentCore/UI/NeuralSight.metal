#include <metal_stdlib>
using namespace metal;

struct Particle {
    float3 position;
    float4 color;
    float size;
};

// MARK: - Compute Shader
// Transforms raw activation data (MTLBuffer) into 3D particle positions/colors.
kernel void neural_compute(device float* activations [[buffer(0)]],
                          device Particle* particles [[buffer(1)]],
                          uint id [[thread_position_in_grid]]) {
    
    float activation = activations[id];
    
    // Create a 3D grid layout for activations
    float x = (id % 32) - 16.0;
    float y = ((id / 32) % 32) - 16.0;
    float z = (id / 1024.0) * 10.0;
    
    particles[id].position = float3(x, y, z + sin(activation * 6.28 + z) * 2.0);
    
    // Color intensity based on activation
    float3 baseColor = float3(0.0, 0.5, 1.0); // Elite Blue
    particles[id].color = float4(baseColor * (0.3 + activation * 0.7), 0.8);
    particles[id].size = 2.0 + activation * 4.0;
}

// MARK: - Vertex & Fragment Shaders
struct VertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex VertexOut neural_vertex(device const Particle* particles [[buffer(0)]],
                             constant float4x4& mvp [[buffer(1)]],
                             uint id [[vertex_id]]) {
    VertexOut out;
    out.position = mvp * float4(particles[id].position, 1.0);
    out.color = particles[id].color;
    out.pointSize = particles[id].size;
    return out;
}

fragment float4 neural_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
