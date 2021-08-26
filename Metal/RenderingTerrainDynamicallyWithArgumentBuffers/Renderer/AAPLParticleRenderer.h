/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the AAPLParticleRenderer which is responsible for rendering particles.
 rendering operations.
*/

#pragma once

#import <array>

#import "AAPLAllocator.h"
#import "AAPLMainRenderer_shared.h"
#import "AAPLTerrainRenderer_shared.h"
#import "AAPLTerrainRenderer.h"

@interface AAPLParticleRenderer : NSObject

+(std::array <const TerrainHabitat::ParticleProperties*, 4>) GetParticleProperties;

#if TARGET_OS_OSX

-(id) initWithDevice: (id <MTLDevice>)  device
             library: (id <MTLLibrary>) library;

-(void) spawnParticleWithCommandBuffer: (id <MTLCommandBuffer>) commandBuffer
                              uniforms: (AAPLGpuBuffer<AAPLUniforms>) uniforms
                               terrain: (AAPLTerrainRenderer*) terrain
                           mouseBuffer: (id <MTLBuffer>) mouseBuffer
                          numParticles: (NSUInteger) numParticles;

-(void) drawWithEncoder: (id <MTLRenderCommandEncoder>) renderEncoder
               uniforms: (AAPLGpuBuffer <AAPLUniforms>) uniforms
              depthDraw: (bool) depthDraw;

#endif

@end
