/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal vertex and fragment shaders.
*/

#include <metal_stdlib>

using namespace metal;

#include "AAPLShaderTypes.h"

#pragma mark -

#pragma mark - Shaders for simple pipeline used to render triangle to renderable texture

// Vertex shader outputs and fragment shader inputs for simple pipeline
struct SimplePipelineRasterizerData
{
    float4 position [[position]];
    float4 color;
};

// Vertex shader which passes position and color through to rasterizer.
vertex SimplePipelineRasterizerData
simpleVertexShader(const uint vertexID [[ vertex_id ]],
                   const device AAPLSimpleVertex *vertices [[ buffer(AAPLVertexInputIndexVertices) ]])
{
    SimplePipelineRasterizerData out;

    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = vertices[vertexID].position.xy;

    out.color = vertices[vertexID].color;

    return out;
}

// Fragment shader that just outputs color passed from rasterizer.
fragment float4 simpleFragmentShader(SimplePipelineRasterizerData in [[stage_in]])
{
    return in.color;
}

#pragma mark -

#pragma mark Shaders for pipeline used texture from renderable texture when rendering to the drawable.

// Vertex shader outputs and fragment shader inputs for texturing pipeline.
struct TexturePipelineRasterizerData
{
    float4 position [[position]];
    float2 texcoord;
};

// Vertex shader which adjusts positions by an aspect ratio and passes texture
// coordinates through to the rasterizer.
vertex TexturePipelineRasterizerData
textureVertexShader(const uint vertexID [[ vertex_id ]],
                    const device AAPLTextureVertex *vertices [[ buffer(AAPLVertexInputIndexVertices) ]],
                    constant float &aspectRatio [[ buffer(AAPLVertexInputIndexAspectRatio) ]])
{
    TexturePipelineRasterizerData out;

    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);

    out.position.x = vertices[vertexID].position.x * aspectRatio;
    out.position.y = vertices[vertexID].position.y;

    out.texcoord = vertices[vertexID].texcoord;

    return out;
}
// Fragment shader that samples a texture and outputs the sampled color.
fragment float4 textureFragmentShader(TexturePipelineRasterizerData in      [[stage_in]],
                                      texture2d<float>              texture [[texture(AAPLTextureInputIndexColor)]])
{
    sampler simpleSampler;

    // Sample data from the texture.
    float4 colorSample = texture.sample(simpleSampler, in.texcoord);

    // Return the color sample as the final color.
    return colorSample;
}
