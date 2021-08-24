/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/
#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

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
    AAPLArgumentBufferIDExampleTextures  = 0,
    AAPLArgumentBufferIDExampleBuffers   = 100,
    AAPLArgumentBufferIDExampleConstants = 200
} AAPLArgumentBufferID;

// Constant values shared between shader and C code which indicate the size of argument arrays
//   in the structure defining the argument buffers
typedef enum AAPLNumArguments {
    AAPLNumBufferArguments  = 30,
    AAPLNumTextureArguments = 32
} AAPLNumArguments;

//  Defines the layout of each vertex in the array of vertices set as an input to our
//    Metal vertex shader.
typedef struct AAPLVertex {
    vector_float2 position;
    vector_float2 texCoord;
} AAPLVertex;

#endif /* AAPLShaderTypes_h */
