/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the terrain renderer which is responsible for rendering tesselated terrain patches.
*/

#pragma once

#import "AAPLRendererCommon.h"
#import "AAPLMainRenderer_shared.h"
#import "AAPLAllocator.h"

@interface AAPLTerrainRenderer : NSObject

@property (atomic, readonly) bool       precomputationCompleted;
@property (readonly) id <MTLBuffer>     terrainParamsBuffer;
@property (readonly) id <MTLTexture>    terrainHeight;
@property (readonly) id <MTLTexture>    terrainNormalMap;
@property (readonly) id <MTLTexture>    terrainPropertiesMap;
@property (readonly) simd::float3       terrainWorldBoundsMin;
@property (readonly) simd::float3       terrainWorldBoundsMax;

-(simd::float3) terrainWorldBoundsMax;
-(simd::float3) terrainWorldBoundsMin;


-(instancetype) initWithDevice:(id <MTLDevice>) device
                       library:(id <MTLLibrary>) library;

-(void) computeTesselationFactors:(id <MTLCommandBuffer>) commandBuffer
                   globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;

- (void)drawShadowsWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
                globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;

- (void)drawWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
         globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;

-(void) computeUpdateHeightMap:(id <MTLCommandBuffer>) commandBuffer
                globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
                   mouseBuffer:(id<MTLBuffer>) mouseBuffer;

@end
