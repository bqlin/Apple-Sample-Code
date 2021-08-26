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
struct RasterizerData
{
    float4 position [[position]];
    float2 tex_coord;
};

vertex RasterizerData
vertexShader(uint                         vertexID      [[ vertex_id ]],
             uint                         objectIndex   [[ instance_id ]],
             const device AAPLVertex *    vertices      [[ buffer(AAPLVertexBufferIndexVertices) ]],
             const device AAPLObjectPerameters* object_params [[ buffer(AAPLVertexBufferIndexObjectParams) ]],
             constant AAPLFrameState *    frame_state   [[ buffer(AAPLVertexBufferIndexFrameState) ]])
{
    RasterizerData out;

    float2 worldObjectPostion  = object_params[objectIndex].position;
    float2 modelVertexPosition = vertices[vertexID].position;
    float2 worldVertexPosition = modelVertexPosition + worldObjectPostion;
    float2 clipVertexPosition  = frame_state->aspectScale * AAPLViewScale * worldVertexPosition;

    out.position = float4(clipVertexPosition.x, clipVertexPosition.y, 0, 1);
    out.tex_coord = float2(vertices[vertexID].texcoord);

    return out;
}

fragment float4
fragmentShader(RasterizerData in [[ stage_in ]])
{
    float4 output_color = float4(in.tex_coord.x, in.tex_coord.y, 0, 1);

    return output_color;
}
