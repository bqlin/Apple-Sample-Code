/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and C/ObjC source
*/
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/////////////////////////////////////////////////////////
#pragma mark - Constants shared between shader and C code
/////////////////////////////////////////////////////////

// Number of unique meshes/objects in the scene
#define AAPLNumObjects    65536

// The number of objects in a row
#define AAPLGridWidth     256

// The number of object in a column
#define AAPLGridHeight    ((AAPLNumObjects+AAPLGridWidth-1)/AAPLGridWidth)

// Scale of each object when drawn
#define AAPLViewScale    0.25

// Because the objects are centered at origin, the scale appliced
#define AAPLObjectSize    2.0

// Distance between each object
#define AAPLObjecDistance 2.1


/////////////////////////////////////////////////////
#pragma mark - Types shared between shader and C code
/////////////////////////////////////////////////////

// Structure defining the layout of each vertex.  Shared between C code filling in the vertex data
// and Metal vertex shader consuming the vertices
typedef struct
{
    packed_float2 position;
    packed_float2 texcoord;
} AAPLVertex;

// Structure defining the layout of variable changing once (or less) per frame
typedef struct AAPLFrameState
{
    vector_float2 translation;
    vector_float2 aspectScale;
} AAPLFrameState;

// Structure defining parameters for each rendered object
typedef struct AAPLObjectPerameters
{
    packed_float2 position;
    float boundingRadius;
    uint32_t numVertices;
    uint32_t startVertex;
} AAPLObjectPerameters;

// Buffer index values shared between the vertex shader and C code
typedef enum AAPLVertexBufferIndex
{
    AAPLVertexBufferIndexVertices,
    AAPLVertexBufferIndexObjectParams,
    AAPLVertexBufferIndexFrameState
} AAPLVertexBufferIndex;

// Buffer index values shared between the compute kernel and C code
typedef enum AAPLKernelBufferIndex
{
    AAPLKernelBufferIndexFrameState,
    AAPLKernelBufferIndexObjectParams,
    AAPLKernelBufferIndexVertices,
    AAPLKernelBufferIndexCommandBufferContainer
} AAPLKernelBufferIndex;

// Argument buffer ID for the ICB encoded by the compute kernel
typedef enum AAPLArgumentBufferBufferID
{
    AAPLArgumentBufferIDCommandBuffer,
} AAPLArgumentBufferBufferID;

#endif /* ShaderTypes_h */
