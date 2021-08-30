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
typedef enum AAPLBufferIndex
{
    AAPLBufferIndexMeshPositions = 0,
    AAPLBufferIndexMeshGenerics  = 1,
    AAPLBufferIndexUniforms      = 2
} AAPLBufferIndex;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
typedef enum AAPLVertexAttribute
{
    AAPLVertexAttributePosition  = 0,
    AAPLVertexAttributeTexcoord  = 1,
    AAPLVertexAttributeNormal    = 2,
    AAPLVertexAttributeTangent   = 3,
    AAPLVertexAttributeBitangent = 4
} AAPLVertexAttribute;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
typedef enum AAPLTextureIndex
{
    AAPLTextureIndexBaseColor = 0,
    AAPLTextureIndexSpecular  = 1,
    AAPLTextureIndexNormal    = 2,
    kNumTextureIndices
} AAPLTextureIndex;

// Structure shared between shader and C code to ensure the layout of uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
typedef struct
{
    // Per Frame Uniforms
    vector_float3 cameraPos;

    // Per Mesh Uniforms
    float materialShininess;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
    matrix_float3x3 normalMatrix;

    // Per Light Properties
    vector_float3 ambientLightColor;
    vector_float3 directionalLightInvDirection;
    vector_float3 directionalLightColor;

} AAPLUniforms;

#endif /* ShaderTypes_h */
