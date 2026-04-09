#include <metal_stdlib>
using namespace metal;

struct PointIn {
    float3 position [[attribute(0)]];
    uchar4 color    [[attribute(1)]];
};

struct PointOut {
    float4 clipPosition [[position]];
    float4 color;
    float  pointSize [[point_size]];
};

struct Uniforms {
    float4x4 viewProjection;
    float    pointSize;
};

vertex PointOut pointVertex(
    PointIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    PointOut out;
    out.clipPosition = uniforms.viewProjection * float4(in.position, 1.0);
    out.color = float4(in.color) / 255.0;
    out.pointSize = uniforms.pointSize;
    return out;
}

fragment float4 pointFragment(PointOut in [[stage_in]]) {
    return in.color;
}
