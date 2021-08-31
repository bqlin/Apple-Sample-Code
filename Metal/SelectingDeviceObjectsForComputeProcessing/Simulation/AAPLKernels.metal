/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal kernel used for the simulation
*/

#include <metal_stdlib>

using namespace metal;

#import "AAPLKernelTypes.h"

static float3 computeAcceleration(const float4 vsPosition,
                                  const float4 oldPosition,
                                  const float  softeningSqr)
{
    float3 r = vsPosition.xyz - oldPosition.xyz;

    float distSqr = distance_squared(vsPosition.xyz, oldPosition.xyz);

    distSqr += softeningSqr;

    float invDist  = rsqrt(distSqr);
    float invDist3 = invDist * invDist * invDist;

    float s = vsPosition.w * invDist3;

    return r * s;
}

kernel void NBodySimulation(device float4*           newPosition       [[ buffer(AAPLComputeBufferIndexNewPosition) ]],
                            device float4*           newVelocity       [[ buffer(AAPLComputeBufferIndexNewVelocity) ]],
                            device float4*           oldPosition       [[ buffer(AAPLComputeBufferIndexOldPosition) ]],
                            device float4*           oldVelocity       [[ buffer(AAPLComputeBufferIndexOldVelocity) ]],
                            constant AAPLSimParams & params            [[ buffer(AAPLComputeBufferIndexParams)      ]],
                            threadgroup float4     * sharedPosition    [[ threadgroup(0)                            ]],
                            const uint               threadInGrid      [[ thread_position_in_grid                   ]],
                            const uint               threadInGroup     [[ thread_position_in_threadgroup            ]],
                            const uint               numThreadsInGroup [[ threads_per_threadgroup                   ]])
{

    float4 currentPosition = oldPosition[threadInGrid];
    float3 acceleration = 0.0f;

    const float softeningSqr = params.softeningSqr;

    uint sourcePosition = threadInGroup;

    // For each particle / body
    for(uint i = 0; i < params.numBodies ; i += numThreadsInGroup)
    {
        sharedPosition[threadInGroup] = oldPosition[sourcePosition];

        threadgroup_barrier(metal::mem_flags::mem_threadgroup);

        for(uint j = 0; j < numThreadsInGroup; j++)
        {
            acceleration += computeAcceleration(sharedPosition[j], currentPosition, softeningSqr);
        }

        threadgroup_barrier(metal::mem_flags::mem_threadgroup);

        sourcePosition += numThreadsInGroup;
    }


    float4 currentVelocity = oldVelocity[threadInGrid];

    currentVelocity.xyz += acceleration * params.timestep;
    currentVelocity.xyz *= params.damping;
    currentPosition.xyz += currentVelocity.xyz * params.timestep;

    newPosition[threadInGrid] = currentPosition;
    newVelocity[threadInGrid] = currentVelocity;
} // NBodyIntegrateSystem
