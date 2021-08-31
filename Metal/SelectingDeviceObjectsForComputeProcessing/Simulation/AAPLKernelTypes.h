/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal kernels and C/ObjC source
*/
#ifndef AAPLKernelTypes_h
#define AAPLKernelTypes_h

#include <simd/simd.h>

typedef enum AAPLComputeBufferIndex
{
    AAPLComputeBufferIndexOldPosition = 0,
    AAPLComputeBufferIndexOldVelocity = 1,
    AAPLComputeBufferIndexNewPosition = 2,
    AAPLComputeBufferIndexNewVelocity = 3,
    AAPLComputeBufferIndexParams      = 4
} AAPLComputeBufferIndex;

typedef struct AAPLSimParams
{
    float  timestep;
    float  damping;
    float  softeningSqr;

    unsigned int numBodies;
} AAPLSimParams;

#endif // AAPLKernelTypes_h
