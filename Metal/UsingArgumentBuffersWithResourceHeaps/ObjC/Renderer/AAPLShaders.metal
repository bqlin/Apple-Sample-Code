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

    return out;
}

struct FragmentShaderArguments {
    array<texture2d<float>, AAPLNumTextureArguments> exampleTextures  [[ id(AAPLArgumentBufferIDExampleTextures)  ]];
    array<device float *,  AAPLNumBufferArguments>   exampleBuffers   [[ id(AAPLArgumentBufferIDExampleBuffers)   ]];
    array<uint32_t, AAPLNumBufferArguments>          exampleConstants [[ id(AAPLArgumentBufferIDExampleConstants) ]];
};

fragment float4
fragmentShader(       RasterizerData            in                 [[ stage_in ]],
               device FragmentShaderArguments & fragmentShaderArgs [[ buffer(AAPLFragmentBufferIndexArguments) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    float4 color = float4(0, 0, 0, 1);

    // If on the right side of the quad...
    if(in.texCoord.x < 0.5)
    {
        //...use accumulated values from each of the 32 textures

        for(uint32_t textureToSample = 0; textureToSample < AAPLNumTextureArguments; textureToSample++)
        {
            float4 textureValue = fragmentShaderArgs.exampleTextures[textureToSample].sample(textureSampler, in.texCoord);

            color += textureValue;
        }
    }
    else // if on left side of the quad...
    {
        //...use values from a buffer

        // Use texCoord.x to select the buffer to read from
        uint32_t bufferToRead = (in.texCoord.x-0.5)*2.0 * (AAPLNumBufferArguments-1);

        // Retrieve the number of elements for the selected buffer from
        // the array of constants in the argument buffer
        uint32_t numElements = fragmentShaderArgs.exampleConstants[bufferToRead];

        // Determine the index used to read from the buffer
        uint32_t indexToRead = in.texCoord.y * numElements;

        // Retrieve the buffer to read from by accessing the array of
        // buffers in the argument buffer
        device float* buffer = fragmentShaderArgs.exampleBuffers[bufferToRead];

        // Read from the buffer and assign the value to the output color
        color = buffer[indexToRead];
    }

    return color;
}
