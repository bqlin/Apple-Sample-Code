/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "AAPLShaderTypes.h"

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

vertex ColorInOut vertexShader(              uint           vertexID [[ vertex_id ]],
                               const device  AAPLVertex   * in       [[ buffer(AAPLBufferIndexVertices) ]],
                               constant      AAPLUniforms & uniforms [[ buffer(AAPLBufferIndexUniforms) ]])
{
    ColorInOut out;

    out.position = uniforms.mvp * in[vertexID].position;

    out.texCoord = in[vertexID].texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut      in       [[stage_in]],
                               texture2d<half> baseMap [[ texture(AAPLTextureIndexBaseMap) ]],
                               texture2d<half> labelMap [[ texture(AAPLTextureIndexLabelMap) ]])
{
    constexpr sampler linearSampler (mip_filter::nearest,
                                     mag_filter::linear,
                                     min_filter::linear);

    const half4 baseColor = baseMap.sample (linearSampler, in.texCoord.xy);
    const half4 labelColor = labelMap.sample (linearSampler, in.texCoord.xy);

    const half4 outputColor = (baseColor * (1.0 - labelColor.w)) + (labelColor * labelColor.w);
    return float4(outputColor);
}

