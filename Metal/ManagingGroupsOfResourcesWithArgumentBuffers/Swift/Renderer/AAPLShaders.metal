/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#include "AAPLShaderTypes.h"

// Vertex shader outputs and per-fragment inputs.
struct RasterizerData
{
    float4 position [[position]];
    float2 texCoord;
    half4  color;
};

vertex RasterizerData
vertexShader(             uint        vertexID [[ vertex_id ]],
             const device AAPLVertex *vertices [[ buffer(AAPLVertexBufferIndexVertices) ]])
{
    RasterizerData out;

    float2 position = vertices[vertexID].position;

    out.position.xy = position;
    out.position.z  = 0.0;
    out.position.w  = 1.0;

    out.texCoord = vertices[vertexID].texCoord;
    out.color    = (half4) vertices[vertexID].color;

    return out;
}

struct FragmentShaderArguments {
    texture2d<half> exampleTexture  [[ id(AAPLArgumentBufferIDExampleTexture)  ]];
    sampler         exampleSampler  [[ id(AAPLArgumentBufferIDExampleSampler)  ]];
    device float   *exampleBuffer   [[ id(AAPLArgumentBufferIDExampleBuffer)   ]];
    uint32_t        exampleConstant [[ id(AAPLArgumentBufferIDExampleConstant) ]];
};

fragment float4
fragmentShader(       RasterizerData            in                 [[ stage_in ]],
               device FragmentShaderArguments & fragmentShaderArgs [[ buffer(AAPLFragmentBufferIndexArguments) ]])
{
    // Get the sampler encoded in the argument buffer
    sampler exampleSampler = fragmentShaderArgs.exampleSampler;

    // Sample the texture encoded in the argument buffer
    half4 textureSample = fragmentShaderArgs.exampleTexture.sample(exampleSampler, in.texCoord);

    // Use the fragment position and the constant encoded in the argument buffer to calculate an array index
    uint32_t index = (uint32_t)in.position.x % fragmentShaderArgs.exampleConstant;

    // Index into the buffer encoded in the argument buffer
    float colorScale = fragmentShaderArgs.exampleBuffer[index];

    // Add sample and color values together and return the result
    return float4((1.0-textureSample.w) * colorScale * in.color + textureSample);
}
