/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for renderer class which performs Metal setup and per frame rendering
*/

@import MetalKit;

@interface AAPLRenderer : NSObject

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
                                      device:(nonnull id <MTLDevice>)device;

- (void)drawFrameNumber:(NSUInteger)frameNumber toView:(nonnull MTKView *)view;

- (void)updateDrawableSize:(CGSize)size;

@property (nonnull, readonly, nonatomic) id<MTLDevice> device;

@end
