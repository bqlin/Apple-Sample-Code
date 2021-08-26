/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declarartion of the Debug Renderer
*/

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#import "TargetConditionals.h"
#import "AAPLRendererCommon.h"
#import "AAPLCamera.h"
#import "AAPLAllocator.h"

@interface AAPLDebugLine : NSObject
    @property simd::float3 to;
    @property simd::float3 from;
    @property simd::float4 color;
+(nullable instancetype)      lineFrom:(simd::float3)from
                                    to:(simd::float3)to
                                 color:(simd::float4)color;
@end

@interface AAPLDebugRenderer : NSObject

-(nullable instancetype) initWithDevice:(nonnull id<MTLDevice>) device
                                library:(nonnull id <MTLLibrary>) library
                              allocator:(nonnull AAPLAllocator*) allocator;

- (void) drawPlane:(simd::float4) planeEquation /* equation is of form xA+yB+zC+D = 0 */
           atPoint:(simd::float3) point
              size:(float) size
             color:(simd::float4) color;

- (void) drawDiscAt:(simd::float3) position
             normal:(simd::float3) normal
             radius:(float) radius
              color:(simd::float4) color;

- (void) drawLineFrom:(simd::float3)pos0
                   to: (simd::float3)pos1
                color: (simd::float4)color;

- (void) drawSphereWithCenter: (simd::float3)center
                       radius: (float)radius
                        color: (simd::float4)color;

- (void) drawBoxWithTransform:(simd::float4x4) matrix;

- (void) drawWithEncoder:(nonnull id <MTLRenderCommandEncoder>)renderEncoder
                  camera:(nonnull const AAPLCamera*)camera
          globalUniforms:(const AAPLGpuBuffer<AAPLUniforms>&)globalUniforms;

@end

