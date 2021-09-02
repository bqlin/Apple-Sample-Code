/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/

#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between the Metal shader and C code ensure the shader buffer
// inputs match the Metal API buffer set calls.
typedef enum AAPLVertexInputIndex
{
    AAPLVertexInputIndexVertices     = 0,
    AAPLVertexInputIndexViewportSize = 1,
} AAPLVertexInputIndex;

// Texture index values shared between the Metal shader and C code ensure the shader buffer
// inputs match the Metal API texture set calls.
typedef enum AAPLTextureIndex
{
    AAPLTextureIndexInput  = 0,
    AAPLTextureIndexOutput = 1,
} AAPLTextureIndex;

// This structure defines the layout of each vertex in the array of vertices set as an
// input to our Metal vertex shader. Since this header is shared between the Metal shader
// and C code, the layout of the vertex array in the code matches the layout that the
// vertex shader expects.
typedef struct
{
    // The position for the vertex, in pixel space; a value of 100 indicates 100 pixels
    // from the origin/center.
    vector_float2 position;

    // The 2D texture coordinate for this vertex.
    vector_float2 textureCoordinate;
} AAPLVertex;

#endif /* AAPLShaderTypes_h */
