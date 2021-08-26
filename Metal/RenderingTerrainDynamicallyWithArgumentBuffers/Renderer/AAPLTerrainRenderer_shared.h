/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Terrain-specific Uniforms structs that are shared between Metal / Objective-C.
*/

#pragma once

#import <simd/simd.h>

// Macro to affix the argument buffer index onto the property name if we're running on the GPU
#ifdef __METAL_VERSION__
    #define IAB_INDEX(x) [[id(x)]]
#else
    #define IAB_INDEX(x)
#endif

enum TerrainHabitatType : uint8_t
{
    TerrainHabitatTypeSand,
    TerrainHabitatTypeGrass,
    TerrainHabitatTypeRock,
    TerrainHabitatTypeSnow,
    
    // The number of variations of each type, for added realism
    TerrainHabitatTypeCOUNT
};

#define VARIATION_COUNT_PER_HABITAT 4

enum class TerrainHabitat_MemberIds : uint32_t
{
    slopeStrength = 0,
    slopeThreshold,
    elevationStrength,
    elevationThreshold,
    specularPower,
    textureScale,
    flipNormal,
    
    // The "particle_" properties must match TerrainHabitat::ParticleProperties fields
    particle_keyTimePoints,
    particle_scaleFactors,
    particle_alphaFactors,
    particle_gravity,
    particle_lightingCoefficients,
    particle_doesCollide,
    particle_doesRotate,
    particle_castShadows,
    particle_distanceDependent,
    diffSpecTextureArray,
    normalTextureArray,
    COUNT,
};

// The argument buffer that defines materials and particle properties
struct TerrainHabitat
{
#ifndef __METAL_VERSION__
    // This struct should not be instantiated in C++ because it contains textures that aren't visible on the CPU
private:
    TerrainHabitat ();
public:
#endif

    float slopeStrength      IAB_INDEX(TerrainHabitat_MemberIds::slopeStrength);
    float slopeThreshold     IAB_INDEX(TerrainHabitat_MemberIds::slopeThreshold);
    float elevationStrength  IAB_INDEX(TerrainHabitat_MemberIds::elevationStrength);
    float elevationThreshold IAB_INDEX(TerrainHabitat_MemberIds::elevationThreshold);
    float specularPower      IAB_INDEX(TerrainHabitat_MemberIds::specularPower);
    float textureScale       IAB_INDEX(TerrainHabitat_MemberIds::textureScale);
    bool  flipNormal         IAB_INDEX(TerrainHabitat_MemberIds::flipNormal);
    
    struct ParticleProperties
    {
        // The fields of this struct must be reflected in TerrainHabitat_MemberIds
        simd::float4    keyTimePoints;
        simd::float4    scaleFactors;
        simd::float4    alphaFactors;
        simd::float4    gravity;
        simd::float4    lightingCoefficients;
        int             doesCollide;
        int             doesRotate;
        int             castShadows;
        int             distanceDependent;
    } particleProperties;
    
#ifdef __METAL_VERSION__
    texture2d_array <float,access::sample> diffSpecTextureArray IAB_INDEX(TerrainHabitat_MemberIds::diffSpecTextureArray);
    texture2d_array <float,access::sample> normalTextureArray   IAB_INDEX(TerrainHabitat_MemberIds::normalTextureArray);
#endif
};

enum class TerrainParams_MemberIds : uint32_t
{
    ambientOcclusionScale = int(TerrainHabitat_MemberIds::COUNT) * TerrainHabitatTypeCOUNT + 1,
    ambientOcclusionContrast,
    ambientLightScale,
    atmosphereScale,
    COUNT
};

// Each habitat type has a few slightly different variations for added realism
struct TerrainParams
{
    TerrainHabitat habitats [TerrainHabitatTypeCOUNT];
    float ambientOcclusionScale    IAB_INDEX(TerrainParams_MemberIds::ambientOcclusionScale);
    float ambientOcclusionContrast IAB_INDEX(TerrainParams_MemberIds::ambientOcclusionContrast);
    float ambientLightScale        IAB_INDEX(TerrainParams_MemberIds::ambientLightScale);
    float atmosphereScale          IAB_INDEX(TerrainParams_MemberIds::atmosphereScale);
};

#define TERRAIN_PATCHES 32
#define TERRAIN_SCALE   15000.0f
#define TERRAIN_HEIGHT  4500.0f
#define TERRAIN_WATER_LEVEL 50.0

struct TerrainAdjustParams
{
    simd::float4x4  inverseViewProjectionMatrix;
    simd::float4x4  viewProjectionMatrix;
    simd::float3    cameraPosition;
    simd::float2    invScreenSize;
    simd::float2    invHeightmapSize;
    float           power;
    float           radiusScale;
    float           brushHighlight;
    uint32_t        component;
    bool            useTargetMap;
};
