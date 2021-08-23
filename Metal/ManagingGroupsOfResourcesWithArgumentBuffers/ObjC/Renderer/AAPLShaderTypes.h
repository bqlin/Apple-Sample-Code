/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum AAPLVertexBufferIndex
{
    AAPLVertexBufferIndexVertices = 0,
} AAPLVertexBufferIndex;

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum AAPLFragmentBufferIndex
{
    AAPLFragmentBufferIndexArguments = 0,
} AAPLFragmentBufferIndex;

// Argument buffer indices shared between shader and C code to ensure Metal shader buffer
//   input match Metal API texture set calls
typedef enum AAPLArgumentBufferID
{
    AAPLArgumentBufferIDExampleTexture,
    AAPLArgumentBufferIDExampleSampler,
    AAPLArgumentBufferIDExampleBuffer,
    AAPLArgumentBufferIDExampleConstant
} AAPLArgumentBufferID;

//  Defines the layout of each vertex in the array of vertices set as an input to our
//    Metal vertex shader.
typedef struct AAPLVertex {
    vector_float2 position;
    vector_float2 texCoord;
    vector_float4 color;
} AAPLVertex;

#endif /* ShaderTypes_h */
