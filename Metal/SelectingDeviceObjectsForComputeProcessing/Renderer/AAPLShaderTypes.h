/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/
#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

#include <simd/simd.h>

typedef enum AAPLRenderBufferIndex
{
    AAPLRenderBufferIndexPositions = 0,
    AAPLRenderBufferIndexColors   = 1,
    AAPLRenderBufferIndexUniforms = 2,
} AAPLRenderBufferIndex;

typedef enum AAPLTextureIndex
{
    AAPLTextureIndexColorMap = 0,
} AAPLTextureIndex;

typedef struct
{
    matrix_float4x4 mvpMatrix;
    float pointSize;
} AAPLUniforms;

#endif // AAPLShaderTypes_h
