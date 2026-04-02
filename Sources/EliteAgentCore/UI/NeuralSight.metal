#include <metal_stdlib>
using namespace metal;

struct Particle {
    float3 position;
    float4 color;
    float size;
};

struct KernelUniforms {
    int state;      // 0: Idle, 1: Pulse, 2: Gathering, 3: Glow, 4: Verifying, 5: Ready, -1: Glitch
    float progress;
    float time;
};

// MARK: - Compute Shader
kernel void neural_compute(device float* activations [[buffer(0)]],
                          device Particle* particles [[buffer(1)]],
                          constant KernelUniforms& uniforms [[buffer(2)]],
                          uint id [[thread_position_in_grid]]) {
    
    float activation = activations[id];
    float t = uniforms.time;
    float p = uniforms.progress;
    
    // Base grid layout
    float x_grid = (id % 32) - 16.0;
    float y_grid = ((id / 32) % 32) - 16.0;
    float z_grid = (id / 1024.0) * 10.0;
    
    float3 targetPos;
    float3 baseColor = float3(0.0, 0.5, 1.0); // Elite Blue
    float intensity = 0.3 + activation * 0.7;
    float size = 2.0 + activation * 4.0;
    
    if (uniforms.state == 1) { // PULSE (Reading Weights)
        float pulse = (sin(t * 2.0) + 1.0) * 0.5;
        targetPos = float3(x_grid, y_grid, z_grid + pulse * 2.0);
        intensity = pulse * 0.5;
    } else if (uniforms.state == 2) { // GATHERING (Decoding)
        float3 center = float3(0, 0, 0);
        targetPos = mix(float3(x_grid, y_grid, z_grid), center, p * 0.8);
        intensity = 0.5 + p * 0.5;
    } else if (uniforms.state == 3) { // GLOW (Transferring)
        targetPos = float3(x_grid, y_grid, z_grid);
        intensity = 1.0 + sin(t * 10.0) * 0.2;
        size *= 1.5;
        baseColor = float3(0.0, 0.8, 1.0); // Cyan glow
    } else {
        targetPos = float3(x_grid, y_grid, z_grid + sin(activation * 6.28 + z_grid) * 2.0);
    }
    
    particles[id].position = targetPos;
    particles[id].color = float4(baseColor * intensity, 0.8);
    particles[id].size = size;
}

// MARK: - Vertex & Fragment Shaders
struct VertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex VertexOut neural_vertex(device const Particle* particles [[buffer(0)]],
                             constant float4x4& mvp [[buffer(1)]],
                             constant KernelUniforms& uniforms [[buffer(2)]],
                             uint id [[vertex_id]]) {
    VertexOut out;
    float3 pos = particles[id].position;
    
    // VERTEX-LEVEL GLITCH (Zero-cost jitter for error feedback)
    if (uniforms.state == -1) {
        float noise = fract(sin(dot(float2(id, uniforms.time), float2(12.9898, 78.233))) * 43758.5453);
        pos.x += (noise - 0.5) * 2.0;
        pos.y += (noise - 0.5) * 2.0;
    }
    
    out.position = mvp * float4(pos, 1.0);
    out.color = (uniforms.state == -1) ? float4(1.0, 0.0, 0.0, 1.0) : particles[id].color;
    out.pointSize = particles[id].size;
    return out;
}

fragment float4 neural_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
