/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Particle Renderer's uniforms that are shared between Metal / Objective-C.
*/

#pragma once

#import <simd/simd.h>

#ifdef __METAL_VERSION__
#import <metal_stdlib>
using namespace metal;
#endif

#define MAX_PARTICLES (int)(4096*4)
#define PARTICLES_PER_THREADGROUP 128

struct ParticleInstanceBufferDescription
{
#ifdef __METAL_VERSION__
    atomic_int numParticlesAlive;
    atomic_int firstParticleOffset;
#else
    int32_t numParticlesAlive;
    int32_t firstParticleOffset;
#endif
    int32_t particlesBufferSize;
};

struct ParticleSpawnParams
{
    int32_t         numParticles;
    simd::float2    invHeightMapSize;
    simd::float2    kernelOffset;
    float           cosAlpha;
    float           sinAlpha;
    float           radiusScale;
};

