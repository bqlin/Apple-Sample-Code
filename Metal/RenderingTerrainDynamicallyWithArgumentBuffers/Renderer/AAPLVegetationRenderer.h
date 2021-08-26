/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the vegetation renderer which is responsible for the terrain-specific foliage geometry.
*/

#import <Foundation/Foundation.h>
#import "AAPLAllocator.h"
#import "AAPLObjLoader.h"
#import <Metal/Metal.h>
#import <simd/simd.h>

@class AAPLTerrainRenderer;


// AAPLVegetationPopulation defines a single 'type' of vegetation asset: a single mesh type that has multiple instances throughout the scene
// There is one population of each of the loaded vegetation geometry

@interface AAPLVegetationPopulation : NSObject
@property (readonly) const AAPLObjMesh* mesh;                   /// The mesh that represents the population
@property (readonly) NSUInteger         indexCount;             /// amount of indices within the geometry
@property (readonly) NSUInteger         vertexCount;            /// amount of vertices within the geometry

-(instancetype) initWithObjMesh:(const AAPLObjMesh*) mesh;
-(NSUInteger) indexCount;
-(NSUInteger) vertexCount;
@end

// The AAPLVegetationRenderer takes care of instancing and rendering the vegetation geometry
// All instantiation and culling is done on the GPU, so the CPU side only needs to load the
//  geometry and allocate the instance buffers and indirect argument buffers
@interface AAPLVegetationRenderer : NSObject

-(instancetype) initWithDevice:(id<MTLDevice>)device
                       library:(id <MTLLibrary>) library;

-(void)spawnVegetationWithCommandbuffer: (id <MTLCommandBuffer>) commandBuffer
                               uniforms: (AAPLGpuBuffer <AAPLUniforms>) uniforms
                                terrain: (AAPLTerrainRenderer*) terrain;

-(void)drawVegetationWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
                  globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;

-(void)drawShadowsWithEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
               globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms
                 cascadeIndex:(uint) index;

@end






