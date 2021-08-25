/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/
#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

#include <simd/simd.h>

// Constants shared between shader and C code
#define AAPLQuadSize     0.3
#define AAPLQuadSpacing  0.31
#define AAPLGridWidth    11
#define AAPLNumInstances 66
#define AAPLNumTextures  67
#define AAPLGridHeight   ((AAPLNumInstances+1)/AAPLGridWidth)

// Buffer index values shared between shader and C code
typedef enum AAPLVertexBufferIndex
{
    AAPLVertexBufferIndexVertices,
    AAPLVertexBufferIndexInstanceParams,
    AAPLVertexBufferIndexFrameState
} AAPLVertexBufferIndex;

// Buffer index values shared between shader and C code
typedef enum AAPLFragmentBufferIndex
{
    AAPLFragmentBufferIndexInstanceParams,
    AAPLFragmentBufferIndexFrameState
} AAPLFragmentBufferIndex;

typedef enum AAPLComputeBufferIndex {
    AAPLComputeBufferIndexSourceTextures,
    AAPLComputeBufferIndexInstanceParams,
    AAPLComputeBufferIndexFrameState
} AAPLComputeBufferIndex;

// Argument buffer indices shared between shader and C code
typedef enum AAPLArgumentBufferID
{
    AAPLArgumentBufferIDTexture = 0
} AAPLArgumentBufferID;

// Structure defining the layout of each vertex in the array of vertices set as an input to
//  our Metal vertex shader
typedef struct AAPLVertex
{
    vector_float2 position;
    vector_float2 texCoord;
} AAPLVertex;

// Structure defining the layout of variable changing once (or less) per frame
typedef struct AAPLFrameState
{
    uint          textureIndexOffset;
    float         slideFactor;
    vector_float2 offset;
    vector_float2 quadScale;
} AAPLFrameState;

#endif /* AAPLShaderTypes_h */
