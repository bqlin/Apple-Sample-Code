/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Shaders used by the Debug renderer: simple colored primitives.
*/

#import <metal_stdlib>
#import "AAPLMainRenderer_shared.h"
using namespace metal;

typedef struct
{
    float4 position [[position]];
    float4 color;
    
} DebugColorInOut;

vertex DebugColorInOut debugVertexShader(const device const AAPLDebugVertex* in [[ buffer(0) ]],
                                         constant AAPLUniforms & uniforms [[ buffer(1) ]],
                                         uint vid [[vertex_id]])

{
    DebugColorInOut out;
    
    float4 position = float4(in[vid].position);
    out.position = uniforms.cameraUniforms.viewProjectionMatrix * position;
    out.color = float4(in[vid].color);
    
    return out;
}

fragment float4 debugFragmentShader(DebugColorInOut in [[stage_in]],
                                    constant AAPLUniforms & uniforms [[ buffer(0) ]])
{
    return float4(in.color);
}
