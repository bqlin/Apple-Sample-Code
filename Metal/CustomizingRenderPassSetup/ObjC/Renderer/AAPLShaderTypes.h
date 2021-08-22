/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders
 and Objective-C source.
*/

#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

#include <simd/simd.h>

typedef enum AAPLVertexInputIndex
{
    AAPLVertexInputIndexVertices    = 0,
    AAPLVertexInputIndexAspectRatio = 1,
} AAPLVertexInputIndex;

typedef enum AAPLTextureInputIndex
{
    AAPLTextureInputIndexColor = 0,
} AAPLTextureInputIndex;

typedef struct
{
    vector_float2 position;
    vector_float4 color;
} AAPLSimpleVertex;

typedef struct
{
    vector_float2 position;
    vector_float2 texcoord;
} AAPLTextureVertex;

#endif /* AAPLShaderTypes_h */
