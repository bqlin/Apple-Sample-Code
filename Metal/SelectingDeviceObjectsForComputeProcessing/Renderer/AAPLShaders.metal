/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#include "AAPLShaderTypes.h"

// Vertex shader outputs and per-fragment inputs
struct ColorInOut
{
    float4 position [[position]];
    float  pointSize [[point_size]];
    half4  color;
};

vertex ColorInOut vertexShader(uint                    vertexID  [[ vertex_id ]],
                               const device float4*    position  [[ buffer(AAPLRenderBufferIndexPositions) ]],
                               const device uchar4*    color     [[ buffer(AAPLRenderBufferIndexColors)    ]],
                               constant AAPLUniforms & uniforms  [[ buffer(AAPLRenderBufferIndexUniforms)  ]])
{
    ColorInOut out;

    // Calculate the position of the vertex in clip space and output for clipping and rasterization
    out.position = uniforms.mvpMatrix * position[vertexID];

    // Pass along the texture coordinate of the vertex for the fragment shader to use to sample from
    // the texture
    out.color = half4(color[vertexID]) / 255.0h;

    out.pointSize = half(uniforms.pointSize);

    return out;
}

fragment half4 fragmentShader(ColorInOut       inColor  [[ stage_in    ]],
                              texture2d<half>  colorMap [[ texture(AAPLTextureIndexColorMap)  ]],
                              float2           texcoord [[ point_coord ]])
{
    constexpr sampler linearSampler (mip_filter::none,
                                     mag_filter::linear,
                                     min_filter::linear);

    half4 c = colorMap.sample(linearSampler, texcoord);

    half4 fragColor = (0.6h + 0.4h * inColor.color) * c.x;

    half4 x = half4(0.1h, 0.0h, 0.0h, fragColor.w);
    half4 y = half4(1.0h, 0.7h, 0.3h, fragColor.w);
    half  a = fragColor.w;

    return fragColor * mix(x, y, a);
}
