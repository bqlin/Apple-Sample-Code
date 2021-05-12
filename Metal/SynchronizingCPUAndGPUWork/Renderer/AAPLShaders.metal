/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal vertex and fragment shaders.
*/

#include <metal_stdlib>

using namespace metal;

// Include header shared between this Metal shader code and the C code executing Metal API commands.
#include "AAPLShaderTypes.h"

// Vertex shader outputs and fragment shader inputs.
struct RasterizerData
{
    // The [[position]] attribute qualifier of this member indicates this value is the clip space
    // position of the vertex when this structure is returned from the vertex shader.
    float4 position [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer interpolates
    // its value with values of other vertices making up the triangle and passes the interpolated
    // value to the fragment shader for each fragment in that triangle.
    float4 color;

};

// Vertex shader.
vertex RasterizerData
vertexShader(const uint vertexID [[ vertex_id ]],
             const device AAPLVertex *vertices [[ buffer(AAPLVertexInputIndexVertices) ]],
             constant vector_uint2 *viewportSizePointer  [[ buffer(AAPLVertexInputIndexViewportSize) ]])
{
    RasterizerData out;

    // Index into the array of positions to get the current vertex.
    // Positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from the origin).
    float2 pixelSpacePosition = vertices[vertexID].position.xy;

    // Get the viewport size and cast to float.
    vector_float2 viewportSize = vector_float2(*viewportSizePointer);

    // To convert from positions in pixel space to positions in clip-space,
    // divide the pixel coordinates by half the size of the viewport.
    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = pixelSpacePosition / (viewportSize / 2.0);

    // Pass the input color straight to the output color.
    out.color = vertices[vertexID].color;

    return out;
}

// Fragment shader.
fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    // Return the color you just set in the vertex shader.
    return in.color;
}

