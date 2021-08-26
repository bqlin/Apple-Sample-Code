/*
See LICENSE folder for this sample’s licensing information.

Abstract:
General Uniforms structs that are shared between Metal / Objective-C.
*/

#pragma once

#import <simd/simd.h>

#define NUM_CASCADES (3)

#define GAME_TIME 1.1f

// Matrices that are stored and generated internally within the camera object
struct AAPLCameraUniforms
{
    simd::float4x4      viewMatrix;
    simd::float4x4      projectionMatrix;
    simd::float4x4      viewProjectionMatrix;
    simd::float4x4      invOrientationProjectionMatrix;
    simd::float4x4      invViewProjectionMatrix;
    simd::float4x4      invProjectionMatrix;
    simd::float4x4      invViewMatrix;
    simd::float4        frustumPlanes[6];

};

struct AAPLUniforms
{
    AAPLCameraUniforms  cameraUniforms;
    AAPLCameraUniforms  shadowCameraUniforms[3];
    
    // Mouse state: x,y = position in pixels; z = buttons
    simd::float3        mouseState;
    simd::float2        invScreenSize;
    float               projectionYScale;
    float               brushSize;

    float               ambientOcclusionContrast;
    float               ambientOcclusionScale;
    float               ambientLightScale;
#if !USE_CONST_GAME_TIME
    float               gameTime;
#endif
    float               frameTime;  // TODO. this doesn't appear to be initialized until UpdateCpuUniforms. OK?
};

struct AAPLDebugVertex
{
    simd::float4        position;
    simd::float4        color;
};

// Describes our standardized OBJ format geometry vertex format
struct AAPLObjVertex
{
    simd::float3        position;
    simd::float3        normal;
    simd::float3        color;
#ifndef __METAL_VERSION__
    bool operator == (const AAPLObjVertex& o) const
    {
        return simd::all (o.position == position) &&
               simd::all (o.normal == normal) &&
               simd::all (o.color == color);
    }
#endif
};
