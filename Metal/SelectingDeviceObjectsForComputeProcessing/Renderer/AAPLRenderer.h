/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for renderer class which performs Metal setup and per frame rendering
*/

@import MetalKit;

// Platform independent renderer class
@interface AAPLRenderer : NSObject

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;

- (void)drawableSizeWillChange:(CGSize)size;

- (void)providePositionData:(nonnull NSData *)data;

- (void)drawWithCommandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer
              positionsBuffer:(nonnull id<MTLBuffer>)positionsBuffer
                    numBodies:(NSUInteger)numBodies
                       inView:(nonnull MTKView *)view;

- (void)drawProvidedPositionDataWithNumBodies:(NSUInteger)numParticles
                                       inView:(nonnull MTKView *)view;

- (void)setRenderScale:(float)renderScale withDrawableSize:(CGSize)size;

@property (nonatomic, readonly, nonnull) id<MTLDevice> device;

@end
