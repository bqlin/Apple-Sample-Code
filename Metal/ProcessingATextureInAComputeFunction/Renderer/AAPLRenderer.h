/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for renderer class that performs Metal setup and per frame rendering.
*/

@import MetalKit;

// This is a platform-independent renderer class.
@interface AAPLRenderer : NSObject<MTKViewDelegate>

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;

@end
