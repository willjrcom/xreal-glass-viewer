#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position;
    float2 texCoord;
};

struct PlaneUniform {
    float4x4 modelMatrix;
    float aspectRatio;
    float cornerRadius;
};

struct Uniforms {
    float4x4 viewProjection;
};

struct VertexOut {
    float4 position [[ position ]];
    float2 texCoord;
    float2 quadCoord; // Coordenada de -1 a 1 para o quad
    uint instanceID;
};

vertex VertexOut sceneVertex(uint vertexID [[ vertex_id ]],
                             constant Vertex *vertices [[ buffer(0) ]],
                             constant PlaneUniform *planes [[ buffer(1) ]],
                             constant Uniforms &uniforms [[ buffer(2) ]],
                             uint instanceID [[ instance_id ]]) {
    VertexOut out;
    float4 localPos = float4(vertices[vertexID].position, 1.0);
    float4 worldPos = planes[instanceID].modelMatrix * localPos;
    out.position = uniforms.viewProjection * worldPos;
    out.texCoord = vertices[vertexID].texCoord;
    // quadCoord mapeia de -0.5 a 0.5 (posição local do vértice / tamanho total se for 1.0)
    out.quadCoord = float2(vertices[vertexID].position.x, vertices[vertexID].position.y);
    out.instanceID = instanceID;
    return out;
}

float roundedRectSDF(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + r;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

fragment float4 sceneFragment(VertexOut in [[ stage_in ]],
                                texture2d<float> tex0 [[ texture(0) ]],
                                texture2d<float> tex1 [[ texture(1) ]],
                                texture2d<float> tex2 [[ texture(2) ]],
                                constant PlaneUniform *planes [[ buffer(1) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    float aspect = planes[in.instanceID].aspectRatio;
    float cornerRadius = planes[in.instanceID].cornerRadius;
    
    float2 size = float2(0.5 * aspect, 0.5);
    float2 p = in.quadCoord;
    p.x *= aspect;
    
    float dist = roundedRectSDF(p, size, cornerRadius);
    
    // 1. Amostragem da textura
    float4 color;
    if (in.instanceID == 0) color = tex0.sample(s, in.texCoord);
    else if (in.instanceID == 1) color = tex1.sample(s, in.texCoord);
    else color = tex2.sample(s, in.texCoord);
    
    // 2. Glassmorphism effect base
    float glassAmount = 0.1;
    float4 glassBase = float4(1.0, 1.0, 1.0, 0.1); 
    
    // 3. Inner Glow (brilho nas bordas internas)
    float innerGlow = smoothstep(-0.02, 0.0, dist);
    float4 innerGlowColor = float4(1.0, 1.0, 1.0, 0.2) * innerGlow;
    
    // 4. Borda Iluminada (Outer Glow / Bloom)
    float bloom = smoothstep(0.0, -0.01, dist) * (1.0 - smoothstep(-0.01, -0.02, dist));
    float4 bloomColor = float4(1.0, 1.0, 1.0, 0.4) * bloom;
    
    // 5. Composição Final
    float4 finalColor = color;
    finalColor.rgb += innerGlowColor.rgb * innerGlowColor.a;
    finalColor.rgb += bloomColor.rgb * bloomColor.a;
    
    // 6. Recorte suave (Anti-aliasing)
    float mask = 1.0 - smoothstep(0.0, 0.003, dist);
    
    return float4(finalColor.rgb, finalColor.a * mask);
}
